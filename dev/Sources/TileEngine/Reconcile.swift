// The reconcile step (milestone M1): compares what is on the shown desktops with the stored
// layouts, and changes layouts and windows only where something changed. Every trigger
// (window opened or closed, desktop switch, display change, resume) ends up here.
import CoreGraphics
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileLog
import TileSpaces

/// One reading of the shown desktops.
public struct Observation: Sendable {
    /// The windows Accessibility listed (only the shown desktops, session A).
    public var records: [WindowRecord]
    public var displays: DisplayTable
    /// The Space shown on each display; empty in fallback mode (TA-16).
    public var currentSpaces: [DisplayID: SpaceInfo]
    /// Window numbers front to back: the order of use (TA-27).
    public var recency: [WindowID]
    /// Apps that did not answer in time. Their windows keep their tiles (TA-13).
    public var unansweredPIDs: Set<pid_t>
    /// Hidden apps (Cmd-H). Their windows leave the layout and come back later (US-8).
    public var hiddenPIDs: Set<pid_t>

    public init(records: [WindowRecord], displays: DisplayTable, currentSpaces: [DisplayID: SpaceInfo],
                recency: [WindowID] = [], unansweredPIDs: Set<pid_t> = [], hiddenPIDs: Set<pid_t> = []) {
        self.records = records
        self.displays = displays
        self.currentSpaces = currentSpaces
        self.recency = recency
        self.unansweredPIDs = unansweredPIDs
        self.hiddenPIDs = hiddenPIDs
    }
}

public struct ReconcileSummary: Sendable, Equatable {
    public var layouts = 0
    public var arrived = 0
    public var departed = 0
    public var written = 0
    public var matched = 0
    public var doesNotFit = 0
    public var failed = 0
    public var minimised = 0
    public var restored = 0

    public var changedAnything: Bool { written > 0 || minimised > 0 || restored > 0 }
}

extension LayoutEngine {
    /// Brings the layouts of the shown desktops in line with the observation and writes the
    /// frames that changed. With `rebuild`, every shown layout is arranged afresh ("Tile now").
    public func reconcile(
        _ observation: Observation,
        limits: WindowLimits = WindowLimits(),
        excludedBundleIDs: Set<String> = [],
        rebuild: Bool = false
    ) async -> ReconcileSummary {
        var summary = ReconcileSummary()
        let rank = Dictionary(observation.recency.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        func lastUsed(_ id: WindowID) -> Int { rank[id] ?? .max }

        // Layouts of displays that are gone are dropped; their windows show up elsewhere (US-9).
        trees = trees.filter { observation.displays.display(id: $0.key.display) != nil }

        var records: [WindowID: WindowRecord] = [:]
        var classes: [WindowID: Classification] = [:]
        for record in observation.records {
            records[record.id] = record
            windowPIDs[record.id] = record.snapshot.app.pid
            classes[record.id] = observation.hiddenPIDs.contains(record.snapshot.app.pid)
                ? .minimised
                : WindowClassifier.classify(record.snapshot, excludedBundleIDs: excludedBundleIDs)
            if classes[record.id] == .tiled, originals[record.id] == nil, let frame = record.snapshot.frame {
                originals[record.id] = (record.snapshot, frame)
            }
        }

        // A window TILE32 minimised that the user brought back is an arrival (US-31.4).
        for id in minimisedByEngine where classes[id] == .tiled {
            forgetMinimised(id)
        }

        var toMinimise: [(WindowID, WindowSnapshot, LayoutKey)] = []
        var toRestore: [(WindowID, WindowSnapshot)] = []

        for display in observation.displays.displays {
            let space = observation.currentSpaces[display.id]
            // A full-screen Space has no layout (US-30.1).
            if space?.isFullScreen == true { continue }
            let key = LayoutKey(space: space?.id, display: display.id)
            let limit = limits.limit(for: display)
            let observed = observation.records
                .filter { $0.display == display.id && classes[$0.id] == .tiled }
                .sorted { ($0.snapshot.frame?.minX ?? 0, $0.id.raw) < ($1.snapshot.frame?.minX ?? 0, $1.id.raw) }
            let observedIDs = Set(observed.map(\.id))

            guard !rebuild, var tree = trees[key] else {
                // First visit, or "Tile now": a fresh arrangement with the limit.
                guard !observed.isEmpty else { trees[key] = nil; continue }
                let byUse = observed.sorted { (lastUsed($0.id), $0.id.raw) < (lastUsed($1.id), $1.id.raw) }
                let members = Set(byUse.prefix(limit).map(\.id))
                toMinimise += byUse.dropFirst(limit).map { ($0.id, $0.snapshot, key) }
                let ordered = observed.filter { members.contains($0.id) }.map(\.id)
                trees[key] = LayoutTree.arranged(ordered, availableWidth: display.usableArea.width - Self.gap)
                for id in ordered { returnHints[id] = nil }
                summary.layouts += 1
                continue
            }

            // Departures: closed, minimised, hidden, full screen, moved to another desktop.
            for id in tree.windowIDs where !observedIDs.contains(id) {
                if let pid = windowPIDs[id], observation.unansweredPIDs.contains(pid) { continue }
                if let cls = classes[id], cls == .minimised || cls == .floating(.fullScreen), let hint = tree.returnHint(for: id) {
                    returnHints[id] = (hint, key)
                }
                tree = tree.removing(id)
                lastTile[id] = nil
                retries[id] = nil
                summary.departed += 1
            }

            // Arrivals: new windows, windows coming back, windows moved here.
            let arrivals = observed.filter { !tree.contains($0.id) }
            let arrivalIDs = Set(arrivals.map(\.id))
            for record in arrivals {
                let id = record.id
                if tree.windowIDs.count >= limit,
                   let victim = tree.windowIDs.filter({ !arrivalIDs.contains($0) }).max(by: { lastUsed($0) < lastUsed($1) }),
                   let victimRecord = records[victim] {
                    // A full layout: the arrival takes the least recently used tile (US-31.4, US-31.5).
                    tree = tree.replacing(victim, with: id)
                    toMinimise.append((victim, victimRecord.snapshot, key))
                } else if let stored = returnHints[id], stored.key == key, tree.contains(stored.hint.sibling) {
                    tree = tree.splitting(target: stored.hint.sibling, with: id, zone: stored.hint.zone)
                } else {
                    tree = tree.appending(id, availableWidth: display.usableArea.width - Self.gap)
                }
                returnHints[id] = nil
                summary.arrived += 1
            }

            // A lowered limit minimises the least recently used windows at once (US-31.7).
            while tree.windowIDs.count > limit,
                  let victim = tree.windowIDs.max(by: { lastUsed($0) < lastUsed($1) }),
                  let victimRecord = records[victim] {
                tree = tree.removing(victim)
                toMinimise.append((victim, victimRecord.snapshot, key))
            }

            // Freed tiles bring back windows TILE32 minimised, most recent first (US-31.6).
            while tree.windowIDs.count < limit,
                  let back = minimisedOrder.last(where: { minimisedKeys[$0] == key }),
                  let snapshot = minimisedSnapshots[back] {
                toRestore.append((back, snapshot))
                tree = tree.appending(back, availableWidth: display.usableArea.width - Self.gap)
                forgetMinimised(back)
                summary.restored += 1
            }

            trees[key] = tree.isEmpty ? nil : tree
            summary.layouts += 1
        }

        let restoredSnapshots = Dictionary(toRestore.map { ($0.0, $0.1) }, uniquingKeysWith: { first, _ in first })

        // Frames: write a window when its tile changed, or when it moved away from its tile
        // (put back at most `maximumRetries` times, TA-12).
        var batch: [FrameAssignment] = []
        for display in observation.displays.displays {
            let space = observation.currentSpaces[display.id]
            if space?.isFullScreen == true { continue }
            guard let tree = trees[LayoutKey(space: space?.id, display: display.id)] else { continue }
            for (id, frame) in tree.frames(in: display.usableArea, gap: Self.gap) {
                guard let snapshot = records[id]?.snapshot ?? restoredSnapshots[id] else { continue }
                let tileChanged = lastTile[id].map { !Self.close($0, frame) } ?? true
                if tileChanged {
                    retries[id] = 0
                    if let current = snapshot.frame, Self.close(current, frame) {
                        lastTile[id] = frame
                        continue
                    }
                    batch.append(FrameAssignment(id: id, window: snapshot, frame: frame))
                    continue
                }
                guard !doesNotFit.contains(id), let current = snapshot.frame, !Self.close(current, frame, tolerance: FrameWriteResult.stepTolerance) else { continue }
                let attempts = retries[id] ?? 0
                guard attempts < Self.maximumRetries else { continue }
                retries[id] = attempts + 1
                batch.append(FrameAssignment(id: id, window: snapshot, frame: frame))
            }
        }
        // Windows that come back get their frame while still minimised, then are restored, so
        // they animate straight into their tile; writing during the restore animation fails
        // (found in the owner's step 9 check).
        let written = await apply(batch)
        if !toRestore.isEmpty {
            let failed = await writer.setMinimised(toRestore, false)
            if !failed.isEmpty { Log.layout.info("Bringing back \(failed.count) windows failed") }
        }
        summary.written = batch.count
        summary.matched = written.matched
        summary.doesNotFit = written.doesNotFit
        summary.failed = written.failed
        summary.minimised = await minimise(toMinimise)

        if summary.changedAnything || summary.arrived > 0 || summary.departed > 0 {
            Log.layout.info("""
                Reconcile: \(summary.arrived) arrived, \(summary.departed) departed, \(summary.written) written, \
                \(summary.minimised) minimised, \(summary.restored) brought back
                """)
        }
        return summary
    }
}
