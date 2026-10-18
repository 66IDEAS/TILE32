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
private let bothDisplays = DisplayTable(screens: [
    ScreenDescriptor(id: dell, number: 4, name: "Dell U4924DW",
                     frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: CGRect(x: 0, y: 57, width: 5120, height: 1353)),
    ScreenDescriptor(id: laptop, number: 1, name: "Built-in Retina Display",
                     frame: CGRect(x: -1728, y: 88, width: 1728, height: 1117), visibleFrame: CGRect(x: -1728, y: 88, width: 1728, height: 1085)),
])
private let onlyDell = DisplayTable(screens: [bothDisplays.displays.count > 0 ? ScreenDescriptor(
    id: dell, number: 4, name: "Dell U4924DW",
    frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: CGRect(x: 0, y: 57, width: 5120, height: 1353)) : nil].compactMap { $0 })
private let desktop2 = SpaceInfo(id: SpaceID(4), uuid: "U4", type: 0, desktopNumber: 2)
private let desktop3 = SpaceInfo(id: SpaceID(5), uuid: "U5", type: 0, desktopNumber: 3)
private let fullScreenSpace = SpaceInfo(id: SpaceID(903), uuid: "F", type: 4, desktopNumber: nil)

/// A simulated set of windows. The writer changes it the way macOS would.
private final class World: FrameWriting, @unchecked Sendable {
    struct Window {
        var pid: pid_t = 100
        var bundleID = "com.example.app"
        var frame: CGRect
        var space: SpaceID = SpaceID(4)
        var minimised = false
        var fullScreen = false
        var minimumSize: CGSize = .zero
    }

    private let lock = NSLock()
    private var windows: [UInt64: Window] = [:]
    private var _writes = 0

    var writes: Int { lock.withLock { _writes } }

    func add(_ number: UInt64, x: CGFloat, y: CGFloat = 300, width: CGFloat = 800, pid: pid_t = 100,
             space: SpaceID = SpaceID(4), minimumSize: CGSize = .zero) {
        lock.withLock {
            windows[number] = Window(pid: pid, frame: CGRect(x: x, y: y, width: width, height: 600), space: space, minimumSize: minimumSize)
        }
    }

    func update(_ number: UInt64, _ change: (inout Window) -> Void) {
        lock.withLock { if var window = windows[number] { change(&window); windows[number] = window } }
    }

    func remove(_ number: UInt64) { lock.withLock { _ = windows.removeValue(forKey: number) } }

    func window(_ number: UInt64) -> Window? { lock.withLock { windows[number] } }

    /// What TILE32 would read: Accessibility lists only the shown desktop, plus minimised windows.
    func observe(space: SpaceInfo = desktop2, displays: DisplayTable = bothDisplays, recency: [UInt64] = [],
                 unanswered: Set<pid_t> = [], hidden: Set<pid_t> = []) -> Observation {
        let snapshot = lock.withLock { windows }
        let records = snapshot.filter { $0.value.space == space.id || $0.value.minimised }.map { number, window in
            let snap = WindowSnapshot(
                app: AppInfo(pid: window.pid, bundleID: window.bundleID, name: "App \(window.pid)"),
                element: AXElementBox(AXUIElementCreateApplication(pid_t(number))),
                windowNumber: CGWindowID(number), role: "AXWindow", subrole: "AXStandardWindow", title: "",
                frame: window.frame, isMinimized: window.minimised, isFullScreen: window.fullScreen,
                isModal: false, isResizable: true)
            return WindowRecord(id: WindowID(number), snapshot: snap,
                                display: displays.display(mostlyContaining: window.frame)?.id, spaces: [window.space])
        }
        .filter { !unanswered.contains($0.snapshot.app.pid) }
        var current: [DisplayID: SpaceInfo] = [:]
        for display in displays.displays { current[display.id] = space }
        return Observation(records: records, displays: displays, currentSpaces: current,
                           recency: recency.map { WindowID($0) }, unansweredPIDs: unanswered, hiddenPIDs: hidden)
    }

    func write(_ assignments: [FrameAssignment]) async -> [WindowID: FrameWriteResult] {
        lock.withLock {
            var results: [WindowID: FrameWriteResult] = [:]
            for item in assignments {
                _writes += 1
                guard var window = windows[item.id.raw] else { continue }
                var actual = item.frame
                actual.size.width = max(actual.width, window.minimumSize.width)
                actual.size.height = max(actual.height, window.minimumSize.height)
                window.frame = actual
                windows[item.id.raw] = window
                results[item.id] = FrameWriteResult(requested: item.frame, actual: actual, positionError: .success,
                                                    sizeError: .success, duration: .zero)
            }
            return results
        }
    }

    func setMinimised(_ list: [(WindowID, WindowSnapshot)], _ minimised: Bool) async -> Set<WindowID> {
        lock.withLock {
            for (id, _) in list { windows[id.raw]?.minimised = minimised }
            return []
        }
    }
}

private func ids(_ tree: LayoutTree?) -> [UInt64] { tree?.windowIDs.map(\.raw) ?? [] }
private let key2 = LayoutKey(space: SpaceID(4), display: dell)

@Suite("Reconcile (M1)")
struct ReconcileTests {
    @Test func firstVisitArrangesAndASecondIdenticalReadingWritesNothing() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        let first = await engine.reconcile(world.observe())
        #expect(first.written == 3)
        #expect(ids(await engine.trees[key2]) == [1, 2, 3])
        let second = await engine.reconcile(world.observe())
        #expect(second.written == 0)
        #expect(!second.changedAnything)
    }

    @Test func newWindowJoinsAtTheRightEnd() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        world.add(3, x: 600)   // opens anywhere, joins at the right end (L3)
        let summary = await engine.reconcile(world.observe())
        #expect(summary.arrived == 1)
        #expect(ids(await engine.trees[key2]) == [1, 2, 3])
        #expect(world.window(3)!.frame.minX > world.window(2)!.frame.minX)
    }

    @Test func closedWindowLetsNeighboursGrow() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        world.remove(2)
        let summary = await engine.reconcile(world.observe())
        #expect(summary.departed == 1)
        #expect(ids(await engine.trees[key2]) == [1, 3])
        #expect(world.window(1)!.frame.width > 2000)
    }

    @Test func lastWindowClosedEmptiesTheLayout() async {
        let world = World()
        world.add(1, x: 100)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        world.remove(1)
        _ = await engine.reconcile(world.observe())
        #expect(await engine.trees[key2] == nil)
    }

    @Test func minimisedWindowComesBackToItsPlace() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        _ = await engine.trees[key2]
        // Build A over D in the first column, then minimise D.
        world.add(4, x: 4000)
        _ = await engine.reconcile(world.observe())
        world.update(2) { $0.minimised = true }
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [1, 3, 4])
        world.update(2) { $0.minimised = false }
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [1, 2, 3, 4])
    }

    @Test func userMinimisedWindowsAreNeverBroughtBack() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        world.update(2) { $0.minimised = true }
        _ = await engine.reconcile(world.observe())
        _ = await engine.reconcile(world.observe())
        #expect(world.window(2)!.minimised)
        #expect(await engine.minimisedByEngine.isEmpty)
    }

    @Test func windowsOfAppsThatDidNotAnswerKeepTheirTiles() async {
        let world = World()
        world.add(1, x: 100, pid: 100); world.add(2, x: 1500, pid: 200)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        let summary = await engine.reconcile(world.observe(unanswered: [200]))
        #expect(summary.departed == 0)
        #expect(ids(await engine.trees[key2]) == [1, 2])
    }

    @Test func hiddenAppLeavesAndReturns() async {
        let world = World()
        world.add(1, x: 100, pid: 100); world.add(2, x: 1500, pid: 200); world.add(3, x: 3000, pid: 300)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        _ = await engine.reconcile(world.observe(hidden: [200]))
        #expect(ids(await engine.trees[key2]) == [1, 3])
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [1, 2, 3])
    }

    @Test func eachDesktopKeepsItsOwnLayout() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        world.add(5, x: 200, space: SpaceID(5)); world.add(6, x: 2000, space: SpaceID(5)); world.add(7, x: 3500, space: SpaceID(5))
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe(space: desktop2))
        _ = await engine.reconcile(world.observe(space: desktop3))
        #expect(ids(await engine.trees[key2]) == [1, 2])
        #expect(ids(await engine.trees[LayoutKey(space: SpaceID(5), display: dell)]) == [5, 6, 7])
        // Back on desktop 2: the layout is unchanged and nothing is written (US-12.2).
        let back = await engine.reconcile(world.observe(space: desktop2))
        #expect(back.written == 0)
        #expect(back.departed == 0)
    }

    @Test func windowMovedToAnotherDesktopLeavesAndJoins() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(5, x: 200, space: SpaceID(5))
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe(space: desktop2))
        _ = await engine.reconcile(world.observe(space: desktop3))
        world.update(2) { $0.space = SpaceID(5) }
        _ = await engine.reconcile(world.observe(space: desktop3))
        #expect(ids(await engine.trees[LayoutKey(space: SpaceID(5), display: dell)]) == [5, 2])
        _ = await engine.reconcile(world.observe(space: desktop2))
        #expect(ids(await engine.trees[key2]) == [1])
    }

    @Test func fullScreenWindowLeavesAndComesBack() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        world.update(1) { $0.fullScreen = true }
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [2, 3])
        // While the full-screen Space is shown, no layout is touched.
        let onFullScreen = await engine.reconcile(world.observe(space: fullScreenSpace))
        #expect(onFullScreen.written == 0)
        world.update(1) { $0.fullScreen = false }
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [1, 2, 3])
    }

    @Test func disconnectedDisplayDropsItsLayout() async {
        let world = World()
        world.add(1, x: 100); world.add(9, x: -1000, y: 400, width: 600)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        #expect(await engine.trees[LayoutKey(space: SpaceID(4), display: laptop)] != nil)
        // macOS moves the laptop's window onto the remaining display.
        world.update(9) { $0.frame = CGRect(x: 300, y: 300, width: 600, height: 600) }
        _ = await engine.reconcile(world.observe(displays: onlyDell))
        #expect(await engine.trees[LayoutKey(space: SpaceID(4), display: laptop)] == nil)
        #expect(ids(await engine.trees[key2]) == [1, 9])
    }

    @Test func windowMovedAwayIsPutBackOnceOnly() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        let tile = world.window(1)!.frame
        world.update(1) { $0.frame = $0.frame.offsetBy(dx: 300, dy: 0) }
        _ = await engine.reconcile(world.observe())
        #expect(world.window(1)!.frame == tile)
        // The app moves it again: TILE32 does not fight (TA-12).
        world.update(1) { $0.frame = $0.frame.offsetBy(dx: 300, dy: 0) }
        let summary = await engine.reconcile(world.observe())
        #expect(summary.written == 0)
    }

    @Test func fullLayoutSwapsTheLeastRecentlyUsedWindow() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let engine = LayoutEngine(writer: world)
        var limits = WindowLimits()
        limits.set(2, for: dell)
        _ = await engine.reconcile(world.observe(recency: [1, 2]), limits: limits)
        world.add(3, x: 3000)
        // Window 2 is the least recently used: window 3 takes its tile (US-31.5).
        _ = await engine.reconcile(world.observe(recency: [3, 1, 2]), limits: limits)
        #expect(ids(await engine.trees[key2]) == [1, 3])
        #expect(world.window(2)!.minimised)
        #expect(await engine.minimisedByEngine == [WindowID(2)])
        // The user brings window 2 back: it takes the tile of the least recently used one (US-31.4).
        world.update(2) { $0.minimised = false }
        _ = await engine.reconcile(world.observe(recency: [2, 3, 1]), limits: limits)
        #expect(Set(ids(await engine.trees[key2])) == [2, 3])
        #expect(world.window(1)!.minimised)
        #expect(await engine.minimisedByEngine == [WindowID(1)])
    }

    @Test func freedTileBringsBackTheLastMinimisedWindow() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        var limits = WindowLimits()
        limits.set(2, for: dell)
        _ = await engine.reconcile(world.observe(recency: [1, 2, 3]), limits: limits)
        #expect(world.window(3)!.minimised)
        world.remove(1)
        let summary = await engine.reconcile(world.observe(recency: [2]), limits: limits)
        #expect(summary.restored == 1)
        #expect(!world.window(3)!.minimised)
        #expect(Set(ids(await engine.trees[key2])) == [2, 3])
        #expect(await engine.minimisedByEngine.isEmpty)
    }

    @Test func tileNowRebuildsAnExistingLayout() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        world.add(4, x: 4000)
        _ = await engine.reconcile(world.observe())
        let rebuilt = await engine.reconcile(world.observe(), rebuild: true)
        #expect(rebuilt.layouts >= 1)
        #expect(ids(await engine.trees[key2]).count == 4)
    }

    @Test func windowThatCannotShrinkIsNotRetried() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500, minimumSize: CGSize(width: 4000, height: 600))
        let engine = LayoutEngine(writer: world)
        let first = await engine.reconcile(world.observe())
        #expect(first.doesNotFit == 1)
        let second = await engine.reconcile(world.observe())
        #expect(second.written == 0)
    }

    @Test func changingTheLimitMinimisesOrBringsBackAtOnce() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe(recency: [1, 2, 3]))
        var limits = WindowLimits()
        limits.set(2, for: dell)
        _ = await engine.reconcile(world.observe(recency: [1, 2, 3]), limits: limits)
        #expect(world.window(3)!.minimised)
        #expect(ids(await engine.trees[key2]) == [1, 2])
        limits.set(3, for: dell)
        _ = await engine.reconcile(world.observe(recency: [1, 2]), limits: limits)
        #expect(!world.window(3)!.minimised)
        #expect(Set(ids(await engine.trees[key2])) == [1, 2, 3])
    }
}
