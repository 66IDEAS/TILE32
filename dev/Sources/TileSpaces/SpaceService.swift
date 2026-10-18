// TileSpaces: which Space each display shows and which Space each window is on
// (architecture TA-26). The rest of the code sees only this protocol.
import ApplicationServices
import CoreGraphics
import Foundation
import TileGeometry

/// A Space as macOS numbers it. Numbers can change after a logout; use `SpaceInfo.uuid`
/// for anything that must survive a restart (TA-19).
public struct SpaceID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
    public var description: String { "space-\(raw)" }
}

public struct SpaceInfo: Sendable, Equatable {
    public let id: SpaceID
    public let uuid: String
    /// macOS Space type: 0 is a desktop, 4 is a full-screen app.
    public let type: Int
    /// Position among the desktops of its display, starting at 1 ("Desktop 3", UX-6).
    public let desktopNumber: Int?

    public var isFullScreen: Bool { type == 4 }

    public init(id: SpaceID, uuid: String, type: Int, desktopNumber: Int?) {
        self.id = id
        self.uuid = uuid
        self.type = type
        self.desktopNumber = desktopNumber
    }
}

/// The Spaces of one display entry. With "Displays have separate Spaces" switched off,
/// macOS reports a single entry named "Main" for all displays (TA-26).
public struct DisplaySpaces: Sendable, Equatable {
    public static let sharedIdentifier = "Main"

    public let displayIdentifier: String
    public let current: SpaceInfo
    public let spaces: [SpaceInfo]

    public init(displayIdentifier: String, current: SpaceInfo, spaces: [SpaceInfo]) {
        self.displayIdentifier = displayIdentifier
        self.current = current
        self.spaces = spaces
    }
}

public protocol SpaceService: Sendable {
    /// False when the undocumented functions are missing; the engine then uses the
    /// fallback of TA-16 (US-12.7).
    var isAvailable: Bool { get }
    /// The Spaces of every display entry, including the one currently shown.
    func spaceTable() -> [DisplaySpaces]
    /// The Spaces each window is on. A window on all Spaces lists several.
    func spaces(of windows: [CGWindowID]) -> [CGWindowID: [SpaceID]]
    /// The window number of an Accessibility window element (TA-20).
    func windowNumber(of element: AXUIElement) -> CGWindowID?
}

extension SpaceService {
    /// The Space shown on each display. With shared Spaces, every display shows the same one.
    public func currentSpaces(on displays: DisplayTable) -> [DisplayID: SpaceInfo] {
        let table = spaceTable()
        var result: [DisplayID: SpaceInfo] = [:]
        for display in displays.displays {
            let entry = table.first { $0.displayIdentifier.caseInsensitiveCompare(display.id.uuid) == .orderedSame }
                ?? table.first { $0.displayIdentifier == DisplaySpaces.sharedIdentifier }
            if let entry { result[display.id] = entry.current }
        }
        return result
    }
}
