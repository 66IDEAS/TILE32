import ApplicationServices
import CoreGraphics
import Testing
@testable import TileAX
@testable import TileCore
@testable import TileEngine
@testable import TileGeometry
@testable import TileSpaces

private let dell = DisplayID(uuid: "DELL")
private let laptop = DisplayID(uuid: "LAPTOP")
private let displays = DisplayTable(screens: [
    ScreenDescriptor(id: laptop, number: 1, name: "Built-in Retina Display",
                     frame: CGRect(x: -1728, y: 88, width: 1728, height: 1117), visibleFrame: CGRect(x: -1728, y: 88, width: 1728, height: 1085)),
    ScreenDescriptor(id: dell, number: 4, name: "Dell U4924DW",
                     frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: CGRect(x: 0, y: 57, width: 5120, height: 1353)),
])

private func record(_ number: UInt64, app: String, title: String, display: DisplayID?, subrole: String = "AXStandardWindow", minimised: Bool = false) -> WindowRecord {
    let snapshot = WindowSnapshot(
        app: AppInfo(pid: 4242, bundleID: "com.example.\(app)", name: app),
        element: AXElementBox(AXUIElementCreateApplication(pid_t(number))),
        windowNumber: CGWindowID(number), role: "AXWindow", subrole: subrole, title: title,
        frame: CGRect(x: 10, y: 40, width: 800, height: 600),
        isMinimized: minimised, isFullScreen: false, isModal: false, isResizable: true
    )
    return WindowRecord(id: WindowID(number), snapshot: snapshot, display: display, spaces: [SpaceID(4)])
}

private let desktop2 = SpaceInfo(id: SpaceID(4), uuid: "U4", type: 0, desktopNumber: 2)

@Suite("Windows submenu (UX-6)")
struct WindowMenuModelTests {
    @Test func groupsByDisplayPrimaryFirst() {
        let content = WindowMenuModel.build(
            records: [record(3, app: "Terminal", title: "zsh", display: laptop), record(1, app: "Mail", title: "Inbox", display: dell)],
            displays: displays, currentSpaces: [dell: desktop2, laptop: desktop2], otherSpacesCount: 14
        )
        #expect(content.sections.map(\.header) == ["Dell U4924DW - Desktop 2", "Built-in Retina Display - Desktop 2"])
        #expect(content.sections[0].entries.map(\.text) == ["Mail - Inbox"])
        #expect(content.sections[1].entries.map(\.text) == ["Terminal - zsh"])
        #expect(content.otherSpacesCount == 14)
    }

    @Test func floatingWindowsAreListedWithTheirReason() {
        let content = WindowMenuModel.build(
            records: [record(5, app: "Preview", title: "Open", display: dell, subrole: "AXDialog")],
            displays: displays, currentSpaces: [:], otherSpacesCount: 0
        )
        #expect(content.sections.isEmpty)
        #expect(content.floating.map(\.text) == ["Preview - Open  (floating: dialog)"])
    }

    @Test func minimisedWindowsAreNotListed() {
        let content = WindowMenuModel.build(
            records: [record(6, app: "Safari", title: "Apple", display: dell, minimised: true)],
            displays: displays, currentSpaces: [:], otherSpacesCount: 0
        )
        #expect(content.isEmpty)
    }

    @Test func headerWithoutSpaceInformation() {
        let content = WindowMenuModel.build(
            records: [record(1, app: "Mail", title: "", display: dell)],
            displays: displays, currentSpaces: [:], otherSpacesCount: 0
        )
        #expect(content.sections.map(\.header) == ["Dell U4924DW"])
        #expect(content.sections[0].entries.map(\.text) == ["Mail"])
    }

    @Test func longTitlesAreCutInTheMiddle() {
        let text = WindowMenuModel.middleTruncated(String(repeating: "a", count: 30) + String(repeating: "b", count: 30))
        #expect(text.count == 48)
        #expect(text.hasPrefix("aaaaaaaaaaaaaaaaaaaaaaa..."))
        #expect(text.hasSuffix("bbbbbbbbbbbbbbbbbbbbbb"))
        #expect(WindowMenuModel.middleTruncated("short") == "short")
    }
}
