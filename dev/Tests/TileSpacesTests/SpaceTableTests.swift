import CoreGraphics
import Foundation
import Testing
@testable import TileGeometry
@testable import TileSpaces

/// Shaped like the dictionaries the window server returns for two displays with separate
/// Spaces: three desktops and one full-screen app on the ultrawide, one desktop on the laptop.
private var separateSpaces: [[String: Any]] { [
    [
        "Display Identifier": "1888B9FA-5260-4070-BF34-74E7EE430825",
        "Current Space": ["id64": 7, "ManagedSpaceID": 7, "type": 0, "uuid": "U7"],
        "Spaces": [
            ["id64": 3, "type": 0, "uuid": "U3"],
            ["id64": 7, "type": 0, "uuid": "U7"],
            ["id64": 9, "type": 4, "uuid": "U9"],
            ["id64": 12, "type": 0, "uuid": "U12"],
        ],
    ],
    [
        "Display Identifier": "37D8832A-2D66-02CA-B9F7-8F30A301B230",
        "Current Space": ["id64": 1, "type": 0, "uuid": "U1"],
        "Spaces": [["id64": 1, "type": 0, "uuid": "U1"]],
    ],
] }

private let displays = DisplayTable(screens: [
    ScreenDescriptor(id: DisplayID(uuid: "1888B9FA-5260-4070-BF34-74E7EE430825"), number: 4, name: "Dell U4924DW",
                     frame: CGRect(x: 0, y: 0, width: 5120, height: 1440), visibleFrame: CGRect(x: 0, y: 57, width: 5120, height: 1353)),
    ScreenDescriptor(id: DisplayID(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230"), number: 1, name: "Built-in Retina Display",
                     frame: CGRect(x: -1728, y: 88, width: 1728, height: 1117), visibleFrame: CGRect(x: -1728, y: 88, width: 1728, height: 1085)),
])

@Suite("Space table (TA-26)")
struct SpaceTableTests {
    @Test func parsesDisplaysSpacesAndDesktopNumbers() {
        let table = SpaceTableParser.parse(separateSpaces)
        #expect(table.count == 2)
        let dell = table[0]
        #expect(dell.current.id == SpaceID(7))
        #expect(dell.current.desktopNumber == 2)
        #expect(dell.spaces.map(\.desktopNumber) == [1, 2, nil, 3])
        #expect(dell.spaces[2].isFullScreen)
        #expect(dell.current.uuid == "U7")
    }

    @Test func skipsEntriesWithoutCurrentSpace() {
        let table = SpaceTableParser.parse([["Display Identifier": "X"], ["Current Space": ["id64": 1]]])
        #expect(table.isEmpty)
    }

    @Test func currentSpacePerDisplayWithSeparateSpaces() {
        let service = FakeSpaceService(table: SpaceTableParser.parse(separateSpaces))
        let current = service.currentSpaces(on: displays)
        #expect(current[DisplayID(uuid: "1888B9FA-5260-4070-BF34-74E7EE430825")]?.id == SpaceID(7))
        #expect(current[DisplayID(uuid: "37D8832A-2D66-02CA-B9F7-8F30A301B230")]?.id == SpaceID(1))
    }

    @Test func sharedSpacesMapToEveryDisplay() {
        let shared: [[String: Any]] = [[
            "Display Identifier": "Main",
            "Current Space": ["id64": 5, "type": 0, "uuid": "U5"],
            "Spaces": [["id64": 5, "type": 0, "uuid": "U5"]],
        ]]
        let current = FakeSpaceService(table: SpaceTableParser.parse(shared)).currentSpaces(on: displays)
        #expect(current.count == 2)
        #expect(current.values.allSatisfy { $0.id == SpaceID(5) })
    }

    @Test func unavailableServiceReportsNothing() {
        let service = FakeSpaceService(isAvailable: false, table: SpaceTableParser.parse(separateSpaces),
                                       windowSpaces: [42: [SpaceID(7)]])
        #expect(service.currentSpaces(on: displays).isEmpty)
        #expect(service.spaces(of: [42]).isEmpty)
    }

    @Test func fakeWindowSpaces() {
        let service = FakeSpaceService(windowSpaces: [42: [SpaceID(7)], 43: [SpaceID(3), SpaceID(7)]])
        let result = service.spaces(of: [42, 43, 44])
        #expect(result[42] == [SpaceID(7)])
        #expect(result[43] == [SpaceID(3), SpaceID(7)])
        #expect(result[44] == nil)
    }
}
