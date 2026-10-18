// Wires the modules together. Holds no layout logic (architecture TA-2, TA-17).
import AppKit
import TileAX
import TileEngine
import TileGeometry
import TileLog
import TileSpaces
import TileUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var displays: DisplayMonitor?
    private var permission: PermissionMonitor?
    private var spaces: SpaceMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.ui.info("TILE32 \(version, privacy: .public) started")

        displays = DisplayMonitor { _ in }
        #if DEBUG
        // Debug builds only: `open -n TILE32.app --args --dump-windows` logs every window and
        // quits, without a menu-bar icon. Lets Claude check readings without opening menus.
        if CommandLine.arguments.contains("--dump-windows") {
            startSpaceMonitor()
            runDumpAndQuit()
            return
        }
        // `--frame-test-fakewindows` runs the S2 tool on FakeWindows windows only, so frame
        // writing can be checked without moving any of the owner's windows.
        if CommandLine.arguments.contains("--frame-test-fakewindows") {
            Task {
                await frameWriteTest(onlyBundleID: "com.66ideas.tile32.FakeWindows")
                NSApp.terminate(nil)
            }
            return
        }
        if CommandLine.arguments.contains("--dump-spaces") {
            Task {
                logSpaceDiagnostics(windows: false)
                await logSpaceWindows()
                NSApp.terminate(nil)
            }
            return
        }
        #endif
        startSpaceMonitor()
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
                dumpLayoutTrees: { [weak self] in self?.dumpWindows() },
                logSpaces: { [weak self] in self?.logSpaceDiagnostics(windows: false) },
                logWindows: { [weak self] in self?.logSpaceDiagnostics(windows: true) },
                frameWriteTest: { [weak self] in self?.runFrameWriteTest(onlyBundleID: nil) },
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

    /// Logs which undocumented Space functions were found, then the Space of each display (S6).
    private func startSpaceMonitor() {
        let service = SkyLightSpaceService.shared
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        Log.spaces.info("macOS \(osVersion, privacy: .public); Space functions available: \(service.isAvailable)")
        for key in ["MainConnectionID", "CopyManagedDisplaySpaces", "CopySpacesForWindows", "AXUIElementGetWindow"] {
            Log.spaces.info("  \(key, privacy: .public): \(service.resolvedFunctions[key] ?? "missing", privacy: .public)")
        }
        let monitor = SpaceMonitor(service: service, displays: { [weak self] in
            self?.displays?.table ?? DisplayTable(screens: [])
        }, onChange: { [weak self] in
            #if DEBUG
            // Spike S6 and S3: record everything on every Space switch.
            self?.logSpaceDiagnostics(windows: true)
            #endif
        })
        monitor.logCurrentSpaces()
        spaces = monitor
    }

    /// Until the engine exists (T-0.24) there are no trees; this lists every window with its
    /// number, display and Space (T-0.14).
    private func dumpWindows() {
        guard AccessibilityPermission.isGranted else {
            Log.layout.info("Dump skipped: Accessibility permission missing")
            return
        }
        let apps = AppInfo.runningRegularApps()
        let displays = self.displays?.table ?? DisplayTable(screens: [])
        Task {
            let result = await WindowScan.run(apps: apps, displays: displays, spaceService: SkyLightSpaceService.shared)
            WindowScan.log(result, displays: displays)
        }
    }

    #if DEBUG
    private func runDumpAndQuit() {
        let apps = AppInfo.runningRegularApps()
        let displays = self.displays?.table ?? DisplayTable(screens: [])
        Log.layout.info("Dump mode: permission \(AccessibilityPermission.isGranted ? "granted" : "missing", privacy: .public)")
        Task {
            let result = await WindowScan.run(apps: apps, displays: displays, spaceService: SkyLightSpaceService.shared)
            WindowScan.log(result, displays: displays)
            NSApp.terminate(nil)
        }
    }
    #endif

    /// Spike tools for S6 and S3 (T-0.17).
    private func logSpaceDiagnostics(windows: Bool) {
        let displays = self.displays?.table ?? DisplayTable(screens: [])
        SpaceDiagnostics.logSpaces(service: SkyLightSpaceService.shared, displays: displays)
        guard windows else { return }
        Task { await logSpaceWindows() }
    }

    private func logSpaceWindows() async {
        guard AccessibilityPermission.isGranted else { return }
        let displays = self.displays?.table ?? DisplayTable(screens: [])
        await SpaceDiagnostics.logWindows(apps: AppInfo.runningRegularApps(), service: SkyLightSpaceService.shared, displays: displays)
    }

    private func runFrameWriteTest(onlyBundleID: String?) {
        Task { await frameWriteTest(onlyBundleID: onlyBundleID) }
    }

    private func frameWriteTest(onlyBundleID: String?) async {
        guard AccessibilityPermission.isGranted else { return }
        let displays = self.displays?.table ?? DisplayTable(screens: [])
        await FrameWriteTest.run(apps: AppInfo.runningRegularApps(), displays: displays,
                                 spaceService: SkyLightSpaceService.shared, onlyBundleID: onlyBundleID)
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
        let service = SkyLightSpaceService.shared
        lines.append("Space functions: " + ["MainConnectionID", "CopyManagedDisplaySpaces", "CopySpacesForWindows", "AXUIElementGetWindow"]
            .map { "\($0)=\(service.resolvedFunctions[$0] ?? "missing")" }.joined(separator: ", "))
        lines += spaces?.describe() ?? []
        return lines.joined(separator: "\n")
    }
}
