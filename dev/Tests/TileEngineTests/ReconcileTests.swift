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
        var title = ""
        var frame: CGRect
        var space: SpaceID = SpaceID(4)
        var minimised = false
        var fullScreen = false
        var minimumSize: CGSize = .zero
        /// The next writes take the position but keep the old width, as Safari did right
        /// after moving to the Retina display (macOS itself had fitted the height to the
        /// smaller display). `Int.max` ignores widths for ever.
        var ignoredSizeWrites = 0
        /// A tab behind another tab: on its desktop, but not listed by Accessibility.
        var backgroundTab = false
    }

    private let lock = NSLock()
    private var windows: [UInt64: Window] = [:]
    private var _writes = 0

    var writes: Int { lock.withLock { _writes } }

    func add(_ number: UInt64, x: CGFloat, y: CGFloat = 300, width: CGFloat = 800, pid: pid_t = 100,
             space: SpaceID = SpaceID(4), minimumSize: CGSize = .zero, bundleID: String = "com.example.app", title: String = "") {
        lock.withLock {
            windows[number] = Window(pid: pid, bundleID: bundleID, title: title,
                                     frame: CGRect(x: x, y: y, width: width, height: 600), space: space, minimumSize: minimumSize)
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
        let records = snapshot.filter { ($0.value.space == space.id || $0.value.minimised) && !$0.value.backgroundTab }.map { number, window in
            let snap = WindowSnapshot(
                app: AppInfo(pid: window.pid, bundleID: window.bundleID, name: "App \(window.pid)"),
                element: AXElementBox(AXUIElementCreateApplication(pid_t(number))),
                windowNumber: CGWindowID(number), role: "AXWindow", subrole: "AXStandardWindow", title: window.title,
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
                if window.ignoredSizeWrites > 0 {
                    if window.ignoredSizeWrites != .max { window.ignoredSizeWrites -= 1 }
                    actual.size.width = window.frame.width
                }
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

    @Test func disconnectedDisplayKeepsItsLayoutUntilItReturns() async {
        let world = World()
        world.add(1, x: 100); world.add(9, x: -1000, y: 400, width: 600)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        let laptopKey = LayoutKey(space: SpaceID(4), display: laptop)
        let laptopTile = world.window(9)!.frame
        // macOS moves the laptop's window onto the remaining display; it joins there.
        world.update(9) { $0.frame = CGRect(x: 300, y: 300, width: 600, height: 600) }
        _ = await engine.reconcile(world.observe(displays: onlyDell))
        #expect(ids(await engine.trees[key2]) == [1, 9])
        // The laptop's layout waits for the laptop.
        #expect(ids(await engine.trees[laptopKey]) == [9])
        // The laptop comes back and macOS moves the window back: it takes its old tile again.
        world.update(9) { $0.frame = laptopTile.offsetBy(dx: 40, dy: 20) }
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [1])
        #expect(ids(await engine.trees[laptopKey]) == [9])
        #expect(world.window(9)!.frame == laptopTile)
    }

    @Test func displaysOfflineDuringALockChangeNothing() async {
        let world = World()
        for n in 1...8 { world.add(UInt64(n), x: CGFloat(n) * 500) }
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        _ = await engine.drop(WindowID(3), at: CGPoint(x: 5100, y: 700), displays: bothDisplays,
                             currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        let before = await engine.trees[key2]
        // While locked, macOS reports no displays for a moment.
        _ = await engine.reconcile(world.observe(displays: DisplayTable(screens: [])))
        let summary = await engine.reconcile(world.observe())
        #expect(await engine.trees[key2] == before)
        #expect(summary.written == 0)
    }

    @Test func rememberedLayoutServesEveryFirstVisit() async {
        let world = World()
        for n in 1...4 { world.add(UInt64(n), x: CGFloat(n) * 900) }
        let first = LayoutEngine(writer: world)
        _ = await first.reconcile(world.observe())
        let notes = world.window(4)!.frame
        _ = await first.drop(WindowID(1), at: CGPoint(x: notes.midX, y: notes.midY), displays: bothDisplays,
                             currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        let stored = await first.exportLayouts(world.observe())
        let second = LayoutEngine(writer: world)
        await second.importLayouts(stored)
        _ = await second.reconcile(world.observe())
        // The layout is lost again later and the windows got shuffled meanwhile.
        await second.setTree(LayoutTree(), for: key2)
        await second.forgetTree(key2)
        for n in 1...4 { world.update(UInt64(n)) { $0.frame = CGRect(x: CGFloat(n) * 300, y: 200, width: 900, height: 700) } }
        _ = await second.reconcile(world.observe())
        #expect(ids(await second.trees[key2]) == [4, 2, 3, 1])
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

    @Test func sixteenDesktopsNeverWriteToAHiddenOne() async {
        let world = World()
        // Three windows on each of 16 desktops (Spaces 100 to 115).
        for desktop in 0..<16 {
            for index in 0..<3 {
                world.add(UInt64(1000 + desktop * 10 + index), x: CGFloat(100 + index * 1500), space: SpaceID(UInt64(100 + desktop)))
            }
        }
        let engine = LayoutEngine(writer: world)
        func space(_ desktop: Int) -> SpaceInfo { SpaceInfo(id: SpaceID(UInt64(100 + desktop)), uuid: "D\(desktop)", type: 0, desktopNumber: desktop + 1) }
        // Visit every desktop once: each gets its own layout.
        for desktop in 0..<16 { _ = await engine.reconcile(world.observe(space: space(desktop))) }
        #expect(await engine.trees.count == 16)
        // Switch around many times: nothing changes, so nothing is written (US-12.2, US-12.3).
        let before = world.writes
        for round in 0..<5 {
            for desktop in stride(from: 15, through: 0, by: -1) where (desktop + round) % 2 == 0 {
                let summary = await engine.reconcile(world.observe(space: space(desktop)))
                #expect(summary.written == 0)
            }
        }
        #expect(world.writes == before)
        // A window closed on desktop 7 changes only desktop 7's layout when it is shown.
        world.remove(1070)
        let summary = await engine.reconcile(world.observe(space: space(7)))
        #expect(summary.departed == 1)
        #expect(ids(await engine.trees[LayoutKey(space: SpaceID(107), display: dell)]) == [1071, 1072])
        #expect(ids(await engine.trees[LayoutKey(space: SpaceID(108), display: dell)]) == [1080, 1081, 1082])
    }
}

private func snapshots(_ observation: Observation) -> [WindowID: WindowSnapshot] {
    Dictionary(observation.records.map { ($0.id, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
}

private func current(_ space: SpaceInfo, _ displays: DisplayTable = bothDisplays) -> [DisplayID: SpaceInfo] {
    Dictionary(displays.displays.map { ($0.id, space) }, uniquingKeysWith: { first, _ in first })
}

@Suite("Desktop switch in progress")
struct MidSwitchTests {
    /// Desktop 2 with three windows (1, 2, 3 from left to right after a swap) and desktop 3
    /// with two windows.
    private func setUp() async -> (World, LayoutEngine) {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        world.add(7, x: 100, space: SpaceID(5)); world.add(8, x: 2000, space: SpaceID(5))
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe(space: desktop3))
        _ = await engine.reconcile(world.observe(space: desktop2))
        // A custom order the user made: 3, 1, 2.
        _ = await engine.drop(WindowID(3), at: CGPoint(x: world.window(1)!.frame.midX, y: world.window(1)!.frame.midY),
                              displays: bothDisplays, currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        return (world, engine)
    }

    private func known(_ world: World) -> [WindowID: [SpaceID]] {
        Dictionary(uniqueKeysWithValues: [1, 2, 3, 7, 8].compactMap { n in world.window(n).map { (WindowID(n), [$0.space]) } })
    }

    @Test func oldDesktopWindowsListedForTheNewDesktopAreHeld() async {
        let (world, engine) = await setUp()
        let before = await engine.trees[key2]
        let writes = world.writes
        // macOS already reports desktop 2, Accessibility still lists desktop 3's windows.
        var reading = world.observe(space: desktop3)
        reading.currentSpaces = current(desktop2)
        reading.knownSpaces = known(world)
        let summary = await engine.reconcile(reading)
        #expect(summary.heldMidSwitch)
        #expect(await engine.trees[key2] == before)
        #expect(world.writes == writes)
    }

    @Test func shownWindowsNotListedYetAreHeld() async {
        let (world, engine) = await setUp()
        let before = await engine.trees[key2]
        var reading = world.observe(space: desktop2)
        reading.records = []   // desktop 2's windows are not listed yet
        reading.knownSpaces = known(world)
        let summary = await engine.reconcile(reading)
        #expect(summary.heldMidSwitch)
        #expect(await engine.trees[key2] == before)
        // The settled reading keeps the user's order and writes nothing.
        var settled = world.observe(space: desktop2)
        settled.knownSpaces = known(world)
        let after = await engine.reconcile(settled)
        #expect(!after.heldMidSwitch && after.written == 0)
        #expect(ids(await engine.trees[key2]) == ids(before))
    }

    @Test func windowsClosedOrMovedAwayStillLeave() async {
        let (world, engine) = await setUp()
        world.remove(1)                               // closed: the window server no longer has it
        world.update(2) { $0.space = SpaceID(5) }     // moved to desktop 3 in Mission Control
        var reading = world.observe(space: desktop2)
        reading.knownSpaces = known(world)
        let summary = await engine.reconcile(reading)
        #expect(!summary.heldMidSwitch)
        #expect(summary.departed == 2)
        #expect(ids(await engine.trees[key2]) == [3])
    }

    @Test func aReadingThatNeverSettlesIsTakenWhenAccepted() async {
        let (world, engine) = await setUp()
        var reading = world.observe(space: desktop2)
        reading.records = []
        reading.knownSpaces = known(world)
        let summary = await engine.reconcile(reading, acceptMidSwitch: true)
        #expect(!summary.heldMidSwitch)
        #expect(summary.departed == 3)
    }
}

@Suite("Tabs replace each other in one tile")
struct TabTests {
    /// Three windows on desktop 2; the middle one is a Finder window (pid 200).
    private func setUp() async -> (World, LayoutEngine) {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500, pid: 200); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        return (world, engine)
    }

    private func reading(_ world: World) -> Observation {
        var observation = world.observe()
        observation.knownSpaces = Dictionary(uniqueKeysWithValues: [1, 2, 3, 9].compactMap { n in
            world.window(n).map { (WindowID(n), [$0.space]) }
        })
        return observation
    }

    @Test func aNewTabTakesTheTileOfTheTabBehindIt() async {
        let (world, engine) = await setUp()
        let tile = world.window(2)!.frame
        // Cmd-T: a new window in the same frame, the old tab goes behind it.
        world.add(9, x: tile.minX, y: tile.minY, width: tile.width, pid: 200)
        world.update(9) { $0.frame = tile }
        world.update(2) { $0.backgroundTab = true }
        let writes = world.writes
        let summary = await engine.reconcile(reading(world))
        #expect(!summary.heldMidSwitch)
        #expect(ids(await engine.trees[key2]) == [1, 9, 3])
        #expect(world.writes == writes)
        // Choosing the first tab again swaps back, still in the same place.
        world.update(2) { $0.backgroundTab = false }
        world.update(9) { $0.backgroundTab = true }
        _ = await engine.reconcile(reading(world))
        #expect(ids(await engine.trees[key2]) == [1, 2, 3])
        #expect(world.writes == writes)
    }

    @Test func anotherAppsWindowInTheSameFrameDoesNotTakeTheTile() async {
        let (world, engine) = await setUp()
        let tile = world.window(2)!.frame
        world.remove(2)   // Finder window closed
        world.add(9, x: tile.minX, pid: 300)
        world.update(9) { $0.frame = tile }
        _ = await engine.reconcile(reading(world))
        #expect(ids(await engine.trees[key2]) == [1, 3, 9])
    }
}

@Suite("Drops (M2, US-14 to US-18)")
struct DropTests {
    /// Three windows side by side on the Dell, tiled.
    private func setUp() async -> (World, LayoutEngine) {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        return (world, engine)
    }

    @Test func dropOnTheBottomEdgeSplitsTheTarget() async {
        let (world, engine) = await setUp()
        world.add(4, x: 4000)
        _ = await engine.reconcile(world.observe())
        // US-15.4: D dropped on the bottom edge of A.
        let a = world.window(1)!.frame
        let outcome = await engine.drop(WindowID(4), at: CGPoint(x: a.midX, y: a.maxY - 20), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .split)
        #expect(shape(await engine.trees[key2]!) == "H(V(1,4),2,3)")
        #expect(world.window(4)!.frame.minY > world.window(1)!.frame.maxY)
    }

    @Test func dropOnTheCentreSwapsAndSizesStayWithTheTiles() async {
        let (world, engine) = await setUp()
        let tile1 = world.window(1)!.frame, tile3 = world.window(3)!.frame
        let outcome = await engine.drop(WindowID(1), at: CGPoint(x: tile3.midX, y: tile3.midY), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .swapped)
        #expect(ids(await engine.trees[key2]) == [3, 2, 1])
        #expect(world.window(1)!.frame == tile3)
        #expect(world.window(3)!.frame == tile1)
    }

    @Test func dropOnNothingSnapsBack() async {
        let (world, engine) = await setUp()
        let tile = world.window(2)!.frame
        world.update(2) { $0.frame = $0.frame.offsetBy(dx: 0, dy: 400) }   // the user dragged it
        let outcome = await engine.drop(WindowID(2), at: CGPoint(x: -3000, y: 100), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .snappedBack)
        #expect(world.window(2)!.frame == tile)
        #expect(ids(await engine.trees[key2]) == [1, 2, 3])
    }

    @Test func dropOnItsOwnTileSnapsBack() async {
        let (world, engine) = await setUp()
        let tile = world.window(2)!.frame
        world.update(2) { $0.frame = $0.frame.offsetBy(dx: 30, dy: 0) }
        let outcome = await engine.drop(WindowID(2), at: CGPoint(x: tile.midX, y: tile.midY), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .snappedBack)
        #expect(world.window(2)!.frame == tile)
    }

    @Test func dropOnTheEmptyLaptopMovesTheWindowThere() async {
        let (world, engine) = await setUp()
        let outcome = await engine.drop(WindowID(3), at: CGPoint(x: -900, y: 700), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .movedToEmptyDisplay)
        #expect(ids(await engine.trees[key2]) == [1, 2])
        #expect(ids(await engine.trees[LayoutKey(space: SpaceID(4), display: laptop)]) == [3])
        // It fills the laptop's usable area minus the gap (US-18.3).
        #expect(world.window(3)!.frame == CGRect(x: -1722, y: 273, width: 1716, height: 1073))
    }

    @Test func ignoredSizeAfterADropIsWrittenAgainUntilItFits() async {
        let (world, engine) = await setUp()
        world.update(3) { $0.ignoredSizeWrites = 2 }
        let outcome = await engine.drop(WindowID(3), at: CGPoint(x: -633, y: 351), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .movedToEmptyDisplay)
        #expect(world.window(3)!.frame.width < 1716)
        #expect(await engine.needsWriteRetry)
        let first = await engine.reconcile(world.observe())
        #expect(first.written == 1 && first.failed == 1)
        let second = await engine.reconcile(world.observe())
        #expect(second.written == 1 && second.matched == 1)
        #expect(world.window(3)!.frame == CGRect(x: -1722, y: 273, width: 1716, height: 1073))
        #expect(await !engine.needsWriteRetry)
        #expect(await engine.reconcile(world.observe()).written == 0)
    }

    @Test func appThatKeepsIgnoringIsLeftAloneAfterThreeAttempts() async {
        let (world, engine) = await setUp()
        world.update(3) { $0.ignoredSizeWrites = .max }
        _ = await engine.drop(WindowID(3), at: CGPoint(x: -633, y: 351), displays: bothDisplays,
                              currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        let writesAfterDrop = world.writes
        for _ in 0..<LayoutEngine.maximumWriteRetries {
            #expect(await engine.needsWriteRetry)
            #expect(await engine.reconcile(world.observe()).written == 1)
        }
        #expect(await !engine.needsWriteRetry)
        #expect(await engine.reconcile(world.observe()).written == 0)
        #expect(world.writes == writesAfterDrop + LayoutEngine.maximumWriteRetries)
    }

    @Test func userMovingAWindowAwayIsStillPutBackOnlyOnce() async {
        let (world, engine) = await setUp()
        world.update(2) { $0.frame = $0.frame.offsetBy(dx: 0, dy: 200) }
        #expect(await engine.reconcile(world.observe()).written == 1)
        world.update(2) { $0.frame = $0.frame.offsetBy(dx: 0, dy: 200) }
        #expect(await engine.reconcile(world.observe()).written == 0)
        #expect(await !engine.needsWriteRetry)
    }

    @Test func dropAtTheRightDisplayEdgeMakesAFullHeightColumn() async {
        let world = World()
        for n in 1...8 { world.add(UInt64(n), x: CGFloat(n) * 500) }
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        #expect(shape(await engine.trees[key2]!) == "H(V(1,5),V(2,6),V(3,7),V(4,8))")
        let outcome = await engine.drop(WindowID(3), at: CGPoint(x: 5100, y: 700), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .placedAtDisplayEdge)
        #expect(shape(await engine.trees[key2]!) == "H(V(1,5),V(2,6),7,V(4,8),3)")
        let frame = world.window(3)!.frame
        #expect(frame.maxX == 5120 - LayoutEngine.gap)
        #expect(frame.minY == 30 + LayoutEngine.gap && frame.maxY == 30 + 1353 - LayoutEngine.gap)
    }

    @Test func dropAtTheLeftEdgeOfAnotherDisplayMovesTheWindowThere() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(9, x: -1500, y: 400, width: 600)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        let outcome = await engine.drop(WindowID(9), at: CGPoint(x: 10, y: 700), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .placedAtDisplayEdge)
        #expect(ids(await engine.trees[key2]) == [9, 1, 2])
        #expect(await engine.trees[LayoutKey(space: SpaceID(4), display: laptop)] == nil)
    }

    @Test func swapAcrossDisplaysExchangesBothWindows() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(9, x: -1000, y: 400, width: 600)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        let laptopTile = world.window(9)!.frame
        let outcome = await engine.drop(WindowID(1), at: CGPoint(x: laptopTile.midX, y: laptopTile.midY), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .swapped)
        #expect(ids(await engine.trees[key2]) == [9, 2])
        #expect(ids(await engine.trees[LayoutKey(space: SpaceID(4), display: laptop)]) == [1])
        #expect(world.window(1)!.frame == laptopTile)
    }

    @Test func splitAcrossDisplaysLeavesTheSourceTidy() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(9, x: -1000, y: 400, width: 600)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        let laptopTile = world.window(9)!.frame
        let outcome = await engine.drop(WindowID(2), at: CGPoint(x: laptopTile.minX + DisplayEdgeGeometry.band + 20, y: laptopTile.midY), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .split)
        #expect(ids(await engine.trees[key2]) == [1])
        #expect(ids(await engine.trees[LayoutKey(space: SpaceID(4), display: laptop)]) == [2, 9])
        #expect(world.window(1)!.frame.width > 5000)
    }

    @Test func missingDropZonesHaveAReason() async {
        let (world, engine) = await setUp()
        let own = world.window(2)!.frame
        #expect(await engine.noDropPreviewReason(for: WindowID(2), at: CGPoint(x: own.midX, y: own.midY), displays: bothDisplays,
                                                 currentSpaces: current(desktop2)) == "the pointer is over the window's own tile")
        #expect(await engine.noDropPreviewReason(for: WindowID(77), at: CGPoint(x: 200, y: 200), displays: bothDisplays,
                                                 currentSpaces: current(desktop2)) == "the window is in no layout of the shown desktops")
        #expect(await engine.noDropPreviewReason(for: WindowID(2), at: CGPoint(x: 2000, y: 5), displays: bothDisplays,
                                                 currentSpaces: current(desktop2)) == "the pointer is outside the usable area")
    }

    @Test func floatingWindowsAreIgnored() async {
        let (world, engine) = await setUp()
        let outcome = await engine.drop(WindowID(77), at: CGPoint(x: 200, y: 200), displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(outcome == .ignored)
    }

    @Test func previewMatchesTheZone() async {
        let (world, engine) = await setUp()
        let a = world.window(1)!.frame
        let preview = await engine.dropPreview(for: WindowID(3), at: CGPoint(x: a.minX + DisplayEdgeGeometry.band + 10, y: a.midY),
                                               displays: bothDisplays, currentSpaces: current(desktop2))
        guard case .window(let target, let zone, _)? = preview?.target else { Issue.record("no preview"); return }
        #expect(target == WindowID(1))
        #expect(zone == .left)
        #expect(preview!.area.width < a.width)
        // Over the dragged window's own tile there is no preview.
        let own = await engine.dropPreview(for: WindowID(1), at: CGPoint(x: a.midX, y: a.midY),
                                           displays: bothDisplays, currentSpaces: current(desktop2))
        #expect(own == nil)
    }
}

/// Compact structure, for example "H(V(1,4),2,3)" (same as in the core tests).
private func shape(_ tree: LayoutTree) -> String {
    guard let root = tree.root else { return "empty" }
    func walk(_ node: LayoutNode) -> String {
        switch node {
        case .leaf(let id): return "\(id.raw)"
        case .split(let direction, let children):
            return (direction == .horizontal ? "H(" : "V(") + children.map { walk($0.node) }.joined(separator: ",") + ")"
        }
    }
    return walk(root)
}

@Suite("Resizing by edge (M2, US-28)")
struct ResizeTests {
    @Test func ownerScenarioFiftyTwentyFiveTwentyFive() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        // Drag A's right edge to the middle of the display, then B's right edge to three quarters.
        var a = world.window(1)!.frame
        a.size.width = 2560 - 3 - a.minX
        world.update(1) { $0.frame = a }
        let share = await engine.resize(WindowID(1), to: a, edges: [.right], final: true, displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(abs((share ?? 0) - 0.5) < 0.01)
        var b = world.window(2)!.frame
        b.size.width = 3840 - 3 - b.minX + 2   // released 2 points off: snaps to 3/4
        world.update(2) { $0.frame = b }
        _ = await engine.resize(WindowID(2), to: b, edges: [.right], final: true, displays: bothDisplays,
                                currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        let widths = [1, 2, 3].map { world.window(UInt64($0))!.frame.width }
        #expect(abs(widths[0] - 2 * widths[1]) < 8)
        #expect(abs(widths[1] - widths[2]) < 4)
    }

    @Test func liveResizeWritesOnlyTheNeighbours() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        var a = world.window(1)!.frame
        a.size.width += 400
        world.update(1) { $0.frame = a }
        let before = world.window(2)!.frame
        _ = await engine.resize(WindowID(1), to: a, edges: [.right], final: false, displays: bothDisplays,
                                currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(world.window(1)!.frame == a)                  // the held window is not touched
        #expect(world.window(2)!.frame.minX > before.minX)     // the neighbour followed
    }

    @Test func outerEdgeSnapsBack() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        let tile = world.window(1)!.frame
        var dragged = tile
        dragged.origin.x += 200; dragged.size.width -= 200   // left edge, which touches the display border
        world.update(1) { $0.frame = dragged }
        _ = await engine.resize(WindowID(1), to: dragged, edges: [.left], final: true, displays: bothDisplays,
                                currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(world.window(1)!.frame == tile)
    }
}

@Suite("Live resize details (TA-25, UX-16)")
struct LiveResizeDetailTests {
    @Test func labelShowsTheValueItWillSnapTo() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        var a = world.window(1)!.frame
        a.size.width = 2560 - 3 - a.minX - 30     // 30 points short of the middle: within 1 percent
        let share = await engine.resize(WindowID(1), to: a, edges: [.right], final: false, displays: bothDisplays,
                                        currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(abs((share ?? 0) - 0.5) < 0.0001)
    }

    @Test func slowAppsFollowOnReleaseOnly() async {
        let world = World()
        world.add(1, x: 100, pid: 100); world.add(2, x: 1500, pid: 200)
        let engine = LayoutEngine(writer: SlowWriter(world: world, slowPID: 200))
        _ = await engine.reconcile(world.observe())
        _ = await engine.reconcile(world.observe(), rebuild: true)   // a few writes to measure app 200
        let neighbour = world.window(2)!.frame
        var a = world.window(1)!.frame
        a.size.width += 400
        world.update(1) { $0.frame = a }
        _ = await engine.resize(WindowID(1), to: a, edges: [.right], final: false, displays: bothDisplays,
                                currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(world.window(2)!.frame == neighbour)
        _ = await engine.resize(WindowID(1), to: a, edges: [.right], final: true, displays: bothDisplays,
                                currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(world.window(2)!.frame != neighbour)
    }
}

/// Reports 80 ms per write for one app, like an app that redraws slowly.
private final class SlowWriter: FrameWriting, @unchecked Sendable {
    let world: World
    let slowPID: pid_t
    init(world: World, slowPID: pid_t) { self.world = world; self.slowPID = slowPID }

    func write(_ assignments: [FrameAssignment]) async -> [WindowID: FrameWriteResult] {
        let results = await world.write(assignments)
        var adjusted: [WindowID: FrameWriteResult] = [:]
        for item in assignments {
            guard let result = results[item.id] else { continue }
            adjusted[item.id] = FrameWriteResult(requested: result.requested, actual: result.actual, positionError: .success,
                                                 sizeError: .success,
                                                 duration: item.window.app.pid == slowPID ? .milliseconds(80) : .milliseconds(5))
        }
        return adjusted
    }

    func setMinimised(_ windows: [(WindowID, WindowSnapshot)], _ minimised: Bool) async -> Set<WindowID> {
        await world.setMinimised(windows, minimised)
    }
}

@Suite("Excluding apps in reconcile (US-22)")
struct ExcludeReconcileTests {
    @Test func excludedAppLeavesAndComesBack() async {
        let world = World()
        world.add(1, x: 100, pid: 100); world.add(2, x: 1500, pid: 200); world.add(3, x: 3000, pid: 100)
        world.update(2) { $0.bundleID = "us.zoom.xos" }
        let engine = LayoutEngine(writer: world)
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [1, 2, 3])
        let zoomFrame = world.window(2)!.frame
        let excluded = await engine.reconcile(world.observe(), excludedBundleIDs: ["us.zoom.xos"])
        #expect(excluded.departed == 1)
        #expect(ids(await engine.trees[key2]) == [1, 3])
        #expect(world.window(2)!.frame == zoomFrame)          // floats where it is (US-22.2)
        _ = await engine.reconcile(world.observe())
        #expect(ids(await engine.trees[key2]) == [1, 3, 2])    // joins again (US-22.3)
    }
}

@Suite("Remembered layouts (US-26)")
struct StoredLayoutTests {
    @Test func arrangementAndProportionsSurviveARestart() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500); world.add(3, x: 3000); world.add(4, x: 4000)
        let first = LayoutEngine(writer: world)
        _ = await first.reconcile(world.observe())
        // A over D in the first column, then A's column made wider.
        let a = world.window(1)!.frame
        _ = await first.drop(WindowID(4), at: CGPoint(x: a.midX, y: a.maxY - 20), displays: bothDisplays,
                             currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        var wide = world.window(1)!.frame
        wide.size.width = 2560 - 3 - wide.minX
        world.update(1) { $0.frame = wide }
        _ = await first.resize(WindowID(1), to: wide, edges: [.right], final: true, displays: bothDisplays,
                               currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        let before = await first.trees[key2]!
        let stored = await first.exportLayouts(world.observe())
        #expect(stored.keys.contains("U4/DELL"))

        // TILE32 restarts: a new engine, the same windows.
        let second = LayoutEngine(writer: world)
        await second.importLayouts(stored)
        let summary = await second.reconcile(world.observe())
        #expect(await second.trees[key2] == before)
        #expect(summary.written == 0)   // nothing moves: the windows are already where the layout puts them
    }

    @Test func unmatchedWindowsJoinAsNewOnes() async {
        let world = World()
        world.add(1, x: 100); world.add(2, x: 1500)
        let first = LayoutEngine(writer: world)
        _ = await first.reconcile(world.observe())
        let stored = await first.exportLayouts(world.observe())
        world.remove(2)
        world.add(7, x: 3000, pid: 300)        // a window of another app
        let second = LayoutEngine(writer: world)
        await second.importLayouts(stored)
        _ = await second.reconcile(world.observe())
        #expect(ids(await second.trees[key2]) == [1, 7])
    }

    @Test func restartWithoutRememberedLayoutKeepsTheTilingOnScreen() async {
        let world = World()
        for n in 1...8 { world.add(UInt64(n), x: CGFloat(n) * 500) }
        let first = LayoutEngine(writer: world)
        _ = await first.reconcile(world.observe())
        _ = await first.drop(WindowID(3), at: CGPoint(x: 5100, y: 700), displays: bothDisplays,
                             currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        let before = await first.trees[key2]!
        // TILE32 restarts and has nothing remembered: the screen is read back.
        let second = LayoutEngine(writer: world)
        let summary = await second.reconcile(world.observe())
        #expect(summary.written == 0)
        #expect(shape(await second.trees[key2]!) == shape(before))
        #expect(summary.layoutsChanged)
    }

    @Test func rememberedStructureWinsWhenItMatchesTheScreen() async {
        let world = World()
        for n in 1...4 { world.add(UInt64(n), x: CGFloat(n) * 900) }
        let first = LayoutEngine(writer: world)
        _ = await first.reconcile(world.observe())
        // Two rows whose columns happen to line up; read from the screen alone this would be
        // two columns of two.
        await first.setTree(LayoutTree(root: .split(.vertical, [
            SplitChild(.split(.horizontal, [SplitChild(.leaf(WindowID(1)), weight: 0.5), SplitChild(.leaf(WindowID(2)), weight: 0.5)]), weight: 0.5),
            SplitChild(.split(.horizontal, [SplitChild(.leaf(WindowID(3)), weight: 0.5), SplitChild(.leaf(WindowID(4)), weight: 0.5)]), weight: 0.5),
        ])), for: key2)
        _ = await first.reconcile(world.observe())
        let stored = await first.exportLayouts(world.observe())
        let second = LayoutEngine(writer: world)
        await second.importLayouts(stored)
        let summary = await second.reconcile(world.observe())
        #expect(summary.written == 0)
        #expect(shape(await second.trees[key2]!) == "V(H(1,2),H(3,4))")
    }

    @Test func afterAComputerRestartWindowsGoBackToTheirPlaces() async {
        // Before: Safari on the laptop, and on the Dell Mail, Safari and Notes, in a custom order.
        let world = World()
        world.add(9, x: -1500, y: 400, width: 600, bundleID: "com.apple.Safari", title: "News")
        world.add(1, x: 100, bundleID: "com.apple.mail", title: "Inbox")
        world.add(2, x: 1500, bundleID: "com.apple.Safari", title: "Docs")
        world.add(3, x: 3000, bundleID: "com.apple.Notes", title: "Notes")
        let first = LayoutEngine(writer: world)
        _ = await first.reconcile(world.observe())
        let notes = world.window(3)!.frame
        _ = await first.drop(WindowID(1), at: CGPoint(x: notes.midX, y: notes.midY), displays: bothDisplays,
                             currentSpaces: current(desktop2), snapshots: snapshots(world.observe()))
        #expect(ids(await first.trees[key2]) == [3, 2, 1])
        let stored = await first.exportLayouts(world.observe())

        // After the restart every window has a new number and opens somewhere else, overlapping.
        let rebooted = World()
        rebooted.add(21, x: -1400, y: 350, width: 700, bundleID: "com.apple.Safari", title: "News")
        rebooted.add(22, x: 200, bundleID: "com.apple.Safari", title: "Docs")
        rebooted.add(23, x: 400, bundleID: "com.apple.Notes", title: "Notes")
        rebooted.add(24, x: 600, bundleID: "com.apple.mail", title: "Inbox")
        let second = LayoutEngine(writer: rebooted)
        await second.importLayouts(stored)
        let summary = await second.reconcile(rebooted.observe())
        #expect(summary.written > 0)
        #expect(ids(await second.trees[key2]) == [23, 22, 24])
        #expect(ids(await second.trees[LayoutKey(space: SpaceID(4), display: laptop)]) == [21])
    }

    @Test func titlesAreHashedNotStored() {
        let hash = WindowDescriptor.hash("Inbox - private@example.com")
        #expect(hash.count == 16)
        #expect(!hash.contains("Inbox"))
    }
}
