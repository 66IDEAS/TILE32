// Wires the modules together. Holds no layout logic (architecture TA-2, TA-17).
import AppKit
import TileAX
import TileCore
import TileEngine
import TileGeometry
import TileInput
import TileLog
import TileSpaces
import TileUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var displays: DisplayMonitor?
    private var permission: PermissionMonitor?
    private var spaces: SpaceMonitor?
    private var dragTracker: MouseDragTracker?
    /// The windows behind the last "Windows" submenu, so a choice can raise the right one.
    private var listedWindows: [WindowID: WindowSnapshot] = [:]
    private var refreshingMenu = false
    private let engine = LayoutEngine()
    private let limitStore = WindowLimitStore()
    private lazy var limits = limitStore.load()

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
        // `--tile-now-fakewindows` runs "Tile now" on FakeWindows windows only (task T-0.24),
        // so the engine can be checked on the real screen without moving the owner's windows.
        if CommandLine.arguments.contains("--tile-now-fakewindows") {
            Task {
                await tileNow(onlyBundleID: "com.66ideas.tile32.FakeWindows")
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
            state: menuState(permissionGranted: permission.isGranted),
            actions: MenuActions(
                tileNow: { Log.layout.info("Tile now chosen; arranging windows arrives in task T-0.24") },
                menuWillOpen: { [weak self] in self?.refreshWindowMenu() },
                raiseWindow: { [weak self] id in self?.raise(id) },
                setWindowLimit: { [weak self] uuid, value in self?.setWindowLimit(uuid, value) },
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

        updateDragLogging(granted: permission.isGranted)
        refreshWindowMenu()

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

    /// "Tile now" (US-4). For the owner's windows it stays switched off until the owner agrees
    /// and open question Q-3 is decided (task T-0.24).
    private func tileNow(onlyBundleID: String?) async {
        guard AccessibilityPermission.isGranted else { return }
        let displays = self.displays?.table ?? DisplayTable(screens: [])
        let apps = AppInfo.runningRegularApps().filter { onlyBundleID == nil || $0.bundleID == onlyBundleID }
        let service = SkyLightSpaceService.shared
        let scan = await WindowScan.run(apps: apps, displays: displays, spaceService: service)
        var limits = self.limits
        // Test runs may override the limit for every display: `--window-limit 4`.
        if let index = CommandLine.arguments.firstIndex(of: "--window-limit"), index + 1 < CommandLine.arguments.count,
           let value = Int(CommandLine.arguments[index + 1]) {
            for display in displays.displays { limits.set(value, for: display.id) }
        }
        let recency = WindowServerList.frontToBack().map { WindowID(UInt64($0)) }
        _ = await engine.tileNow(records: Array(scan.registry.records.values), displays: displays,
                                 currentSpaces: service.currentSpaces(on: displays), limits: limits, recency: recency)
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

    /// Reads the windows again whenever the menu opens; the submenu updates while open (US-3.3).
    private func refreshWindowMenu() {
        guard AccessibilityPermission.isGranted, !refreshingMenu else { return }
        refreshingMenu = true
        let apps = AppInfo.runningRegularApps()
        let displays = self.displays?.table ?? DisplayTable(screens: [])
        Task {
            let minimised = await engine.minimisedByEngine
            let result = await WindowMenuLoader.load(apps: apps, displays: displays, spaceService: SkyLightSpaceService.shared,
                                                     minimisedToMakeRoom: minimised)
            listedWindows = result.windows
            menuBar?.setWindowContent(result.content)
            refreshingMenu = false
        }
    }

    /// Brings the chosen window to the front (US-3.4).
    private func raise(_ id: WindowID) {
        guard let snapshot = listedWindows[id] else { return }
        let pid = snapshot.app.pid
        Task {
            let error = await AXWorker.shared.run(for: pid) { WindowActions.raise(snapshot.element) }
            if error != .success {
                Log.ax.info("Raising \(id.description, privacy: .public) failed: AXError \(error.rawValue)")
            }
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    private func permissionChanged(_ granted: Bool) {
        menuBar?.update(menuState(permissionGranted: granted))
        updateDragLogging(granted: granted)
    }

    /// Spike S1 (T-0.21): in debug builds, every press, drag and resize is logged while the
    /// permission is granted. Nothing is changed.
    private func updateDragLogging(granted: Bool) {
        #if DEBUG
        if granted {
            if dragTracker == nil {
                dragTracker = MouseDragTracker(
                    displays: { [weak self] in self?.displays?.table ?? DisplayTable(screens: []) },
                    describe: { number, pid in await Self.describeWindow(number: number, pid: pid) }
                )
            }
            dragTracker?.start()
        } else {
            dragTracker?.stop()
        }
        #endif
    }

    /// App name and TILE32's classification of one window, for the S1 log.
    private static func describeWindow(number: CGWindowID, pid: pid_t) async -> String {
        guard let running = NSRunningApplication(processIdentifier: pid) else { return "pid \(pid)" }
        let app = AppInfo(pid: pid, bundleID: running.bundleIdentifier, name: running.localizedName ?? "?")
        guard running.activationPolicy == .regular else { return "\(app.name) [not a regular app]" }
        let results = await WindowReader.readAll([app]) { SkyLightSpaceService.shared.windowNumber(of: $0) }
        guard let snapshot = results.first?.windows.first(where: { $0.windowNumber == number }) else {
            return "\(app.name) [not listed]"
        }
        let classification: String = switch WindowClassifier.classify(snapshot) {
        case .tiled: "tiled"
        case .minimised: "minimised"
        case .floating(let reason): "floating: \(reason.rawValue)"
        }
        return "\(app.name) [\(classification)]"
    }

    /// Until the engine exists (T-0.24) nothing is tiled, so a granted permission shows the
    /// paused state and "Tile now" stays grey. Texts follow UX-9.
    private func menuState(permissionGranted: Bool) -> MenuState {
        let entries = (displays?.table.displays ?? []).map { display in
            WindowLimitMenuEntry(displayUUID: display.id.uuid, displayName: display.name, limit: limits.limit(for: display))
        }
        return permissionGranted
            ? MenuState(icon: .paused, statusLine: "Tiling paused", canTileNow: false, windowLimits: entries)
            : MenuState(icon: .warning, statusLine: "TILE32 needs permission to move windows",
                        canTileNow: false, needsPermission: true, windowLimits: entries)
    }

    /// US-31.2: remembered per display. Applying a new limit to tiled layouts at once is T-1.14.
    private func setWindowLimit(_ uuid: String, _ value: Int) {
        limits.set(value, for: DisplayID(uuid: uuid))
        limitStore.save(limits)
        Log.layout.info("Window limit for \(uuid, privacy: .public) set to \(value)")
        menuBar?.update(menuState(permissionGranted: permission?.isGranted ?? false))
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
