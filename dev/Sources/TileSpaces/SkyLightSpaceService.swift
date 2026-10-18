// The only place with undocumented macOS functions (architecture TA-26, constitution
// technical rule 1). Exactly four functions, all read-only, resolved by name at runtime so
// a missing one turns into fallback mode instead of a crash at launch. The app is not
// linked against any private framework.
import ApplicationServices
import CoreGraphics
import Darwin
import Foundation
import TileLog

public final class SkyLightSpaceService: SpaceService, @unchecked Sendable {
    // @unchecked: the stored function pointers and the connection number never change
    // after init, and the window server functions may be called from any thread.

    private typealias MainConnectionFunction = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFunction = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFunction = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// Space mask for "all Spaces", as used by other window managers with this function.
    private static let allSpacesMask: Int32 = 0x7

    public static let shared = SkyLightSpaceService()

    private let connection: Int32
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunction?
    private let copySpacesForWindows: CopySpacesForWindowsFunction?
    private let getWindow: GetWindowFunction?

    /// Names that were found, for the start-up log and "Copy diagnostics".
    public let resolvedFunctions: [String: String]

    public var isAvailable: Bool {
        copyManagedDisplaySpaces != nil && copySpacesForWindows != nil && getWindow != nil && connection != 0
    }

    private init() {
        let skyLight = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
        var found: [String: String] = [:]

        /// Looks up the SkyLight name first, then the older CoreGraphics name.
        func resolve(_ names: [String], key: String) -> UnsafeMutableRawPointer? {
            for name in names {
                if let skyLight, let symbol = dlsym(skyLight, name) { found[key] = name; return symbol }
                if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) { found[key] = name; return symbol }
            }
            return nil
        }

        let mainConnection = resolve(["SLSMainConnectionID", "CGSMainConnectionID"], key: "MainConnectionID")
            .map { unsafeBitCast($0, to: MainConnectionFunction.self) }
        copyManagedDisplaySpaces = resolve(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], key: "CopyManagedDisplaySpaces")
            .map { unsafeBitCast($0, to: CopyManagedDisplaySpacesFunction.self) }
        copySpacesForWindows = resolve(["SLSCopySpacesForWindows", "CGSCopySpacesForWindows"], key: "CopySpacesForWindows")
            .map { unsafeBitCast($0, to: CopySpacesForWindowsFunction.self) }
        getWindow = resolve(["_AXUIElementGetWindow"], key: "AXUIElementGetWindow")
            .map { unsafeBitCast($0, to: GetWindowFunction.self) }

        connection = mainConnection?() ?? 0
        resolvedFunctions = found
    }

    public func spaceTable() -> [DisplaySpaces] {
        guard let copyManagedDisplaySpaces,
              let array = copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]] else {
            return []
        }
        return SpaceTableParser.parse(array)
    }

    public func spaces(of windows: [CGWindowID]) -> [CGWindowID: [SpaceID]] {
        guard let copySpacesForWindows else { return [:] }
        var result: [CGWindowID: [SpaceID]] = [:]
        // One call per window: the function returns the union of Spaces for a list, so a
        // single call could not tell which window is on which Space.
        for window in windows {
            let list = [NSNumber(value: window)] as CFArray
            guard let spaces = copySpacesForWindows(connection, Self.allSpacesMask, list)?.takeRetainedValue() as? [NSNumber] else {
                continue
            }
            result[window] = spaces.map { SpaceID($0.uint64Value) }
        }
        return result
    }

    public func windowNumber(of element: AXUIElement) -> CGWindowID? {
        guard let getWindow else { return nil }
        var number: CGWindowID = 0
        return getWindow(element, &number) == .success && number != 0 ? number : nil
    }
}

/// Turns the raw display-Spaces list into value types. Kept apart from the calls so it can
/// be tested with recorded data.
public enum SpaceTableParser {
    public static func parse(_ entries: [[String: Any]]) -> [DisplaySpaces] {
        entries.compactMap { entry in
            guard let identifier = entry["Display Identifier"] as? String,
                  let currentRaw = entry["Current Space"] as? [String: Any] else { return nil }
            let rawSpaces = entry["Spaces"] as? [[String: Any]] ?? []

            var desktopCount = 0
            let spaces: [SpaceInfo] = rawSpaces.compactMap { raw in
                let type = (raw["type"] as? NSNumber)?.intValue ?? -1
                var number: Int?
                if type == 0 {
                    desktopCount += 1
                    number = desktopCount
                }
                return spaceInfo(raw, desktopNumber: number)
            }
            guard let parsedCurrent = spaceInfo(currentRaw, desktopNumber: nil) else { return nil }
            // Take the numbered version of the current Space from the list when present.
            let current = spaces.first { $0.id == parsedCurrent.id } ?? parsedCurrent
            return DisplaySpaces(displayIdentifier: identifier, current: current, spaces: spaces)
        }
    }

    private static func spaceInfo(_ raw: [String: Any], desktopNumber: Int?) -> SpaceInfo? {
        guard let id = (raw["id64"] as? NSNumber) ?? (raw["ManagedSpaceID"] as? NSNumber) else { return nil }
        return SpaceInfo(
            id: SpaceID(id.uint64Value),
            uuid: raw["uuid"] as? String ?? "",
            type: (raw["type"] as? NSNumber)?.intValue ?? -1,
            desktopNumber: desktopNumber
        )
    }
}
