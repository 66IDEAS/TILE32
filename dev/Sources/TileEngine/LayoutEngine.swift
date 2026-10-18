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
    }

    /// "Tile now" (US-4): equal columns per Space and display, ordered by each window's
    /// current left edge, inside the display's usable area. Floating, minimised and
    /// full-screen windows are not touched; no window changes display (US-4.2).
    public func tileNow(
        records: [WindowRecord],
        displays: DisplayTable,
        currentSpaces: [DisplayID: SpaceInfo],
        excludedBundleIDs: Set<String> = []
    ) async -> TileSummary {
        let tiled = records.filter { WindowClassifier.classify($0.snapshot, excludedBundleIDs: excludedBundleIDs) == .tiled }

        var groups: [LayoutKey: [WindowRecord]] = [:]
        for record in tiled {
            guard let displayID = record.display else { continue }
            groups[LayoutKey(space: currentSpaces[displayID]?.id, display: displayID), default: []].append(record)
        }

        var batch: [FrameAssignment] = []
        for (key, members) in groups {
            guard let display = displays.display(id: key.display) else { continue }
            let ordered = members.sorted { ($0.snapshot.frame?.minX ?? 0, $0.id.raw) < ($1.snapshot.frame?.minX ?? 0, $1.id.raw) }
            let tree = LayoutTree.flat(ordered.map(\.id))
            trees[key] = tree
            let frames = tree.frames(in: display.usableArea, gap: Self.gap)
            for record in ordered {
                if let frame = frames[record.id] { batch.append(FrameAssignment(id: record.id, window: record.snapshot, frame: frame)) }
            }
        }
        return await apply(batch, layouts: groups.count)
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
                if result.matches { matched += 1 } else { failed += 1 }
            }
        }
        let summary = TileSummary(layouts: layouts, windows: batch.count, matched: matched, doesNotFit: notFitting, failed: failed)
        Log.layout.info("Tiled \(summary.windows) windows in \(summary.layouts) layouts: \(matched) matched, \(notFitting) do not fit, \(failed) failed")
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
