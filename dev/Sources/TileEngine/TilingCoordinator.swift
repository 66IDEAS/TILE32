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
    /// Minimise and restore animations take about half a second; during them macOS can
    /// still report the old state. After a run that minimised, restored or took in a window,
    /// the next reading waits this long (found in the M1 window limit check: flapping).
    static let settleTime: Duration = .milliseconds(800)
    /// Wait before writing again to a window whose app ignored a write (for example Safari
    /// right after moving to a display with another scale).
    static let writeRetryDelay: Duration = .seconds(1)
    /// A reading taken during a desktop switch is read again after this wait, at most
    /// `maximumMidSwitchHolds` times in a row; after that it is taken as it is.
    static let midSwitchRetryDelay: Duration = .milliseconds(250)
    static let maximumMidSwitchHolds = 8

    public private(set) var state: RunState
    public private(set) var lastSummary = ReconcileSummary()

    private let engine: LayoutEngine
    private let spaceService: SpaceService
    private let displays: @MainActor () -> DisplayTable
    private let limits: @MainActor () -> WindowLimits
    private let onlyBundleIDs: Set<String>?
    /// Apps the user excluded (US-22); read on every run so changes apply at once.
    public var excludedBundleIDs: @MainActor () -> Set<String> = { [] }
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
    private var lastAnimation: ContinuousClock.Instant = .now - .seconds(10)
    /// The last reading, so a drop can write without reading every window again.
    private var lastObservation: Observation?
    private var writeRetryPending = false
    private var midSwitchHolds = 0
    /// While the screen is locked, the displays sleep or another user is active, macOS takes
    /// displays offline and moves windows around; nothing is read or written then. After that
    /// TILE32 waits `screenReturnDelay` before it reads again (found on 2026-10-19: after an
    /// unlock the windows of desktop 2 were arranged afresh).
    private var readAgainAfter: ContinuousClock.Instant = .now - .seconds(10)
    private var distributedObservers: [NSObjectProtocol] = []
    static let screenReturnDelay: Duration = .seconds(2)
    /// Asked live from macOS on every check, so a missing "unlocked" notification can never
    /// leave tiling stopped (found on 2026-10-24: drop zones were often missing, and macOS does
    /// not always post "screen is unlocked" after a screen saver). The notifications only make
    /// TILE32 look again sooner.
    private var screenUnavailable: Bool { Self.screenUnavailableNow() }

    static func screenUnavailableNow() -> Bool {
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any] {
            if session["CGSSessionScreenIsLocked"] as? Bool == true { return true }
            if session[kCGSessionOnConsoleKey as String] as? Bool == false { return true }
        }
        return CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }
    /// The last drag or resize step. Between the mouse-up and the drop taking the lock, a
    /// layout run must not start, or it puts the dragged window back first (found on
    /// 2026-10-19). Cleared when the gesture ends; ignored after `gestureTimeout` in case an
    /// end is never reported.
    private var lastGestureStep: ContinuousClock.Instant = .now - .seconds(10)
    static let gestureTimeout: Duration = .seconds(2)

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
        Log.engine.notice("Run state: \(String(describing: newState), privacy: .public)")
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

        let screenNames: [NSNotification.Name] = [
            NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in screenNames {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenStateChanged(name) }
            })
        }
        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"].map({ NSNotification.Name($0) }) {
            distributedObservers.append(distributed.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.screenStateChanged(name) }
            })
        }

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollWindowServer() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func screenStateChanged(_ name: NSNotification.Name) {
        let unavailable = screenUnavailable
        Log.engine.notice("\(name.rawValue, privacy: .public): screen \(unavailable ? "unavailable, tiling waits" : "available", privacy: .public)")
        // Every one of these events may move displays and windows: read again only after a pause.
        readAgainAfter = .now + Self.screenReturnDelay
        if !unavailable { trigger("screen state changed") }
    }

    private func handle(_ event: WindowEvent) {
        // TILE32's own writes come back as move and resize events (TA-12).
        if event == .moved || event == .resized, ContinuousClock.now - lastWrite < Self.echoWindow { return }
        trigger(event.rawValue)
    }

    private func handleWorkspace(_ name: NSNotification.Name, pid: pid_t?) {
        // The switch animation takes about half a second; read after it (found 2026-10-19).
        if name == NSWorkspace.activeSpaceDidChangeNotification { lastAnimation = .now }
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
            // Nothing while the screen is locked or asleep; look again every second until it is back.
            if screenUnavailable {
                readAgainAfter = now + Self.screenReturnDelay
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1))
                    self.scheduleCheck()
                }
                return
            }
            if now < readAgainAfter {
                scheduleCheck()
                return
            }
            // Let minimise and restore animations finish first.
            if now - lastAnimation < Self.settleTime {
                scheduleCheck()
                return
            }
            // Never while the user holds the mouse button or a drag or resize is still being
            // finished: a drag or resize is in progress.
            if NSEvent.pressedMouseButtons & 1 != 0 || now - lastGestureStep < Self.gestureTimeout {
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
            let summary = await engine.reconcile(observation, limits: limits(), excludedBundleIDs: excludedBundleIDs(),
                                                 acceptMidSwitch: midSwitchHolds >= Self.maximumMidSwitchHolds)
            if summary.heldMidSwitch {
                midSwitchHolds += 1
                Task { @MainActor in
                    try? await Task.sleep(for: Self.midSwitchRetryDelay)
                    trigger("read again after a desktop switch")
                }
                break
            }
            midSwitchHolds = 0
            lastObservation = observation
            if summary.changedAnything { lastWrite = .now }
            if summary.changedAnything || summary.layoutsChanged { await saveLayouts(observation) }
            if summary.minimised > 0 || summary.restored > 0 || summary.arrived > 0 { lastAnimation = .now }
            lastSummary = summary
            onChange()
        } while runAgain && state == .running
        await scheduleWriteRetry()
    }

    /// Looks again after `writeRetryDelay` when an app ignored a write. Bounded by
    /// `LayoutEngine.maximumWriteRetries`, so it never loops.
    private func scheduleWriteRetry() async {
        guard !writeRetryPending, await engine.needsWriteRetry else { return }
        writeRetryPending = true
        Task { @MainActor in
            try? await Task.sleep(for: Self.writeRetryDelay)
            writeRetryPending = false
            trigger("retry ignored write")
        }
    }

    /// Remembered layouts (US-26): saved after changes, offered once after a restart.
    public var layoutStore: StoredLayoutStore?

    public func restoreLayouts() async {
        guard let layoutStore else { return }
        await engine.importLayouts(layoutStore.load())
    }

    /// Forgets the remembered layouts, after "Untile" (US-24): the next start takes the
    /// windows as they are.
    public func forgetLayouts() async {
        await engine.forgetStoredLayouts()
        layoutStore?.save([:])
    }

    private func saveLayouts(_ observation: Observation) async {
        guard let layoutStore else { return }
        var all = layoutStore.load()
        for (key, value) in await engine.exportLayouts(observation) { all[key] = value }
        layoutStore.save(all)
        await engine.importLayouts(all)
    }

    /// One reading of the shown desktops: windows, Spaces, order of use, unanswered and
    /// hidden apps.
    public func observe() async -> Observation {
        let apps = apps()
        let table = displays()
        let scan = await WindowScan.run(apps: apps, displays: table, spaceService: spaceService)
        let unanswered = Set(scan.apps.filter(\.listingFailed).map(\.app.pid))
        let hidden = Set(NSWorkspace.shared.runningApplications.filter(\.isHidden).map(\.processIdentifier))
        let recency = WindowServerList.frontToBack().map { WindowID(UInt64($0)) }
        let pids = Set(apps.map(\.pid))
        let serverNumbers = WindowServerList.normalWindows().filter { pids.contains($0.ownerPID) }.map(\.number)
        var known: [WindowID: [SpaceID]] = [:]
        for (number, spaces) in spaceService.spaces(of: serverNumbers) { known[WindowID(UInt64(number))] = spaces }
        return Observation(records: Array(scan.registry.records.values), displays: table,
                           currentSpaces: spaceService.currentSpaces(on: table), recency: recency,
                           unansweredPIDs: unanswered, hiddenPIDs: hidden, knownSpaces: known)
    }

    private func apps() -> [AppInfo] {
        let all = AppInfo.runningRegularApps()
        guard let onlyBundleIDs else { return all }
        return all.filter { $0.bundleID.map(onlyBundleIDs.contains) ?? false }
    }

    // MARK: Drag-to-split (M2)

    /// What a release at `point` would do, for the overlay (US-16). Nil while paused.
    public func dragMoved(_ number: CGWindowID, at point: CGPoint) async -> DropPreview? {
        guard state == .running else {
            noteMissingPreview(number, "tiling is \(String(describing: state))")
            return nil
        }
        lastGestureStep = .now
        let table = displays()
        let spaces = spaceService.currentSpaces(on: table)
        let id = WindowID(UInt64(number))
        if let preview = await engine.dropPreview(for: id, at: point, displays: table, currentSpaces: spaces) {
            dragHadPreview = true
            return preview
        }
        noteMissingPreview(number, await engine.noDropPreviewReason(for: id, at: point, displays: table, currentSpaces: spaces))
        return nil
    }

    /// What the last drag showed, for the log: whether any zone appeared, and each new reason
    /// why none did. Logged at notice level so it is still there when the owner reports it.
    private var dragHadPreview = false
    private var lastMissingPreviewReason: String?

    private func noteMissingPreview(_ number: CGWindowID, _ reason: String) {
        guard reason != lastMissingPreviewReason else { return }
        lastMissingPreviewReason = reason
        Log.drag.notice("No drop zone for w\(number): \(reason, privacy: .public)")
    }

    /// Applies a drop, or puts the window back after Escape (US-14 to US-19). Runs under the
    /// same lock as reconcile, so the two never interleave.
    public func dragEnded(_ number: CGWindowID, at point: CGPoint, cancelled: Bool) async {
        defer {
            lastGestureStep = .now - .seconds(10)
            dragHadPreview = false
            lastMissingPreviewReason = nil
        }
        guard state == .running else { return }
        while running { try? await Task.sleep(for: .milliseconds(20)) }
        running = true
        defer { running = false }
        let id = WindowID(UInt64(number))
        var observation = lastObservation
        if observation?.records.contains(where: { $0.id == id }) != true {
            observation = await observe()
            lastObservation = observation
        }
        guard let observation else { return }
        let snapshots = Dictionary(observation.records.map { ($0.id, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
        let table = displays()
        let spaces = spaceService.currentSpaces(on: table)
        if cancelled {
            await engine.snapBack(id, displays: table, currentSpaces: spaces, snapshots: snapshots)
        } else {
            let outcome = await engine.drop(id, at: point, displays: table, currentSpaces: spaces, snapshots: snapshots)
            Log.drag.notice("Drop of w\(number): \(String(describing: outcome), privacy: .public), zone shown during the drag: \(self.dragHadPreview ? "yes" : "no", privacy: .public)")
        }
        lastWrite = .now
        await saveLayouts(observation)
        onChange()
        await scheduleWriteRetry()
    }

    /// A drag or resize ended without a release, for example by a desktop switch.
    public func gestureCancelled() {
        lastGestureStep = .now - .seconds(10)
        dragHadPreview = false
        lastMissingPreviewReason = nil
    }

    /// An edge resize moved or ended (US-28, TA-25). Returns the window's share for the label.
    public func resized(_ number: CGWindowID, to frame: CGRect, edges: Set<Edge>, final: Bool) async -> Double? {
        lastGestureStep = final ? .now - .seconds(10) : .now
        guard state == .running, let observation = lastObservation else { return nil }
        if final {
            while running { try? await Task.sleep(for: .milliseconds(20)) }
            running = true
        }
        defer { if final { running = false } }
        let snapshots = Dictionary(observation.records.map { ($0.id, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
        let table = displays()
        let share = await engine.resize(WindowID(UInt64(number)), to: frame, edges: edges, final: final, displays: table,
                                        currentSpaces: spaceService.currentSpaces(on: table), snapshots: snapshots)
        lastWrite = .now
        if final {
            await saveLayouts(observation)
            onChange()
            await scheduleWriteRetry()
        }
        return share
    }

    /// "Make sizes equal" (US-28.9).
    public func makeSizesEqual() async {
        guard state == .running else { return }
        while running { try? await Task.sleep(for: .milliseconds(20)) }
        running = true
        defer { running = false }
        let observation = await observe()
        lastObservation = observation
        let snapshots = Dictionary(observation.records.map { ($0.id, $0.snapshot) }, uniquingKeysWith: { first, _ in first })
        _ = await engine.equalizeShown(displays: observation.displays, currentSpaces: observation.currentSpaces, snapshots: snapshots)
        lastWrite = .now
        await saveLayouts(observation)
        onChange()
    }

    /// Shares of the display width for the Windows submenu (UX-6).
    public func widthShares() async -> [WindowID: Double] {
        let table = displays()
        return await engine.widthShares(displays: table, currentSpaces: spaceService.currentSpaces(on: table))
    }

    /// "Tile now" while running: arranges afresh and keeps tiling (US-4.6).
    public func tileNow() async -> ReconcileSummary {
        let observation = await observe()
        let summary = await engine.reconcile(observation, limits: limits(), excludedBundleIDs: excludedBundleIDs(), rebuild: true)
        lastWrite = .now
        lastObservation = observation
        await saveLayouts(observation)
        lastSummary = summary
        onChange()
        await scheduleWriteRetry()
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
        for observer in distributedObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        distributedObservers.removeAll()
    }
}
