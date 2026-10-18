// Logs the Space table at start and on every Space switch (architecture TA-16, TA-26).
// The engine subscribes to the same notification in task T-1.5.
import AppKit
import TileGeometry
import TileLog

@MainActor
public final class SpaceMonitor {
    private let service: SpaceService
    private let displays: @MainActor () -> DisplayTable
    private let onChange: @MainActor () -> Void
    private var observer: NSObjectProtocol?

    public init(
        service: SpaceService,
        displays: @escaping @MainActor () -> DisplayTable,
        onChange: @escaping @MainActor () -> Void = {}
    ) {
        self.service = service
        self.displays = displays
        self.onChange = onChange
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.spaces.info("Active Space changed")
                self?.logCurrentSpaces()
                self?.onChange()
            }
        }
    }

    isolated deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    public func logCurrentSpaces() {
        guard service.isAvailable else {
            Log.spaces.error("Space functions unavailable; fallback mode")
            return
        }
        let table = displays()
        for (displayID, space) in service.currentSpaces(on: table) {
            let name = table.display(id: displayID)?.name ?? displayID.uuid
            Log.spaces.info("""
                \(name, privacy: .public) shows \(space.id.description, privacy: .public) \
                desktop \(space.desktopNumber.map(String.init) ?? "-", privacy: .public) \
                type \(space.type) full screen \(space.isFullScreen)
                """)
        }
    }

    /// Text for "Copy diagnostics": every display entry and its Spaces.
    public func describe() -> [String] {
        guard service.isAvailable else { return ["Spaces: unavailable (fallback mode)"] }
        var lines = ["Spaces:"]
        for entry in service.spaceTable() {
            lines.append("  \(entry.displayIdentifier): current \(entry.current.id) (desktop \(entry.current.desktopNumber.map(String.init) ?? "-"))")
            for space in entry.spaces {
                lines.append("    \(space.id) type \(space.type) desktop \(space.desktopNumber.map(String.init) ?? "-") uuid \(space.uuid)")
            }
        }
        return lines
    }
}
