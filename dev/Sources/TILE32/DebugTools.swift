// Spike and test tools: debug menu actions and command-line test modes (tasks T-0.14 to
// T-0.24, sessions A to C). None of this changes the normal app.
import AppKit
import TileAX
import TileCore
import TileEngine
import TileGeometry
import TileInput
import TileLog
import TileSpaces
import TileUI

extension AppDelegate {
    /// Logs which undocumented Space functions were found, then the Space of each display (S6).
    func startSpaceMonitor() {
        let service = SkyLightSpaceService.shared
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        Log.spaces.info("macOS \(osVersion, privacy: .public); Space functions available: \(service.isAvailable)")
        for key in ["MainConnectionID", "CopyManagedDisplaySpaces", "CopySpacesForWindows", "AXUIElementGetWindow"] {
            Log.spaces.info("  \(key, privacy: .public): \(service.resolvedFunctions[key] ?? "missing", privacy: .public)")
        }
        let monitor = SpaceMonitor(service: service, displays: { [weak self] in
            self?.displayTable ?? DisplayTable(screens: [])
        }, onChange: { [weak self] in
            self?.updateMenu()
            #if DEBUG
            // Spike S6 and S3: record everything on every Space switch.
            self?.logSpaceDiagnostics(windows: true)
            #endif
        })
        monitor.logCurrentSpaces()
        spaces = monitor
    }

    /// Lists every window with its number, display, Space and class (T-0.14).
    func dumpWindows() {
        guard AccessibilityPermission.isGranted else { return }
        let apps = AppInfo.runningRegularApps()
        let table = displayTable
        Task {
            let result = await WindowScan.run(apps: apps, displays: table, spaceService: SkyLightSpaceService.shared)
            WindowScan.log(result, displays: table)
            for (key, tree) in await engine.trees {
                Log.layout.info("Tree \(key.description, privacy: .public): \(tree.windowIDs.map(\.description).joined(separator: " "), privacy: .public)")
            }
        }
    }

    /// Spike tools for S6 and S3 (T-0.17).
    func logSpaceDiagnostics(windows: Bool) {
        SpaceDiagnostics.logSpaces(service: SkyLightSpaceService.shared, displays: displayTable)
        guard windows else { return }
        Task { await logSpaceWindows() }
    }

    func logSpaceWindows() async {
        guard AccessibilityPermission.isGranted else { return }
        let map = await SpaceDiagnostics.logWindows(apps: AppInfo.runningRegularApps(), service: SkyLightSpaceService.shared,
                                                    displays: displayTable)
        SpaceDiagnostics.logMoves(from: lastSpaceMap, to: map)
        lastSpaceMap = map
    }

    func runFrameWriteTest(onlyBundleID: String?) {
        Task { await frameWriteTest(onlyBundleID: onlyBundleID) }
    }

    func frameWriteTest(onlyBundleID: String?) async {
        guard AccessibilityPermission.isGranted else { return }
        await FrameWriteTest.run(apps: AppInfo.runningRegularApps(), displays: displayTable,
                                 spaceService: SkyLightSpaceService.shared, onlyBundleID: onlyBundleID)
    }

    func diagnostics() -> String {
        let info = ProcessInfo.processInfo
        var lines = [
            "TILE32 diagnostics",
            "Version: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")",
            "macOS: \(info.operatingSystemVersionString)",
            "Accessibility permission: \(AccessibilityPermission.isGranted ? "granted" : "missing")",
            "Run state: \(String(describing: coordinator?.state ?? .noPermission))",
            "Displays:",
        ]
        for display in displayTable.displays {
            lines.append("  \(display.name) [\(display.id)] frame \(display.frame) usable \(display.usableArea)\(display.isPrimary ? " primary" : "")")
        }
        let service = SkyLightSpaceService.shared
        lines.append("Space functions: " + ["MainConnectionID", "CopyManagedDisplaySpaces", "CopySpacesForWindows", "AXUIElementGetWindow"]
            .map { "\($0)=\(service.resolvedFunctions[$0] ?? "missing")" }.joined(separator: ", "))
        lines += spaces?.describe() ?? []
        return lines.joined(separator: "\n")
    }

    #if DEBUG
    /// Spike S1: every press, drag and resize is logged while the permission is granted.
    func updateDragLogging(granted: Bool) {
        if granted {
            if dragTracker == nil {
                dragTracker = MouseDragTracker(
                    displays: { [weak self] in self?.displayTable ?? DisplayTable(screens: []) },
                    describe: { number, pid in await Self.describeWindow(number: number, pid: pid) }
                )
            }
            dragTracker?.start()
        } else {
            dragTracker?.stop()
        }
    }

    /// App name and TILE32's classification of one window, for the S1 log.
    static func describeWindow(number: CGWindowID, pid: pid_t) async -> String {
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

    static let fakeWindowsID = "com.66ideas.tile32.FakeWindows"

    /// Command-line test modes. Each one runs without a menu-bar icon and quits.
    /// Returns true when a mode was started.
    func runDebugModeIfRequested() -> Bool {
        let arguments = CommandLine.arguments
        func run(_ work: @escaping @MainActor () async -> Void) -> Bool {
            Task {
                await work()
                NSApp.terminate(nil)
            }
            return true
        }
        if arguments.contains("--dump-windows") {
            startSpaceMonitor()
            return run {
                let result = await WindowScan.run(apps: AppInfo.runningRegularApps(), displays: self.displayTable,
                                                  spaceService: SkyLightSpaceService.shared)
                WindowScan.log(result, displays: self.displayTable)
            }
        }
        if arguments.contains("--dump-spaces") {
            return run {
                self.logSpaceDiagnostics(windows: false)
                await self.logSpaceWindows()
            }
        }
        // Session B: moves the owner's windows; only with the owner's agreement.
        if arguments.contains("--frame-test-all") { return run { await self.frameWriteTest(onlyBundleID: nil) } }
        if arguments.contains("--frame-test-fakewindows") { return run { await self.frameWriteTest(onlyBundleID: Self.fakeWindowsID) } }
        if arguments.contains("--tile-now-fakewindows") { return run { await self.tileNowFakeWindows() } }
        if arguments.contains("--tile-then-untile-fakewindows") {
            return run {
                await self.tileNowFakeWindows()
                try? await Task.sleep(for: .seconds(3))
                _ = await self.engine.untile(displays: self.displayTable)
            }
        }
        if arguments.contains("--hidden-space-write-test") { return run { await self.hiddenSpaceWriteTest() } }
        // Automatic tiling of FakeWindows windows only, for M1 checks: runs until --quit-after.
        if arguments.contains("--auto-fakewindows") {
            // `--force-fallback` acts as if the Space functions were missing (US-12.7, T-1.8).
            let service: SpaceService = arguments.contains("--force-fallback")
                ? FakeSpaceService(isAvailable: false) : SkyLightSpaceService.shared
            let coordinator = TilingCoordinator(
                engine: engine, spaceService: service, initialState: .running,
                displays: { [weak self] in self?.displayTable ?? DisplayTable(screens: []) },
                limits: { [weak self] in self?.testLimits() ?? WindowLimits() },
                onlyBundleIDs: [Self.fakeWindowsID], onChange: {}
            )
            self.coordinator = coordinator
            coordinator.trigger("test start")
            // `--limit-later 8:12` changes the test limit after 8 seconds (owner's step 9).
            if let later = value(after: "--limit-later")?.split(separator: ":"), later.count == 2,
               let delay = Double(later[0]), let limit = Int(later[1]) {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    Self.testLimitOverride = limit
                    coordinator.trigger("test limit changed to \(limit)")
                }
            }
            let seconds = value(after: "--quit-after").flatMap(Double.init) ?? 30
            return run {
                try? await Task.sleep(for: .seconds(seconds))
                coordinator.stop()
            }
        }
        return false
    }

    private func value(after name: String) -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static var testLimitOverride: Int?

    /// The owner's limits, or `--window-limit N` for every display in test runs.
    private func testLimits() -> WindowLimits {
        var limits = self.limits
        if let value = Self.testLimitOverride ?? value(after: "--window-limit").flatMap(Int.init) {
            for display in displayTable.displays { limits.set(value, for: display.id) }
        }
        return limits
    }

    private func tileNowFakeWindows() async {
        let service = SkyLightSpaceService.shared
        let apps = AppInfo.runningRegularApps().filter { $0.bundleID == Self.fakeWindowsID }
        let scan = await WindowScan.run(apps: apps, displays: displayTable, spaceService: service)
        let recency = WindowServerList.frontToBack().map { WindowID(UInt64($0)) }
        _ = await engine.tileNow(records: Array(scan.registry.records.values), displays: displayTable,
                                 currentSpaces: service.currentSpaces(on: displayTable), limits: testLimits(), recency: recency)
    }

    /// Session A (S3): waits until the owner moves a FakeWindows window to another desktop,
    /// then tries to move it while it is hidden.
    private func hiddenSpaceWriteTest() async {
        let service = SkyLightSpaceService.shared
        let table = displayTable
        let apps = AppInfo.runningRegularApps().filter { $0.bundleID == Self.fakeWindowsID }
        let scan = await WindowScan.run(apps: apps, displays: table, spaceService: service)
        guard let record = scan.registry.records.values.first(where: { WindowClassifier.classify($0.snapshot) == .tiled }),
              let number = record.snapshot.windowNumber, let original = record.snapshot.frame else {
            Log.spaces.error("S3 hidden write: no FakeWindows window found")
            return
        }
        Log.spaces.info("S3 hidden write: watching w\(number); waiting up to 90 s for it to be moved to another desktop")
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .seconds(90) {
            let shown = Set(service.currentSpaces(on: table).values.map(\.id))
            if let spaces = service.spaces(of: [number])[number], !spaces.isEmpty, shown.isDisjoint(with: spaces) {
                try? await Task.sleep(for: .seconds(1))
                let target = original.offsetBy(dx: 200, dy: 100)
                let result = await AXWorker.shared.run(for: record.snapshot.app.pid) {
                    FrameWriter.write(target, to: record.snapshot.element, pid: record.snapshot.app.pid)
                }
                try? await Task.sleep(for: .milliseconds(500))
                let server = WindowServerList.window(number: number)?.bounds
                Log.spaces.info("""
                    S3 hidden write: w\(number) on \(spaces.map(\.description).joined(separator: ","), privacy: .public): \
                    errors \(result.sizeError.rawValue)/\(result.positionError.rawValue), \
                    requested \(String(describing: target), privacy: .public), \
                    Accessibility reads \(result.actual.map { String(describing: $0) } ?? "nothing", privacy: .public), \
                    window server reports \(server.map { String(describing: $0) } ?? "nothing", privacy: .public)
                    """)
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
        Log.spaces.info("S3 hidden write: the window was not moved within 90 s")
    }
    #endif
}
