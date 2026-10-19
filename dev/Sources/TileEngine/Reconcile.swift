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
    /// The Spaces of every window the window server knows, also those Accessibility did not
    /// list. Empty in fallback mode and in most tests; then the mid-switch check is skipped.
    public var knownSpaces: [WindowID: [SpaceID]]

    public init(records: [WindowRecord], displays: DisplayTable, currentSpaces: [DisplayID: SpaceInfo],
                recency: [WindowID] = [], unansweredPIDs: Set<pid_t> = [], hiddenPIDs: Set<pid_t> = [],
                knownSpaces: [WindowID: [SpaceID]] = [:]) {
        self.records = records
        self.displays = displays
        self.currentSpaces = currentSpaces
        self.recency = recency
        self.unansweredPIDs = unansweredPIDs
        self.hiddenPIDs = hiddenPIDs
        self.knownSpaces = knownSpaces
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
    /// The reading mixed two desktops and nothing was changed; read again shortly.
    public var heldMidSwitch = false
    /// A layout changed, also without any window moving (a tab replaced, a first visit
    /// taken from the screen). Remembered layouts are saved after such a run.
    public var layoutsChanged = false

    public var changedAnything: Bool { written > 0 || minimised > 0 || restored > 0 }
}

extension LayoutEngine {
    /// Brings the layouts of the shown desktops in line with the observation and writes the
    /// frames that changed. With `rebuild`, every shown layout is arranged afresh ("Tile now").
    public func reconcile(
        _ observation: Observation,
        limits: WindowLimits = WindowLimits(),
        excludedBundleIDs: Set<String> = [],
        rebuild: Bool = false,
        acceptMidSwitch: Bool = false
    ) async -> ReconcileSummary {
        var summary = ReconcileSummary()
        let treesBefore = trees
        if !acceptMidSwitch, let reason = midSwitchReason(observation) {
            Log.layout.info("Reading mixes two desktops (\(reason, privacy: .public)), waiting")
            summary.heldMidSwitch = true
            return summary
        }
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

            // First visit: the arrangement on screen or the remembered one, so nothing jumps
            // after a restart (US-26). Windows not in it join as new windows.
            if !rebuild, trees[key] == nil, !observed.isEmpty,
               let (first, source) = firstVisitTree(for: key, space: space, display: display, observed: observed) {
                Log.layout.info("First visit of \(key.description, privacy: .public): \(source, privacy: .public)")
                var tree = first
                for record in observed where !tree.contains(record.id) {
                    tree = tree.appending(record.id, availableWidth: display.usableArea.width - Self.gap)
                }
                trees[key] = tree
            }

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

            // Tabs: another tab of the same app took the window's place (new, closed or chosen tab).
            for (old, new) in tabReplacements(in: tree, candidates: observed) {
                tree = tree.replacing(old, with: new)
                lastTile[new] = lastTile[old]
                lastTile[old] = nil
                retries[old] = nil
                ignoredWrites.remove(old)
                returnHints[new] = nil
                Log.layout.info("Tab \(new.description, privacy: .public) takes the tile of \(old.description, privacy: .public)")
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
                ignoredWrites.remove(id)
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

        var snapshots = restoredSnapshots
        for (id, record) in records { snapshots[id] = record.snapshot }
        let batch = frameBatch(displays: observation.displays, currentSpaces: observation.currentSpaces, snapshots: snapshots)
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
        summary.layoutsChanged = trees != treesBefore
        return summary
    }

    /// Tabs (Finder, Safari, Terminal and others) are separate windows, and only the front
    /// tab is listed. A new tab, a closed tab or another chosen tab replaces the listed window
    /// by another window of the same app in the same frame. That window takes over the tile
    /// instead of joining at the end (found by the owner on 2026-10-19: Cmd-T in Finder moved
    /// Finder to the end of the layout). Returns pairs of the vanished and the new window.
    func tabReplacements(in tree: LayoutTree, candidates: [WindowRecord]) -> [(old: WindowID, new: WindowID)] {
        let listed = Set(candidates.map(\.id))
        var free = candidates.filter { record in !trees.values.contains { $0.contains(record.id) } && !tree.contains(record.id) }
        var result: [(old: WindowID, new: WindowID)] = []
        for old in tree.windowIDs where !listed.contains(old) {
            guard let pid = windowPIDs[old], let tile = lastTile[old],
                  let index = free.firstIndex(where: { record in
                      record.snapshot.app.pid == pid
                          && record.snapshot.frame.map { Self.close($0, tile, tolerance: FrameWriteResult.stepTolerance) } == true
                  }) else { continue }
            result.append((old, free[index].id))
            free.remove(at: index)
        }
        return result
    }

    /// Why the reading belongs to a desktop switch in progress, or nil when it is consistent.
    /// macOS reports the new Space at once, but Accessibility lists the old desktop's windows
    /// for a moment and the new desktop's windows only afterwards. Taken as it is, such a
    /// reading removes the shown windows and adds them again in another order (found by the
    /// owner on 2026-10-19: the windows of desktop 2 swapped places after a switch).
    func midSwitchReason(_ observation: Observation) -> String? {
        guard !observation.currentSpaces.isEmpty else { return nil }
        // A listed window that the window server places on a desktop no display shows.
        let shown = Set(observation.currentSpaces.values.map(\.id))
        for record in observation.records {
            guard !record.spaces.isEmpty,
                  !observation.hiddenPIDs.contains(record.snapshot.app.pid),
                  WindowClassifier.classify(record.snapshot) == .tiled else { continue }
            if shown.isDisjoint(with: record.spaces) {
                return "\(record.id.description) listed but on \(record.spaces.map(\.description).joined(separator: ","))"
            }
        }
        // A tiled window of the shown desktop that is still there but not listed yet.
        guard !observation.knownSpaces.isEmpty else { return nil }
        let listed = Set(observation.records.map(\.id))
        for display in observation.displays.displays {
            guard let current = observation.currentSpaces[display.id],
                  let tree = trees[LayoutKey(space: current.id, display: display.id)] else { continue }
            let tiledHere = observation.records.filter {
                $0.display == display.id && WindowClassifier.classify($0.snapshot) == .tiled
            }
            // A tab hidden behind another tab stays on the desktop without being listed.
            let replacedTabs = Set(tabReplacements(in: tree, candidates: tiledHere).map(\.old))
            for id in tree.windowIDs where !listed.contains(id) && !replacedTabs.contains(id) {
                if let pid = windowPIDs[id], observation.unansweredPIDs.contains(pid) || observation.hiddenPIDs.contains(pid) {
                    continue
                }
                if observation.knownSpaces[id]?.contains(current.id) == true {
                    return "\(id.description) on \(current.id.description) but not listed"
                }
            }
        }
        return nil
    }

    /// The frames to write for the shown layouts (TA-12): a window is written when its tile
    /// changed, or when it moved away from its tile (put back at most `maximumRetries` times,
    /// or `maximumWriteRetries` times when the app ignored the last write).
    /// Windows in `force` are always written, for example a window the user just dropped.
    func frameBatch(displays: DisplayTable, currentSpaces: [DisplayID: SpaceInfo],
                    snapshots: [WindowID: WindowSnapshot], force: Set<WindowID> = []) -> [FrameAssignment] {
        var batch: [FrameAssignment] = []
        for display in displays.displays {
            let space = currentSpaces[display.id]
            if space?.isFullScreen == true { continue }
            guard let tree = trees[LayoutKey(space: space?.id, display: display.id)] else { continue }
            for (id, frame) in tree.frames(in: display.usableArea, gap: Self.gap) {
                guard let snapshot = snapshots[id] else { continue }
                if force.contains(id) {
                    retries[id] = 0
                    batch.append(FrameAssignment(id: id, window: snapshot, frame: frame))
                    continue
                }
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
                guard !doesNotFit.contains(id), let current = snapshot.frame,
                      !Self.close(current, frame, tolerance: FrameWriteResult.stepTolerance) else { continue }
                let attempts = retries[id] ?? 0
                let limit = ignoredWrites.contains(id) ? Self.maximumWriteRetries : Self.maximumRetries
                guard attempts < limit else { continue }
                retries[id] = attempts + 1
                batch.append(FrameAssignment(id: id, window: snapshot, frame: frame))
            }
        }
        return batch
    }
}
