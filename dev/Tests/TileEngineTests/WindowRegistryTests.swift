import ApplicationServices
import CoreGraphics
import Testing
@testable import TileAX
@testable import TileCore
@testable import TileEngine
@testable import TileGeometry
@testable import TileSpaces

private let app = AppInfo(pid: 4242, bundleID: "com.example.test", name: "Test")
private let displays = DisplayTable(screens: [
    ScreenDescriptor(id: DisplayID(uuid: "DELL"), number: 4, name: "Dell U4924DW",
                     frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: CGRect(x: 0, y: 57, width: 5120, height: 1353)),
])

/// Distinct elements without needing any permission: application elements for made-up pids.
private func element(_ pid: pid_t) -> AXElementBox {
    AXElementBox(AXUIElementCreateApplication(pid))
}

private func snapshot(_ box: AXElementBox, number: CGWindowID?, frame: CGRect? = CGRect(x: 10, y: 40, width: 800, height: 600)) -> WindowSnapshot {
    WindowSnapshot(app: app, element: box, windowNumber: number, role: "AXWindow", subrole: "AXStandardWindow",
                   title: "", frame: frame, isMinimized: false, isFullScreen: false, isModal: false, isResizable: true)
}

@Suite("Window registry (TA-20)")
struct WindowRegistryTests {
    @Test func windowNumberIsTheID() {
        var registry = WindowRegistry()
        #expect(registry.id(for: snapshot(element(1), number: 7262)) == WindowID(7262))
    }

    @Test func fallbackIDsAreStablePerElement() {
        var registry = WindowRegistry()
        let first = registry.id(for: snapshot(element(1), number: nil))
        let again = registry.id(for: snapshot(element(1), number: nil))
        let other = registry.id(for: snapshot(element(2), number: nil))
        #expect(first == again)
        #expect(first != other)
        #expect(first.raw >= WindowRegistry.firstFallbackID)
    }

    @Test func updateRecordsDisplayAndSpaces() {
        var registry = WindowRegistry()
        registry.update(with: [snapshot(element(1), number: 10)], displays: displays, spaces: [10: [SpaceID(4)]])
        let record = registry.records[WindowID(10)]
        #expect(record?.display == DisplayID(uuid: "DELL"))
        #expect(record?.spaces == [SpaceID(4)])
    }

    @Test func windowOffAllDisplaysHasNoDisplay() {
        var registry = WindowRegistry()
        registry.update(with: [snapshot(element(1), number: 11, frame: CGRect(x: -9000, y: 0, width: 10, height: 10))],
                        displays: displays, spaces: [:])
        #expect(registry.records[WindowID(11)]?.display == nil)
        #expect(registry.records[WindowID(11)]?.spaces == [])
    }

    @Test func goneWindowsAreDroppedWithTheirFallbackIDs() {
        var registry = WindowRegistry()
        registry.update(with: [snapshot(element(1), number: nil), snapshot(element(2), number: 20)], displays: displays, spaces: [:])
        #expect(registry.records.count == 2)
        let oldID = registry.id(for: snapshot(element(1), number: nil))
        registry.update(with: [snapshot(element(2), number: 20)], displays: displays, spaces: [:])
        #expect(registry.records.count == 1)
        // The element is gone, so it gets a new id if it ever reappears.
        #expect(registry.id(for: snapshot(element(1), number: nil)) != oldID)
    }
}
