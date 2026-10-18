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
