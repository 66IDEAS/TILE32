// Reads the real displays from AppKit and reports changes (architecture TA-7, TA-16).
import AppKit
import TileLog

@MainActor
public enum ScreenReader {
    /// The current display table, built from `NSScreen`.
    public static func currentTable() -> DisplayTable {
        let descriptors = NSScreen.screens.compactMap { screen -> ScreenDescriptor? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let displayNumber = CGDirectDisplayID(number.uint32Value)
            return ScreenDescriptor(
                id: DisplayID(uuid: uuidString(for: displayNumber)),
                number: displayNumber,
                name: screen.localizedName,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame
            )
        }
        return DisplayTable(screens: descriptors)
    }

    /// The display UUID, stable across reconnects. Falls back to the display number,
    /// which is still unique while the display is connected.
    static func uuidString(for number: CGDirectDisplayID) -> String {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String? else {
            return "display-\(number)"
        }
        return string
    }
}

/// Calls `onChange` with a fresh table whenever displays are added, removed, moved or resized.
@MainActor
public final class DisplayMonitor {
    private var observer: NSObjectProtocol?
    public private(set) var table: DisplayTable

    public init(onChange: @escaping @MainActor (DisplayTable) -> Void) {
        table = ScreenReader.currentTable()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let newTable = ScreenReader.currentTable()
                guard newTable != self.table else { return }
                self.table = newTable
                Log.layout.info("Displays changed: \(newTable.displays.count) connected")
                onChange(newTable)
            }
        }
        logTable()
    }

    isolated deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func logTable() {
        for display in table.displays {
            Log.layout.info("""
                Display \(display.name, privacy: .public) \(display.id.uuid, privacy: .public) \
                frame \(String(describing: display.frame), privacy: .public) \
                usable \(String(describing: display.usableArea), privacy: .public) \
                primary \(display.isPrimary)
                """)
        }
    }
}
