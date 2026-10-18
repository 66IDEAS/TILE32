// The layout engine (architecture TA-3, TA-11, TA-12, TA-13): the only owner of layout
// state. In task T-0.24 it supports "Tile now"; automatic tiling follows in M1.
import CoreGraphics
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileLog
import TileSpaces

/// One layout per Space and display (TA-3). In fallback mode the Space is unknown.
public struct LayoutKey: Hashable, Sendable, CustomStringConvertible {
    public let space: SpaceID?
    public let display: DisplayID
    public var description: String { "\(space?.description ?? "unknown Space")@\(display.uuid)" }
}

/// One frame to write: the registry id, the window and the target frame.
public struct FrameAssignment: Sendable {
    public let id: WindowID
    public let window: WindowSnapshot
    public let frame: CGRect
}

/// Writes frames to real windows. A protocol so engine tests can use a fake (TA-24).
public protocol FrameWriting: Sendable {
    func write(_ assignments: [FrameAssignment]) async -> [WindowID: FrameWriteResult]
    /// Minimises or restores windows (rule L9). Returns the windows that failed.
    func setMinimised(_ windows: [(WindowID, WindowSnapshot)], _ minimised: Bool) async -> Set<WindowID>
}

/// The real writer: one batch per app on the app's own queue, apps in parallel (TA-11).
public struct AXFrameWriter: FrameWriting {
    public init() {}

    public func write(_ assignments: [FrameAssignment]) async -> [WindowID: FrameWriteResult] {
        let byApp = Dictionary(grouping: assignments) { $0.window.app.pid }
        return await withTaskGroup(of: [(WindowID, FrameWriteResult)].self) { group in
            for (pid, items) in byApp {
                group.addTask {
                    await AXWorker.shared.run(for: pid) {
                        items.map { item in
                            (item.id, FrameWriter.write(item.frame, to: item.window.element, pid: pid))
                        }
                    }
                }
            }
            var results: [WindowID: FrameWriteResult] = [:]
            for await batch in group {
                for (id, result) in batch { results[id] = result }
            }
            return results
        }
    }

    public func setMinimised(_ windows: [(WindowID, WindowSnapshot)], _ minimised: Bool) async -> Set<WindowID> {
        var failed: Set<WindowID> = []
        for (id, window) in windows {
            let error = await AXWorker.shared.run(for: window.app.pid) { WindowActions.setMinimised(window.element, minimised) }
            if error != .success { failed.insert(id) }
        }
        return failed
    }
}

/// A frame TILE32 wrote and expects to see again (TA-12).
public struct ExpectedFrame: Sendable, Equatable {
    public let frame: CGRect
    public let generation: UInt64
    public let deadline: ContinuousClock.Instant
}

public actor LayoutEngine {
    /// Gap between tiles and at the display edge (L7, UX-12).
    public static let gap: CGFloat = 6
    /// How long a written frame counts as "ours" (TA-12).
    public static let expectationWindow: Duration = .milliseconds(500)
    /// Frame differences below this are noise (TA-12).
    public static let frameTolerance: CGFloat = 2

    public private(set) var trees: [LayoutKey: LayoutTree] = [:]
    public private(set) var doesNotFit: Set<WindowID> = []
    /// Windows TILE32 minimised to respect a window limit (rule L9). Windows the user
    /// minimised are never in here, so TILE32 never brings those back (US-31.8).
    public private(set) var minimisedByEngine: Set<WindowID> = []
    /// Each window's frame before TILE32 first moved or minimised it (TA-18), with the
    /// snapshot needed to write it back.
    private var originals: [WindowID: (window: WindowSnapshot, frame: CGRect)] = [:]

    /// True when "Untile" has something to restore (US-24.6).
    public var canUntile: Bool { !originals.isEmpty }
    private var expected: [WindowID: ExpectedFrame] = [:]
    private var generation: UInt64 = 0
    private let writer: FrameWriting

    public init(writer: FrameWriting = AXFrameWriter()) {
        self.writer = writer
    }

    public struct TileSummary: Sendable, Equatable {
        public let layouts: Int
        public let windows: Int
        public let matched: Int
        public let doesNotFit: Int
        public let failed: Int
        /// Windows minimised to respect the window limit (rule L9).
        public var minimised: Int = 0
    }

    /// "Tile now" (US-4): equal columns per Space and display, ordered by each window's
    /// current left edge, inside the display's usable area. Floating, minimised and
    /// full-screen windows are not touched; no window changes display (US-4.2).
    public func tileNow(
        records: [WindowRecord],
        displays: DisplayTable,
        currentSpaces: [DisplayID: SpaceInfo],
        limits: WindowLimits = WindowLimits(),
        recency: [WindowID] = [],
        excludedBundleIDs: Set<String> = []
    ) async -> TileSummary {
        let tiled = records.filter { WindowClassifier.classify($0.snapshot, excludedBundleIDs: excludedBundleIDs) == .tiled }

        var groups: [LayoutKey: [WindowRecord]] = [:]
        for record in tiled {
            guard let displayID = record.display else { continue }
            groups[LayoutKey(space: currentSpaces[displayID]?.id, display: displayID), default: []].append(record)
        }

        // Remember where every window was before TILE32 touches it (TA-18).
        for record in tiled where originals[record.id] == nil {
            if let frame = record.snapshot.frame { originals[record.id] = (record.snapshot, frame) }
        }

        // Most recently used first (TA-27); windows the order does not know come last.
        let rank = Dictionary(recency.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        var batch: [FrameAssignment] = []
        var toMinimise: [(WindowID, WindowSnapshot)] = []
        for (key, all) in groups {
            guard let display = displays.display(id: key.display) else { continue }
            let byUse = all.sorted { (rank[$0.id] ?? .max, $0.id.raw) < (rank[$1.id] ?? .max, $1.id.raw) }
            let limit = limits.limit(for: display)
            let members = Array(byUse.prefix(limit))
            toMinimise += byUse.dropFirst(limit).map { ($0.id, $0.snapshot) }
            let ordered = members.sorted { ($0.snapshot.frame?.minX ?? 0, $0.id.raw) < ($1.snapshot.frame?.minX ?? 0, $1.id.raw) }
            let tree = LayoutTree.arranged(ordered.map(\.id), availableWidth: display.usableArea.width - Self.gap)
            trees[key] = tree
            let frames = tree.frames(in: display.usableArea, gap: Self.gap)
            for record in ordered {
                if let frame = frames[record.id] { batch.append(FrameAssignment(id: record.id, window: record.snapshot, frame: frame)) }
            }
        }
        var summary = await apply(batch, layouts: groups.count)
        if !toMinimise.isEmpty {
            let failed = await writer.setMinimised(toMinimise, true)
            let done = Set(toMinimise.map(\.0)).subtracting(failed)
            minimisedByEngine.formUnion(done)
            summary.minimised = done.count
            Log.layout.info("Minimised \(done.count) windows to make room, \(failed.count) failed")
        }
        return summary
    }

    /// Writes a batch, remembers the expected frames, and marks windows that do not fit (US-10).
    private func apply(_ batch: [FrameAssignment], layouts: Int) async -> TileSummary {
        generation += 1
        let deadline = ContinuousClock.now + Self.expectationWindow
        for item in batch {
            expected[item.id] = ExpectedFrame(frame: item.frame, generation: generation, deadline: deadline)
        }

        let results = await writer.write(batch)
        var matched = 0, notFitting = 0, failed = 0
        for item in batch {
            let id = item.id
            guard let result = results[id] else { failed += 1; continue }
            if result.doesNotFit {
                notFitting += 1
                doesNotFit.insert(id)
            } else {
                doesNotFit.remove(id)
                if result.fits { matched += 1 } else { failed += 1 }
            }
        }
        let summary = TileSummary(layouts: layouts, windows: batch.count, matched: matched, doesNotFit: notFitting, failed: failed)
        Log.layout.info("Tiled \(summary.windows) windows in \(summary.layouts) layouts: \(matched) matched, \(notFitting) do not fit, \(failed) failed")
        return summary
    }

    public struct UntileSummary: Sendable, Equatable {
        public let restored: Int
        public let unminimised: Int
        public let failed: Int
    }

    /// "Untile" (US-24): brings back the windows TILE32 minimised, writes every original
    /// frame back (moved into view if its display is gone), and forgets all layouts.
    public func untile(displays: DisplayTable) async -> UntileSummary {
        let toRestore = minimisedByEngine.compactMap { id in originals[id].map { (id, $0.window) } }
        let failedRestore = await writer.setMinimised(toRestore, false)
        minimisedByEngine.removeAll()

        let batch = originals.map { id, original in
            FrameAssignment(id: id, window: original.window, frame: displays.clampedIntoView(original.frame))
        }
        generation += 1
        let deadline = ContinuousClock.now + Self.expectationWindow
        for item in batch {
            expected[item.id] = ExpectedFrame(frame: item.frame, generation: generation, deadline: deadline)
        }
        let results = await writer.write(batch)
        let failed = batch.filter { results[$0.id]?.fits != true && results[$0.id]?.doesNotFit != true }.count

        originals.removeAll()
        trees.removeAll()
        doesNotFit.removeAll()
        let summary = UntileSummary(restored: batch.count - failed, unminimised: toRestore.count - failedRestore.count,
                                    failed: failed + failedRestore.count)
        Log.layout.info("Untile: \(summary.restored) restored, \(summary.unminimised) brought back, \(summary.failed) failed")
        return summary
    }

    /// True when a move or resize notification was caused by TILE32's own write (TA-12):
    /// the frame matches what was written, or it arrived before the deadline.
    public func isSelfCaused(_ id: WindowID, frame: CGRect, at instant: ContinuousClock.Instant = .now) -> Bool {
        guard let expectation = expected[id] else { return false }
        if instant <= expectation.deadline { return true }
        let a = expectation.frame
        return abs(a.minX - frame.minX) <= Self.frameTolerance && abs(a.minY - frame.minY) <= Self.frameTolerance
            && abs(a.width - frame.width) <= Self.frameTolerance && abs(a.height - frame.height) <= Self.frameTolerance
    }

    public func expectedFrame(of id: WindowID) -> ExpectedFrame? {
        expected[id]
    }
}
