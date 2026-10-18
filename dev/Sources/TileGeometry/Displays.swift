// TileGeometry: the display table and the only coordinate conversion point (architecture TA-7,
// constitution technical rule 9).
//
// Accessibility coordinates: origin at the top-left of the primary display, y grows downward.
// AppKit coordinates: origin at the bottom-left of the primary display, y grows upward.
// Everything outside this module works in Accessibility coordinates.
import CoreGraphics
import Foundation

/// A display identified by its UUID, which survives reconnects (unlike the display number).
public struct DisplayID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let uuid: String
    public init(uuid: String) { self.uuid = uuid }
    public var description: String { uuid }
}

/// One display as macOS reports it, in AppKit coordinates. The input of the display table,
/// so the table can be built from real screens or from test data.
public struct ScreenDescriptor: Sendable, Equatable {
    public let id: DisplayID
    public let number: CGDirectDisplayID
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect

    public init(id: DisplayID, number: CGDirectDisplayID, name: String, frame: CGRect, visibleFrame: CGRect) {
        self.id = id
        self.number = number
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// One display in Accessibility coordinates.
public struct Display: Sendable, Equatable {
    public let id: DisplayID
    public let number: CGDirectDisplayID
    public let name: String
    public let frame: CGRect
    /// The area windows may use: excludes the menu bar and the Dock (US-5.2).
    public let usableArea: CGRect
    public let isPrimary: Bool
}

public enum CoordinateConversion {
    public static func axRect(fromAppKit rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func appKitRect(fromAX rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    public static func axPoint(fromAppKit point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}

public struct DisplayTable: Sendable, Equatable {
    public let displays: [Display]
    /// Height of the primary display, the reference for every conversion.
    public let primaryHeight: CGFloat

    /// The primary display is the one whose AppKit frame starts at the origin.
    public init(screens: [ScreenDescriptor]) {
        let primary = screens.first { $0.frame.origin == .zero } ?? screens.first
        let height = primary?.frame.height ?? 0
        primaryHeight = height
        displays = screens.map { screen in
            Display(
                id: screen.id,
                number: screen.number,
                name: screen.name,
                frame: CoordinateConversion.axRect(fromAppKit: screen.frame, primaryHeight: height),
                usableArea: CoordinateConversion.axRect(fromAppKit: screen.visibleFrame, primaryHeight: height),
                isPrimary: screen.id == primary?.id
            )
        }
    }

    public func display(id: DisplayID) -> Display? {
        displays.first { $0.id == id }
    }

    /// The display under a point in Accessibility coordinates, or nil in a gap between displays.
    public func display(containing point: CGPoint) -> Display? {
        displays.first { display in
            point.x >= display.frame.minX && point.x < display.frame.maxX &&
                point.y >= display.frame.minY && point.y < display.frame.maxY
        }
    }

    /// The display that contains the largest part of a window (US-6.3, US-9.2).
    public func display(mostlyContaining rect: CGRect) -> Display? {
        let best = displays.max { overlapArea($0.frame, rect) < overlapArea($1.frame, rect) }
        guard let best, overlapArea(best.frame, rect) > 0 else { return nil }
        return best
    }

    /// The frame moved, and if needed shrunk, so that it lies fully inside a display's usable
    /// area (US-24.3, N-5). A frame already inside one is returned unchanged. Otherwise the
    /// display holding most of it is used, or the primary display if none holds any part.
    public func clampedIntoView(_ frame: CGRect) -> CGRect {
        if displays.contains(where: { $0.usableArea.contains(frame) }) { return frame }
        guard let target = display(mostlyContaining: frame) ?? displays.first(where: \.isPrimary) ?? displays.first else {
            return frame
        }
        let area = target.usableArea
        let width = min(frame.width, area.width), height = min(frame.height, area.height)
        let x = min(max(frame.minX, area.minX), area.maxX - width)
        let y = min(max(frame.minY, area.minY), area.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Converts the mouse location (AppKit) to Accessibility coordinates.
    public func axPoint(fromAppKit point: CGPoint) -> CGPoint {
        CoordinateConversion.axPoint(fromAppKit: point, primaryHeight: primaryHeight)
    }

    public func axRect(fromAppKit rect: CGRect) -> CGRect {
        CoordinateConversion.axRect(fromAppKit: rect, primaryHeight: primaryHeight)
    }

    public func appKitRect(fromAX rect: CGRect) -> CGRect {
        CoordinateConversion.appKitRect(fromAX: rect, primaryHeight: primaryHeight)
    }
}

private func overlapArea(_ a: CGRect, _ b: CGRect) -> CGFloat {
    let overlap = a.intersection(b)
    return overlap.isNull ? 0 : overlap.width * overlap.height
}
