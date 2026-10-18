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
    /// How often TILE32 puts back a window that moved away from its tile, before leaving it
    /// alone until its tile changes (TA-12: never fight an app).
    public static let maximumRetries = 1

    public internal(set) var trees: [LayoutKey: LayoutTree] = [:]
    public internal(set) var doesNotFit: Set<WindowID> = []
    /// Windows TILE32 minimised to respect a window limit (rule L9). Windows the user
    /// minimised are never in here, so TILE32 never brings those back (US-31.8).
    public internal(set) var minimisedByEngine: Set<WindowID> = []

    /// True when "Untile" has something to restore (US-24.6).
    public var canUntile: Bool { !originals.isEmpty }

    // Internal state, shared with the reconcile step in Reconcile.swift.
    /// Each window's frame before TILE32 first moved or minimised it (TA-18), with the
    /// snapshot needed to write it back.
    var originals: [WindowID: (window: WindowSnapshot, frame: CGRect)] = [:]
    var expected: [WindowID: ExpectedFrame] = [:]
    var generation: UInt64 = 0
    let writer: FrameWriting
    /// The tile each window was last written to; a window is only written again when its
    /// tile changes or it moved away from it (TA-12).
    var lastTile: [WindowID: CGRect] = [:]
    /// Put-backs per window for its current tile (TA-12).
    var retries: [WindowID: Int] = [:]
    /// Where a window that left a layout (minimised, hidden, full screen) comes back (TA-9).
    var returnHints: [WindowID: (hint: ReturnHint, key: LayoutKey)] = [:]
    /// The layout a window minimised by TILE32 belongs to, and the order of minimising
    /// (most recent last), so freed tiles are refilled in the right order (US-31.6).
    var minimisedKeys: [WindowID: LayoutKey] = [:]
    var minimisedOrder: [WindowID] = []
    var minimisedSnapshots: [WindowID: WindowSnapshot] = [:]
    /// The app of every window seen, to keep windows of apps that did not answer.
    var windowPIDs: [WindowID: pid_t] = [:]
    /// The last write durations per app, for the slow-app rule of live resizing (TA-25).
    var writeDurations: [pid_t: [Duration]] = [:]
    /// Apps slower than this on average over their last five writes do not follow a live
    /// resize; their windows are written on release (TA-25, open question OQ-9).
    public static let slowAppLimit: Duration = .milliseconds(50)

    func isSlow(_ pid: pid_t) -> Bool {
        guard let durations = writeDurations[pid], !durations.isEmpty else { return false }
        let total = durations.reduce(Duration.zero, +)
        return total / durations.count > Self.slowAppLimit
    }

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

    /// "Tile now" (US-4): a fresh arrangement (rule L2) of every shown layout, ordered by each
    /// window's current left edge, with the window limit (rule L9). Floating, minimised and
    /// full-screen windows are not touched; no window changes display (US-4.2).
    public func tileNow(
        records: [WindowRecord],
        displays: DisplayTable,
        currentSpaces: [DisplayID: SpaceInfo],
        limits: WindowLimits = WindowLimits(),
        recency: [WindowID] = [],
        excludedBundleIDs: Set<String> = []
    ) async -> TileSummary {
        let observation = Observation(records: records, displays: displays, currentSpaces: currentSpaces, recency: recency)
        let summary = await reconcile(observation, limits: limits, excludedBundleIDs: excludedBundleIDs, rebuild: true)
        return TileSummary(layouts: summary.layouts, windows: summary.written, matched: summary.matched,
                           doesNotFit: summary.doesNotFit, failed: summary.failed, minimised: summary.minimised)
    }

    /// Writes a batch, remembers the expected frames and tiles, and marks windows that do not
    /// fit (US-10). Returns how many fitted, did not fit, and failed.
    func apply(_ batch: [FrameAssignment]) async -> (matched: Int, doesNotFit: Int, failed: Int) {
        guard !batch.isEmpty else { return (0, 0, 0) }
        generation += 1
        let deadline = ContinuousClock.now + Self.expectationWindow
        for item in batch {
            expected[item.id] = ExpectedFrame(frame: item.frame, generation: generation, deadline: deadline)
            lastTile[item.id] = item.frame
        }

        let results = await writer.write(batch)
        var matched = 0, notFitting = 0, failed = 0
        for item in batch {
            let id = item.id
            guard let result = results[id] else { failed += 1; continue }
            writeDurations[item.window.app.pid, default: []].append(result.duration)
            if writeDurations[item.window.app.pid]!.count > 5 { writeDurations[item.window.app.pid]!.removeFirst() }
            if result.doesNotFit {
                notFitting += 1
                doesNotFit.insert(id)
            } else {
                doesNotFit.remove(id)
                if result.fits { matched += 1 } else { failed += 1 }
            }
        }
        Log.layout.info("Wrote \(batch.count) frames: \(matched) fit, \(notFitting) do not fit, \(failed) failed")
        return (matched, notFitting, failed)
    }

    /// Minimises windows to make room and remembers which layout they belong to (rule L9).
    func minimise(_ windows: [(WindowID, WindowSnapshot, LayoutKey)]) async -> Int {
        guard !windows.isEmpty else { return 0 }
        let failed = await writer.setMinimised(windows.map { ($0.0, $0.1) }, true)
        var done = 0
        for (id, snapshot, key) in windows where !failed.contains(id) {
            minimisedByEngine.insert(id)
            minimisedKeys[id] = key
            minimisedSnapshots[id] = snapshot
            minimisedOrder.removeAll { $0 == id }
            minimisedOrder.append(id)
            lastTile[id] = nil
            done += 1
        }
        Log.layout.info("Minimised \(done) windows to make room, \(failed.count) failed")
        return done
    }

    /// Forgets that TILE32 minimised a window (it came back, or it is gone).
    func forgetMinimised(_ id: WindowID) {
        minimisedByEngine.remove(id)
        minimisedKeys[id] = nil
        minimisedSnapshots[id] = nil
        minimisedOrder.removeAll { $0 == id }
    }

    public struct UntileSummary: Sendable, Equatable {
        public let restored: Int
        public let unminimised: Int
        public let failed: Int
    }

    /// "Untile" (US-24): brings back the windows TILE32 minimised, writes every original
    /// frame back (moved into view if its display is gone), and forgets all layouts.
    /// Windows on hidden desktops are restored too, through the element read while they
    /// were visible (session A).
    public func untile(displays: DisplayTable) async -> UntileSummary {
        let toRestore = minimisedByEngine.compactMap { id in
            (minimisedSnapshots[id] ?? originals[id]?.window).map { (id, $0) }
        }
        let failedRestore = await writer.setMinimised(toRestore, false)

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
        minimisedByEngine.removeAll()
        minimisedKeys.removeAll()
        minimisedOrder.removeAll()
        minimisedSnapshots.removeAll()
        lastTile.removeAll()
        retries.removeAll()
        returnHints.removeAll()
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
        return Self.close(expectation.frame, frame)
    }

    public func expectedFrame(of id: WindowID) -> ExpectedFrame? {
        expected[id]
    }

    static func close(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = frameTolerance) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
