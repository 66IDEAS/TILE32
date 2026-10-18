import CoreGraphics
import Testing
@testable import TileGeometry

/// The owner's arrangement as AppKit reported it on 2026-10-18: the Dell U4924DW is the
/// primary display with the Dock at the bottom; the laptop sits to its left, 88 points higher
/// at the bottom edge.
let dell = ScreenDescriptor(
    id: DisplayID(uuid: "DELL"), number: 4, name: "Dell U4924DW",
    frame: CGRect(x: 0, y: 0, width: 5120, height: 1440),
    visibleFrame: CGRect(x: 0, y: 57, width: 5120, height: 1353)
)
let laptop = ScreenDescriptor(
    id: DisplayID(uuid: "LAPTOP"), number: 1, name: "Built-in Retina Display",
    frame: CGRect(x: -1728, y: 88, width: 1728, height: 1117),
    visibleFrame: CGRect(x: -1728, y: 88, width: 1728, height: 1085)
)

@Suite("Display table and coordinates (TA-7)")
struct DisplayTableTests {
    let table = DisplayTable(screens: [laptop, dell])

    @Test func primaryIsTheDisplayAtTheOrigin() {
        #expect(table.primaryHeight == 1440)
        #expect(table.display(id: DisplayID(uuid: "DELL"))?.isPrimary == true)
        #expect(table.display(id: DisplayID(uuid: "LAPTOP"))?.isPrimary == false)
    }

    @Test func framesAndUsableAreasInAccessibilityCoordinates() {
        let dellAX = table.display(id: DisplayID(uuid: "DELL"))!
        #expect(dellAX.frame == CGRect(x: 0, y: 0, width: 5120, height: 1440))
        // Menu bar 30 points at the top, Dock 57 points at the bottom.
        #expect(dellAX.usableArea == CGRect(x: 0, y: 30, width: 5120, height: 1353))

        let laptopAX = table.display(id: DisplayID(uuid: "LAPTOP"))!
        #expect(laptopAX.frame == CGRect(x: -1728, y: 235, width: 1728, height: 1117))
        // Menu bar 32 points at the top, no Dock.
        #expect(laptopAX.usableArea == CGRect(x: -1728, y: 267, width: 1728, height: 1085))
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 5120, height: 1440),
        CGRect(x: -1728, y: 88, width: 1728, height: 1117),
        CGRect(x: -500, y: 300, width: 1200, height: 700),
        CGRect(x: 12.5, y: -40, width: 99, height: 1),
    ])
    func conversionRoundTrips(rect: CGRect) {
        let ax = table.axRect(fromAppKit: rect)
        #expect(table.appKitRect(fromAX: ax) == rect)
    }

    @Test func mouseLocationConversion() {
        // AppKit (100, 1440) is the top-left corner of the Dell: AX (100, 0).
        #expect(table.axPoint(fromAppKit: CGPoint(x: 100, y: 1440)) == CGPoint(x: 100, y: 0))
        #expect(table.axPoint(fromAppKit: CGPoint(x: -100, y: 600)) == CGPoint(x: -100, y: 840))
    }

    @Test func displayUnderAPoint() {
        #expect(table.display(containing: CGPoint(x: 100, y: 100))?.id.uuid == "DELL")
        #expect(table.display(containing: CGPoint(x: -100, y: 300))?.id.uuid == "LAPTOP")
        // Above the laptop's top edge there is no display.
        #expect(table.display(containing: CGPoint(x: -100, y: 100)) == nil)
    }

    @Test func displayWithTheLargestPartOfAWindow() {
        let mostlyOnLaptop = CGRect(x: -1000, y: 400, width: 1200, height: 500)
        #expect(table.display(mostlyContaining: mostlyOnLaptop)?.id.uuid == "LAPTOP")
        let mostlyOnDell = CGRect(x: -200, y: 400, width: 1200, height: 500)
        #expect(table.display(mostlyContaining: mostlyOnDell)?.id.uuid == "DELL")
        #expect(table.display(mostlyContaining: CGRect(x: -3000, y: 0, width: 100, height: 100)) == nil)
    }

    @Test func singleDisplayIsPrimary() {
        let only = DisplayTable(screens: [dell])
        #expect(only.displays.count == 1)
        #expect(only.displays[0].isPrimary)
    }

    @Test func clampingKeepsVisibleFramesAndPullsOthersIntoView() {
        let visible = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(table.clampedIntoView(visible) == visible)
        // Hanging off the right edge of the Dell: moved left, size kept.
        #expect(table.clampedIntoView(CGRect(x: 4800, y: 100, width: 800, height: 600)) == CGRect(x: 4320, y: 100, width: 800, height: 600))
        // Under the menu bar: moved down into the usable area.
        #expect(table.clampedIntoView(CGRect(x: 100, y: 0, width: 800, height: 600)) == CGRect(x: 100, y: 30, width: 800, height: 600))
        // On no display at all: placed on the primary display, shrunk to fit.
        #expect(table.clampedIntoView(CGRect(x: 9000, y: 0, width: 6000, height: 2000)) == CGRect(x: 0, y: 30, width: 5120, height: 1353))
    }
}
