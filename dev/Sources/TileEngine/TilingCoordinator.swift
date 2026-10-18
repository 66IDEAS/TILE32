// Turns events into reconcile runs (milestone M1, architecture TA-9, TA-12, TA-13).
// Every trigger only asks for a run; runs are coalesced, never overlap, and wait while
// the mouse button is held so TILE32 never fights a drag.
import AppKit
import CoreGraphics
import TileAX
import TileCore
import TileGeometry
import TileLog
import TileSpaces

@MainActor
public final class TilingCoordinator {
    public enum RunState: Sendable, Equatable { case running, paused, noPermission }

    /// Quiet time after the last trigger, and the longest wait after the first (TA-12).
    static let quietTime: Duration = .milliseconds(120)
    static let longestWait: Duration = .milliseconds(400)
    /// How often the window server's on-screen list is compared (cheap: milliseconds).
    static let pollInterval: TimeInterval = 1
    /// Move and resize events right after TILE32's own writes are its own echo (TA-12).
    static let echoWindow: Duration = .milliseconds(700)

    public private(set) var state: RunState
    public private(set) var lastSummary = ReconcileSummary()

    private let engine: LayoutEngine
    private let spaceService: SpaceService
    private let displays: @MainActor () -> DisplayTable
    private let limits: @MainActor () -> WindowLimits
    private let onlyBundleIDs: Set<String>?
    private let onChange: @MainActor () -> Void

    private var events: AXEventSource?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var pollTimer: Timer?
    private var lastOnScreen: Set<CGWindowID> = []
    private var firstTrigger: ContinuousClock.Instant?
    private var lastTrigger: ContinuousClock.Instant?
    private var scheduled = false
    private var running = false
    private var runAgain = false
    private var lastWrite: ContinuousClock.Instant = .now - .seconds(10)

    /// `onlyBundleIDs` limits tiling to some apps; used by test runs on FakeWindows.
    public init(engine: LayoutEngine, spaceService: SpaceService, initialState: RunState,
                displays: @escaping @MainActor () -> DisplayTable,
                limits: @escaping @MainActor () -> WindowLimits,
                onlyBundleIDs: Set<String>? = nil,
                onChange: @escaping @MainActor () -> Void) {
        self.engine = engine
        self.spaceService = spaceService
        self.state = initialState
        self.displays = displays
        self.limits = limits
        self.onlyBundleIDs = onlyBundleIDs
        self.onChange = onChange
        startListening()
    }

    // MARK: Run state (US-23)

    public func setState(_ newState: RunState) {
        guard newState != state else { return }
        state = newState
        Log.engine.info("Run state: \(String(describing: newState), privacy: .public)")
        if newState == .running { trigger("resume") }
        onChange()
    }

    // MARK: Triggers

    private func startListening() {
        events = AXEventSource { [weak self] _, event in
            Task { @MainActor in self?.handle(event) }
        }
        for app in apps() { events?.watch(app.pid) }

        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification, NSWorkspace.didUnhideApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification,
        ]
        for name in names {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
                MainActor.assumeIsolated { self?.handleWorkspace(name, pid: pid) }
            })
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollWindowServer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func handle(_ event: WindowEvent) {
        // TILE32's own writes come back as move and resize events (TA-12).
        if event == .moved || event == .resized, ContinuousClock.now - lastWrite < Self.echoWindow { return }
        trigger(event.rawValue)
    }

    private func handleWorkspace(_ name: NSNotification.Name, pid: pid_t?) {
        if name == NSWorkspace.didLaunchApplicationNotification, let pid { events?.watch(pid) }
        if name == NSWorkspace.didTerminateApplicationNotification, let pid {
            events?.unwatch(pid)
            AXWorker.shared.forget(pid)
        }
        trigger(name.rawValue)
    }

    /// Catches closed windows and moves made in Mission Control, which send no reliable
    /// notification (session A).
    private func pollWindowServer() {
        guard state == .running else { return }
        let pids = Set(apps().map(\.pid))
        let onScreen = Set(WindowServerList.onScreenNormalWindows().filter { pids.contains($0.ownerPID) }.map(\.number))
        if onScreen != lastOnScreen {
            lastOnScreen = onScreen
            trigger("window list changed")
        }
    }

    /// Asks for a reconcile run. Runs are coalesced: 120 ms after the last trigger, at most
    /// 400 ms after the first.
    public func trigger(_ reason: String) {
        guard state == .running else { return }
        let now = ContinuousClock.now
        if firstTrigger == nil { firstTrigger = now }
        lastTrigger = now
        Log.engine.debug("Trigger: \(reason, privacy: .public)")
        scheduleCheck()
    }

    private func scheduleCheck() {
        guard !scheduled else { return }
        scheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.quietTime)
            scheduled = false
            guard let first = firstTrigger, let last = lastTrigger else { return }
            let now = ContinuousClock.now
            if now - last < Self.quietTime, now - first < Self.longestWait {
                scheduleCheck()
                return
            }
            // Never while the user holds the mouse button: a drag or resize is in progress.
            if NSEvent.pressedMouseButtons & 1 != 0 {
                scheduleCheck()
                return
            }
            firstTrigger = nil
            lastTrigger = nil
            await run()
        }
    }

    // MARK: Reconcile

    private func run() async {
        guard state == .running else { return }
        if running { runAgain = true; return }
        running = true
        defer { running = false }
        repeat {
            runAgain = false
            let observation = await observe()
            let summary = await engine.reconcile(observation, limits: limits())
            if summary.changedAnything { lastWrite = .now }
            lastSummary = summary
            onChange()
        } while runAgain && state == .running
    }

    /// One reading of the shown desktops: windows, Spaces, order of use, unanswered and
    /// hidden apps.
    public func observe() async -> Observation {
        let apps = apps()
        let table = displays()
        let scan = await WindowScan.run(apps: apps, displays: table, spaceService: spaceService)
        let unanswered = Set(scan.apps.filter { $0.error == .cannotComplete }.map(\.app.pid))
        let hidden = Set(NSWorkspace.shared.runningApplications.filter(\.isHidden).map(\.processIdentifier))
        let recency = WindowServerList.frontToBack().map { WindowID(UInt64($0)) }
        return Observation(records: Array(scan.registry.records.values), displays: table,
                           currentSpaces: spaceService.currentSpaces(on: table), recency: recency,
                           unansweredPIDs: unanswered, hiddenPIDs: hidden)
    }

    private func apps() -> [AppInfo] {
        let all = AppInfo.runningRegularApps()
        guard let onlyBundleIDs else { return all }
        return all.filter { $0.bundleID.map(onlyBundleIDs.contains) ?? false }
    }

    /// "Tile now" while running: arranges afresh and keeps tiling (US-4.6).
    public func tileNow() async -> ReconcileSummary {
        let summary = await engine.reconcile(await observe(), limits: limits(), rebuild: true)
        lastWrite = .now
        lastSummary = summary
        onChange()
        return summary
    }

    /// What the status line shows (UX-9): windows tiled on the shown desktops, displays with
    /// tiles, windows minimised to make room, and windows that do not fit.
    public struct Counts: Sendable, Equatable {
        public let tiled: Int
        public let displays: Int
        public let minimised: Int
        public let doesNotFit: Int
    }

    public func counts() async -> Counts {
        let table = displays()
        let current = spaceService.currentSpaces(on: table)
        let shownKeys = Set(table.displays.map { LayoutKey(space: current[$0.id]?.id, display: $0.id) })
        let trees = await engine.trees.filter { shownKeys.contains($0.key) }
        let tiledIDs = Set(trees.values.flatMap(\.windowIDs))
        return Counts(
            tiled: tiledIDs.count,
            displays: trees.values.filter { !$0.isEmpty }.count,
            minimised: await engine.minimisedByEngine.count,
            doesNotFit: await engine.doesNotFit.intersection(tiledIDs).count
        )
    }

    public func stop() {
        pollTimer?.invalidate()
        events?.unwatchAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        workspaceObservers.removeAll()
    }
}
