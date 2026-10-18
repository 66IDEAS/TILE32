// Wires the modules together. Holds no layout logic (architecture TA-2, TA-17).
import AppKit
import TileAX
import TileGeometry
import TileLog
import TileUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var displays: DisplayMonitor?
    private var permission: PermissionMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.ui.info("TILE32 \(version, privacy: .public) started")

        displays = DisplayMonitor { _ in }
        let permission = PermissionMonitor { [weak self] granted in self?.permissionChanged(granted) }
        self.permission = permission

        menuBar = MenuBarController(
            state: Self.menuState(permissionGranted: permission.isGranted),
            actions: MenuActions(
                tileNow: { Log.layout.info("Tile now chosen; arranging windows arrives in task T-0.24") },
                openAccessibilitySettings: {
                    // Makes sure TILE32 is listed, then opens the pane directly (UX-5).
                    AccessibilityPermission.request()
                    AccessibilityPermission.openSettings()
                },
                dumpLayoutTrees: { Log.layout.info("No layout trees yet; the engine arrives in task T-0.24") },
                diagnostics: { [weak self] in self?.diagnostics() ?? "" }
            )
        )

        // The first-run explanation, once per launch while the permission is missing (UX-8).
        if !permission.isGranted {
            DispatchQueue.main.async {
                if PermissionGuide.ask() == .openSettings {
                    AccessibilityPermission.request()
                }
            }
        }
    }

    private func permissionChanged(_ granted: Bool) {
        menuBar?.update(Self.menuState(permissionGranted: granted))
    }

    /// Until the engine exists (T-0.24) nothing is tiled, so a granted permission shows the
    /// paused state and "Tile now" stays grey. Texts follow UX-9.
    private static func menuState(permissionGranted: Bool) -> MenuState {
        permissionGranted
            ? MenuState(icon: .paused, statusLine: "Tiling paused", canTileNow: false)
            : MenuState(icon: .warning, statusLine: "TILE32 needs permission to move windows",
                        canTileNow: false, needsPermission: true)
    }

    private func diagnostics() -> String {
        let info = ProcessInfo.processInfo
        var lines = [
            "TILE32 diagnostics",
            "Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")",
            "macOS: \(info.operatingSystemVersionString)",
            "Accessibility permission: \(AccessibilityPermission.isGranted ? "granted" : "missing")",
            "Displays:",
        ]
        for display in displays?.table.displays ?? [] {
            lines.append("  \(display.name) [\(display.id)] frame \(display.frame) usable \(display.usableArea)\(display.isPrimary ? " primary" : "")")
        }
        return lines.joined(separator: "\n")
    }
}
