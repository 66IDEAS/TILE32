// Wires the modules together. Holds no layout logic (architecture TA-2, TA-17).
import AppKit
import ServiceManagement
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
    var menuBar: MenuBarController?
    var displays: DisplayMonitor?
    var permission: PermissionMonitor?
    var spaces: SpaceMonitor?
    var coordinator: TilingCoordinator?
    var dragTracker: MouseDragTracker?
    let overlay = OverlayController()
    /// The windows behind the last "Windows" submenu, so a choice can raise the right one.
    var listedWindows: [WindowID: WindowSnapshot] = [:]
    var refreshingMenu = false
    /// The last Space reading, to log which windows moved to another desktop (session A).
    var lastSpaceMap: SpaceDiagnostics.SpaceMap = [:]
    /// Shown in the status line after "Untile" until the state changes (UX-9).
    var showRestoredMessage = false
    let engine = LayoutEngine()
    let limitStore = WindowLimitStore()
    lazy var limits = limitStore.load()
    let runStateStore = RunStateStore()
    let excludedStore = ExcludedAppsStore()
    /// The app in front when the menu last opened (UX-7).
    var frontApp: MenuApp?

    var displayTable: DisplayTable { displays?.table ?? DisplayTable(screens: []) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        Log.ui.info("TILE32 \(version, privacy: .public) started")

        displays = DisplayMonitor { [weak self] _ in self?.coordinator?.trigger("displays changed") }
        #if DEBUG
        if runDebugModeIfRequested() { return }
        #endif
        startSpaceMonitor()
        let permission = PermissionMonitor { [weak self] granted in self?.permissionChanged(granted) }
        self.permission = permission

        coordinator = TilingCoordinator(
            engine: engine, spaceService: SkyLightSpaceService.shared,
            initialState: permission.isGranted ? runStateStore.storedState : .noPermission,
            displays: { [weak self] in self?.displayTable ?? DisplayTable(screens: []) },
            limits: { [weak self] in self?.limits ?? WindowLimits() },
            onChange: { [weak self] in self?.updateMenu() }
        )
        coordinator?.excludedBundleIDs = { [weak self] in
            Set(self?.excludedStore.load().map(\.bundleID) ?? [])
        }
        coordinator?.layoutStore = StoredLayoutStore()
        if let coordinator { Task { await coordinator.restoreLayouts() } }

        menuBar = MenuBarController(
            state: baseMenuState(),
            actions: MenuActions(
                tileNow: { [weak self] in self?.tileNowFromMenu() },
                makeSizesEqual: { [weak self] in
                    guard let coordinator = self?.coordinator else { return }
                    Task { await coordinator.makeSizesEqual() }
                },
                menuWillOpen: { [weak self] in self?.refreshWindowMenu() },
                raiseWindow: { [weak self] id in self?.raise(id) },
                setWindowLimit: { [weak self] uuid, value in self?.setWindowLimit(uuid, value) },
                untile: { [weak self] in self?.untileFromMenu() },
                togglePause: { [weak self] in self?.togglePause() },
                toggleExclude: { [weak self] app in self?.toggleExclude(app) },
                toggleStartAtLogin: { Self.toggleStartAtLogin() },
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
        updateMenu()

        updateDragTracking(granted: permission.isGranted)
        #if DEBUG
        // A first Space reading, so the first desktop switch can already report moved windows.
        if permission.isGranted { Task { await logSpaceWindows() } }
        #endif
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

    // MARK: Run state (US-23, US-27)

    private func permissionChanged(_ granted: Bool) {
        coordinator?.setState(granted ? runStateStore.storedState : .noPermission)
        updateDragTracking(granted: granted)
        updateMenu()
    }

    private func togglePause() {
        guard let coordinator else { return }
        let resume = coordinator.state == .paused
        runStateStore.setPaused(!resume)
        showRestoredMessage = false
        coordinator.setState(resume ? .running : .paused)
    }

    // MARK: Drag-to-split (M2, US-13 to US-18)

    /// The tracker watches title-bar drags while the permission is granted; the overlay shows
    /// where a release would put the window, and the coordinator applies the drop.
    func updateDragTracking(granted: Bool) {
        guard granted else {
            dragTracker?.stop()
            overlay.hide()
            return
        }
        if dragTracker == nil {
            #if DEBUG
            let tracker = MouseDragTracker(displays: { [weak self] in self?.displayTable ?? DisplayTable(screens: []) },
                                           describe: { number, pid in await Self.describeWindow(number: number, pid: pid) })
            #else
            let tracker = MouseDragTracker(displays: { [weak self] in self?.displayTable ?? DisplayTable(screens: []) })
            #endif
            tracker.onDragMove = { [weak self] number, point in self?.dragMoved(number, point) }
            tracker.onDragEnd = { [weak self] number, point, cancelled in self?.dragEnded(number, point, cancelled) }
            tracker.onCancel = { [weak self] in self?.overlay.hide() }
            tracker.onResize = { [weak self] number, frame, edges, final in self?.resized(number, frame, edges, final) }
            dragTracker = tracker
        }
        dragTracker?.start()
    }

    private func dragMoved(_ number: CGWindowID, _ point: CGPoint) {
        guard let coordinator else { return }
        Task {
            let table = displayTable
            if let preview = await coordinator.dragMoved(number, at: point),
               let display = table.display(id: preview.key.display) {
                overlay.show(area: preview.area, label: OverlayController.label(for: preview.target), on: display, table: table)
            } else {
                overlay.hide()
            }
        }
    }

    /// Live neighbours and the share label while resizing; snap and write on release (US-28).
    private func resized(_ number: CGWindowID, _ frame: CGRect, _ edges: Set<DragStateMachine.Edge>, _ final: Bool) {
        guard let coordinator else { return }
        let coreEdges = Set(edges.compactMap { Edge(rawValue: $0.rawValue) })
        Task {
            let share = await coordinator.resized(number, to: frame, edges: coreEdges, final: final)
            let table = displayTable
            if !final, let share, let display = table.display(mostlyContaining: frame) {
                let percent = Int((share * 100).rounded())
                overlay.showLabel("\(percent)%", centredIn: frame, on: display, table: table)
            } else {
                overlay.hide()
            }
        }
    }

    private func dragEnded(_ number: CGWindowID, _ point: CGPoint, _ cancelled: Bool) {
        overlay.hide()
        guard let coordinator else { return }
        Task { await coordinator.dragEnded(number, at: point, cancelled: cancelled) }
    }

    // MARK: Menu state (UX-2, UX-9)

    private func baseMenuState() -> MenuState {
        let entries = displayTable.displays.map { display in
            WindowLimitMenuEntry(displayUUID: display.id.uuid, displayName: display.name, limit: limits.limit(for: display))
        }
        let state = coordinator?.state ?? .noPermission
        let excluded = excludedStore.load().map { MenuApp(bundleID: $0.bundleID, name: $0.name) }
        var menuState = baseMenuStateForRunState(state, entries: entries)
        menuState.frontApp = frontApp
        menuState.excludedApps = excluded
        return menuState
    }

    private func baseMenuStateForRunState(_ state: TilingCoordinator.RunState, entries: [WindowLimitMenuEntry]) -> MenuState {
        switch state {
        case .noPermission:
            return MenuState(icon: .warning, statusLine: "TILE32 needs permission to move windows",
                             canTileNow: false, needsPermission: true, windowLimits: entries)
        case .paused:
            let line = showRestoredMessage ? "Windows restored - tiling paused"
                : runStateStore.hasResumedOnce ? "Tiling paused" : "Tiling paused - choose Resume tiling to start"
            return MenuState(icon: .paused, statusLine: line, canTileNow: false, windowLimits: entries)
        case .running:
            return MenuState(icon: .active, statusLine: "No windows to arrange", canTileNow: true,
                             windowLimits: entries, isRunning: true)
        }
    }

    func updateMenu() {
        Task {
            var state = baseMenuState()
            state.canUntile = await engine.canUntile
            if coordinator?.state == .running, let counts = await coordinator?.counts() {
                state.statusLine = Self.statusLine(counts)
                state.notFitCount = counts.doesNotFit
                // Fallback mode (US-12.7): without Space information only visible windows are arranged.
                if !SkyLightSpaceService.shared.isAvailable {
                    state.statusLine = "Spaces not detected - only visible windows are arranged"
                }
            }
            menuBar?.update(state)
        }
    }

    /// "Tiling 18 windows on 2 displays - 15 minimised to make room - 1 does not fit" (UX-9).
    static func statusLine(_ counts: TilingCoordinator.Counts) -> String {
        guard counts.tiled > 0 else { return "No windows to arrange" }
        var line = "Tiling \(counts.tiled) \(counts.tiled == 1 ? "window" : "windows") on \(counts.displays) "
            + (counts.displays == 1 ? "display" : "displays")
        if counts.minimised > 0 { line += " - \(counts.minimised) minimised to make room" }
        if counts.doesNotFit > 0 { line += " - \(counts.doesNotFit) \(counts.doesNotFit == 1 ? "does" : "do") not fit" }
        return line
    }

    // MARK: Commands

    /// "Tile now" (US-4.6): arranges the shown desktops afresh; tiling keeps running.
    private func tileNowFromMenu() {
        guard let coordinator, coordinator.state == .running else { return }
        Task { _ = await coordinator.tileNow() }
    }

    /// "Untile" (US-24): restores every window, then pauses (US-24.4).
    private func untileFromMenu() {
        Task {
            coordinator?.setState(.paused)
            runStateStore.setPaused(true)
            _ = await engine.untile(displays: displayTable)
            showRestoredMessage = true
            updateMenu()
        }
    }

    /// US-31.2 and US-31.7: remembered per display and applied at once.
    private func setWindowLimit(_ uuid: String, _ value: Int) {
        limits.set(value, for: DisplayID(uuid: uuid))
        limitStore.save(limits)
        Log.layout.info("Window limit for \(uuid, privacy: .public) set to \(value)")
        coordinator?.trigger("window limit changed")
        updateMenu()
    }

    /// US-25: registers or removes TILE32 as a login item.
    private static func toggleStartAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
            Log.ui.info("Start at login: \(String(describing: service.status), privacy: .public)")
        } catch {
            Log.ui.error("Start at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// US-22: excluded windows float at once and the others re-flow; including them again
    /// brings them back into the layout.
    private func toggleExclude(_ app: MenuApp) {
        excludedStore.toggle(ExcludedApp(bundleID: app.bundleID, name: app.name))
        Log.layout.info("Exclude list changed for \(app.bundleID, privacy: .public)")
        coordinator?.trigger("exclude list changed")
        updateMenu()
    }

    /// Reads the windows again whenever the menu opens; the submenu updates while open (US-3.3).
    func refreshWindowMenu() {
        // The menu of an agent app does not activate it, so this is the app the user was using.
        if let app = NSWorkspace.shared.frontmostApplication, app.activationPolicy == .regular,
           let bundleID = app.bundleIdentifier, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            frontApp = MenuApp(bundleID: bundleID, name: app.localizedName ?? bundleID)
        } else {
            frontApp = nil
        }
        guard AccessibilityPermission.isGranted, !refreshingMenu else { return }
        refreshingMenu = true
        let apps = AppInfo.runningRegularApps()
        let table = displayTable
        Task {
            let minimised = await engine.minimisedByEngine
            let notFitting = await engine.doesNotFit
            let shares = await coordinator?.widthShares() ?? [:]
            let result = await WindowMenuLoader.load(apps: apps, displays: table, spaceService: SkyLightSpaceService.shared,
                                                     minimisedToMakeRoom: minimised, doesNotFit: notFitting, shares: shares)
            listedWindows = result.windows
            menuBar?.setWindowContent(result.content)
            refreshingMenu = false
        }
        updateMenu()
    }

    /// Brings the chosen window to the front (US-3.4). A window minimised to make room comes
    /// back and swaps in through the next reconcile (US-31.4).
    private func raise(_ id: WindowID) {
        guard let snapshot = listedWindows[id] else { return }
        let pid = snapshot.app.pid
        Task {
            if snapshot.isMinimized {
                _ = await AXWorker.shared.run(for: pid) { WindowActions.setMinimised(snapshot.element, false) }
            }
            let error = await AXWorker.shared.run(for: pid) { WindowActions.raise(snapshot.element) }
            if error != .success {
                Log.ax.info("Raising \(id.description, privacy: .public) failed: AXError \(error.rawValue)")
            }
            NSRunningApplication(processIdentifier: pid)?.activate()
            coordinator?.trigger("window raised from the menu")
        }
    }
}

/// The paused flag and whether the user ever resumed (US-23.3, US-23.5, TA-19).
struct RunStateStore {
    private static let pausedKey = "tilingPaused"
    private static let resumedKey = "hasResumedOnce"

    /// A fresh install starts paused (US-23.5).
    var storedState: TilingCoordinator.RunState {
        (UserDefaults.standard.object(forKey: Self.pausedKey) as? Bool ?? true) ? .paused : .running
    }

    var hasResumedOnce: Bool { UserDefaults.standard.bool(forKey: Self.resumedKey) }

    func setPaused(_ paused: Bool) {
        UserDefaults.standard.set(paused, forKey: Self.pausedKey)
        if !paused { UserDefaults.standard.set(true, forKey: Self.resumedKey) }
    }
}
