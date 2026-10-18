import ApplicationServices
import CoreGraphics
import Foundation
import Testing
@testable import TileAX
@testable import TileCore
@testable import TileEngine
@testable import TileGeometry
@testable import TileSpaces

private let dell = DisplayID(uuid: "DELL")
private let laptop = DisplayID(uuid: "LAPTOP")
private let displays = DisplayTable(screens: [
    ScreenDescriptor(id: dell, number: 4, name: "Dell U4924DW",
                     frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: CGRect(x: 0, y: 57, width: 5120, height: 1353)),
    ScreenDescriptor(id: laptop, number: 1, name: "Built-in Retina Display",
                     frame: CGRect(x: -1728, y: 88, width: 1728, height: 1117), visibleFrame: CGRect(x: -1728, y: 88, width: 1728, height: 1085)),
])
private let space = SpaceInfo(id: SpaceID(4), uuid: "U4", type: 0, desktopNumber: 2)

/// Records every write and answers with configurable results.
private final class FakeWriter: FrameWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var _written: [WindowID: CGRect] = [:]
    /// Windows that keep this size whatever is requested (minimum size, US-10).
    let minimumSizes: [WindowID: CGSize]

    init(minimumSizes: [WindowID: CGSize] = [:]) { self.minimumSizes = minimumSizes }

    var written: [WindowID: CGRect] { lock.withLock { _written } }

    func write(_ assignments: [FrameAssignment]) async -> [WindowID: FrameWriteResult] {
        var results: [WindowID: FrameWriteResult] = [:]
        for item in assignments {
            var actual = item.frame
            if let minimum = minimumSizes[item.id] {
                actual.size = CGSize(width: max(minimum.width, actual.width), height: max(minimum.height, actual.height))
            }
            lock.withLock { _written[item.id] = item.frame }
            results[item.id] = FrameWriteResult(requested: item.frame, actual: actual, positionError: .success,
                                                sizeError: .success, duration: .milliseconds(1))
        }
        return results
    }

    private var _minimised: Set<WindowID> = []
    var minimised: Set<WindowID> { lock.withLock { _minimised } }

    func setMinimised(_ windows: [(WindowID, WindowSnapshot)], _ minimised: Bool) async -> Set<WindowID> {
        lock.withLock {
            for (id, _) in windows {
                if minimised { _minimised.insert(id) } else { _minimised.remove(id) }
            }
        }
        return []
    }
}

private func record(_ number: UInt64, x: CGFloat, display: DisplayID, subrole: String = "AXStandardWindow", fullScreen: Bool = false) -> WindowRecord {
    let snapshot = WindowSnapshot(
        app: AppInfo(pid: 4242, bundleID: "com.example.app", name: "App"),
        element: AXElementBox(AXUIElementCreateApplication(pid_t(number))),
        windowNumber: CGWindowID(number), role: "AXWindow", subrole: subrole, title: "",
        frame: CGRect(x: x, y: 300, width: 800, height: 600),
        isMinimized: false, isFullScreen: fullScreen, isModal: false, isResizable: true
    )
    return WindowRecord(id: WindowID(number), snapshot: snapshot, display: display, spaces: [SpaceID(4)])
}

@Suite("Layout engine: Tile now (US-4, TA-12)")
struct LayoutEngineTests {
    @Test func equalColumnsPerDisplayOrderedByLeftEdge() async {
        let writer = FakeWriter()
        let engine = LayoutEngine(writer: writer)
        let summary = await engine.tileNow(
            records: [record(3, x: 3000, display: dell), record(1, x: 100, display: dell), record(2, x: 1500, display: dell),
                      record(9, x: -1000, display: laptop)],
            displays: displays, currentSpaces: [dell: space, laptop: space]
        )
        #expect(summary == LayoutEngine.TileSummary(layouts: 2, windows: 4, matched: 4, doesNotFit: 0, failed: 0))

        let written = writer.written
        // Dell usable area in AX coordinates: (0, 30, 5120, 1353); three columns with 6 point gaps.
        #expect(written[WindowID(1)]!.minX < written[WindowID(2)]!.minX)
        #expect(written[WindowID(2)]!.minX < written[WindowID(3)]!.minX)
        #expect(written[WindowID(1)]!.minX == 6)
        #expect(written[WindowID(1)]!.minY == 36)
        #expect(written[WindowID(3)]!.maxX == 5114)
        // The laptop window stays on the laptop and fills its usable area.
        #expect(written[WindowID(9)] == CGRect(x: -1722, y: 273, width: 1716, height: 1073))

        let trees = await engine.trees
        #expect(trees[LayoutKey(space: SpaceID(4), display: dell)]?.windowIDs == [WindowID(1), WindowID(2), WindowID(3)])
    }

    @Test func floatingAndFullScreenWindowsAreNotTouched() async {
        let writer = FakeWriter()
        let engine = LayoutEngine(writer: writer)
        _ = await engine.tileNow(
            records: [record(1, x: 100, display: dell), record(2, x: 200, display: dell, subrole: "AXDialog"),
                      record(3, x: 300, display: dell, fullScreen: true)],
            displays: displays, currentSpaces: [dell: space]
        )
        #expect(Set(writer.written.keys) == [WindowID(1)])
    }

    @Test func excludedAppsAreNotTouched() async {
        let writer = FakeWriter()
        let engine = LayoutEngine(writer: writer)
        _ = await engine.tileNow(records: [record(1, x: 100, display: dell)], displays: displays,
                                 currentSpaces: [dell: space], excludedBundleIDs: ["com.example.app"])
        #expect(writer.written.isEmpty)
    }

    @Test func windowsThatCannotShrinkAreMarked() async {
        let writer = FakeWriter(minimumSizes: [WindowID(2): CGSize(width: 3000, height: 1000)])
        let engine = LayoutEngine(writer: writer)
        let summary = await engine.tileNow(
            records: [record(1, x: 100, display: dell), record(2, x: 1500, display: dell), record(3, x: 3000, display: dell)],
            displays: displays, currentSpaces: [dell: space]
        )
        #expect(summary.doesNotFit == 1)
        #expect(await engine.doesNotFit == [WindowID(2)])
    }

    @Test func fallbackModeUsesUnknownSpace() async {
        let engine = LayoutEngine(writer: FakeWriter())
        _ = await engine.tileNow(records: [record(1, x: 100, display: dell)], displays: displays, currentSpaces: [:])
        #expect(await engine.trees[LayoutKey(space: nil, display: dell)] != nil)
    }

    @Test func ownWritesAreRecognised() async {
        let engine = LayoutEngine(writer: FakeWriter())
        _ = await engine.tileNow(records: [record(1, x: 100, display: dell)], displays: displays, currentSpaces: [dell: space])
        let expected = await engine.expectedFrame(of: WindowID(1))!
        // Within the deadline anything counts as ours; afterwards only the written frame.
        #expect(await engine.isSelfCaused(WindowID(1), frame: .zero, at: expected.deadline))
        let later = expected.deadline + .seconds(1)
        #expect(await engine.isSelfCaused(WindowID(1), frame: expected.frame.offsetBy(dx: 1, dy: 1), at: later))
        #expect(await !engine.isSelfCaused(WindowID(1), frame: expected.frame.offsetBy(dx: 50, dy: 0), at: later))
        #expect(await !engine.isSelfCaused(WindowID(99), frame: .zero, at: later))
    }
}

@Suite("Window limit (L9, US-31)")
struct WindowLimitTests {
    @Test func defaultsFollowDisplayWidth() {
        let limits = WindowLimits()
        #expect(limits.limit(for: displays.display(id: dell)!) == 12)
        #expect(limits.limit(for: displays.display(id: laptop)!) == 6)
    }

    @Test func chosenLimitsAreClamped() {
        var limits = WindowLimits()
        limits.set(40, for: dell)
        limits.set(1, for: laptop)
        #expect(limits.limit(for: displays.display(id: dell)!) == 16)
        #expect(limits.limit(for: displays.display(id: laptop)!) == 2)
        #expect(WindowLimits(chosen: ["DELL": 99]).chosen.isEmpty)
    }

    @Test func limitsSurviveARestart() {
        let suite = "com.66ideas.tile32.tests.\(UInt64.random(in: 0...UInt64.max))"
        let store = WindowLimitStore(suiteName: suite)
        var limits = store.load()
        limits.set(4, for: dell)
        store.save(limits)
        #expect(WindowLimitStore(suiteName: suite).load().limit(for: displays.display(id: dell)!) == 4)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    @Test func mostRecentWindowsGetTilesAndTheRestIsMinimised() async {
        let writer = FakeWriter()
        let engine = LayoutEngine(writer: writer)
        var limits = WindowLimits()
        limits.set(2, for: dell)
        let summary = await engine.tileNow(
            records: [record(1, x: 100, display: dell), record(2, x: 900, display: dell),
                      record(3, x: 1700, display: dell), record(4, x: 2500, display: dell)],
            displays: displays, currentSpaces: [dell: space], limits: limits,
            recency: [WindowID(3), WindowID(1), WindowID(4), WindowID(2)]
        )
        #expect(summary.windows == 2)
        #expect(summary.minimised == 2)
        #expect(Set(writer.written.keys) == [WindowID(1), WindowID(3)])
        #expect(writer.minimised == [WindowID(2), WindowID(4)])
        #expect(await engine.minimisedByEngine == [WindowID(2), WindowID(4)])
        // The tiled windows keep their left-to-right order.
        #expect(await engine.trees[LayoutKey(space: SpaceID(4), display: dell)]?.windowIDs == [WindowID(1), WindowID(3)])
    }

    @Test func windowsTheOrderDoesNotKnowComeLast() async {
        let writer = FakeWriter()
        let engine = LayoutEngine(writer: writer)
        var limits = WindowLimits()
        limits.set(2, for: dell)
        _ = await engine.tileNow(
            records: [record(1, x: 100, display: dell), record(2, x: 900, display: dell), record(3, x: 1700, display: dell)],
            displays: displays, currentSpaces: [dell: space], limits: limits, recency: [WindowID(3)]
        )
        #expect(Set(writer.written.keys) == [WindowID(1), WindowID(3)])
        #expect(writer.minimised == [WindowID(2)])
    }
}
