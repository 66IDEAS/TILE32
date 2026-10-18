// The public window server list (architecture TA-16 fallback, spike S3). Without the Screen
// Recording permission it gives window numbers, owners, bounds and layers, never titles,
// and TILE32 never asks for titles here.
import CoreGraphics
import Foundation

public struct ServerWindow: Sendable, Equatable {
    public let number: CGWindowID
    public let ownerPID: pid_t
    public let ownerName: String
    /// Global coordinates with the origin at the top-left, the same as Accessibility.
    public let bounds: CGRect
    public let layer: Int
    public let isOnScreen: Bool
}

public enum WindowServerList {
    /// Normal windows (layer 0) of all apps, on every Space, without desktop elements.
    public static func normalWindows() -> [ServerWindow] {
        let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(parse).filter { $0.layer == 0 }
    }

    /// The frontmost normal window under a point (global, top-left origin), using the
    /// window server's front-to-back order. Fast enough for every mouse event.
    /// `margin` widens every window, because macOS places resize edges just outside a frame.
    public static func window(at point: CGPoint, margin: CGFloat = 0, excludingPID: pid_t? = nil) -> ServerWindow? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        return list.lazy.compactMap(parse).first { window in
            window.layer == 0 && window.ownerPID != excludingPID && window.bounds.insetBy(dx: -margin, dy: -margin).contains(point)
        }
    }

    /// The on-screen normal windows of all apps, frontmost first.
    public static func onScreenNormalWindows() -> [ServerWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(parse).filter { $0.layer == 0 }
    }

    /// Window numbers of the on-screen normal windows, frontmost first. TILE32 uses this as
    /// the starting order of use (TA-27).
    public static func frontToBack() -> [CGWindowID] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(parse).filter { $0.layer == 0 }.map(\.number)
    }

    /// Every normal window under a point, frontmost first. Near a gap both neighbours are
    /// candidates, because both have their resize zone there (found in the M2 resize check).
    public static func windows(at point: CGPoint, margin: CGFloat, excludingPID: pid_t? = nil) -> [ServerWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap(parse).filter { window in
            window.layer == 0 && window.ownerPID != excludingPID && window.bounds.insetBy(dx: -margin, dy: -margin).contains(point)
        }
    }

    /// The current bounds of one window, or nil when it is gone.
    public static func window(number: CGWindowID) -> ServerWindow? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], number) as? [[String: Any]] else { return nil }
        return list.compactMap(parse).first { $0.number == number }
    }

    static func parse(_ entry: [String: Any]) -> ServerWindow? {
        guard let number = (entry[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
              let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary) else { return nil }
        return ServerWindow(
            number: number,
            ownerPID: pid,
            ownerName: entry[kCGWindowOwnerName as String] as? String ?? "?",
            bounds: bounds,
            layer: (entry[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1,
            isOnScreen: (entry[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        )
    }
}
