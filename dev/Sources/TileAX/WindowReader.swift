// Discovers apps and reads their windows (architecture TA-9, TA-10 inputs).
import AppKit
import ApplicationServices
import CoreGraphics
import TileLog

/// A running app as far as TILE32 cares (TA-9: regular apps only).
public struct AppInfo: Sendable, Hashable {
    public let pid: pid_t
    public let bundleID: String?
    public let name: String

    public init(pid: pid_t, bundleID: String?, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }

    /// Every app with a Dock icon (activation policy regular), except TILE32 itself.
    @MainActor
    public static func runningRegularApps() -> [AppInfo] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier > 0 && $0.processIdentifier != ownPID && !$0.isTerminated }
            .map { AppInfo(pid: $0.processIdentifier, bundleID: $0.bundleIdentifier, name: $0.localizedName ?? "?") }
    }
}

/// Everything TILE32 reads about one window at one moment. Frames are in Accessibility
/// coordinates (top-left origin).
public struct WindowSnapshot: Sendable {
    public let app: AppInfo
    public let element: AXElementBox
    /// The window server's number for the window (TA-20), when it could be read.
    public let windowNumber: CGWindowID?
    public let role: String?
    public let subrole: String?
    public let title: String
    public let frame: CGRect?
    public let isMinimized: Bool
    public let isFullScreen: Bool
    public let isModal: Bool
    public let isResizable: Bool
    /// The window's Accessibility identifier, for example "save-panel" (T-3.1).
    public var identifier: String? = nil
}

/// The result of reading one app, including how long it took and whether it answered.
public struct AppReadResult: Sendable {
    public let app: AppInfo
    public let windows: [WindowSnapshot]
    public let error: AXError
    public let duration: Duration
}

public enum WindowReader {
    /// Reads the windows of every given app, in parallel across apps and in order within
    /// one app. `windowNumber` turns an element into its window number (TA-20, TA-26).
    public static func readAll(
        _ apps: [AppInfo],
        windowNumber: @escaping @Sendable (AXUIElement) -> CGWindowID?
    ) async -> [AppReadResult] {
        await withTaskGroup(of: AppReadResult.self) { group in
            for app in apps {
                group.addTask {
                    await firstResult(
                        { await AXWorker.shared.run(for: app.pid) { read(app, windowNumber: windowNumber) } },
                        orAfter: appDeadline,
                        fallback: AppReadResult(app: app, windows: [], error: .cannotComplete, duration: appDeadline)
                    )
                }
            }
            var results: [AppReadResult] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        }
    }

    /// A reading never waits longer than this for one app. The app's own queue stays busy
    /// until the app answers, but nothing else waits for it (TA-13).
    public static let appDeadline: Duration = .milliseconds(1500)

    /// Blocking; runs on the app's queue.
    static func read(_ app: AppInfo, windowNumber: (AXUIElement) -> CGWindowID?) -> AppReadResult {
        let clock = ContinuousClock()
        let start = clock.now
        let appElement = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(appElement, AXWorker.messagingTimeout)

        let (error, elements) = AXRead.elements(appElement, kAXWindowsAttribute)
        let windows = elements.map { element in
            // Window elements do not reliably inherit the timeout of the application element
            // (found in T-0.16: a hung app blocked a reading for 8 seconds), so set it on each.
            AXUIElementSetMessagingTimeout(element, AXWorker.messagingTimeout)
            let position = AXRead.point(element, kAXPositionAttribute)
            let size = AXRead.size(element, kAXSizeAttribute)
            return WindowSnapshot(
                app: app,
                element: AXElementBox(element),
                windowNumber: windowNumber(element),
                role: AXRead.string(element, kAXRoleAttribute),
                subrole: AXRead.string(element, kAXSubroleAttribute),
                title: AXRead.string(element, kAXTitleAttribute) ?? "",
                frame: position.flatMap { origin in size.map { CGRect(origin: origin, size: $0) } },
                isMinimized: AXRead.bool(element, kAXMinimizedAttribute) ?? false,
                isFullScreen: AXRead.bool(element, "AXFullScreen") ?? false,
                isModal: AXRead.bool(element, kAXModalAttribute) ?? false,
                isResizable: AXRead.isSettable(element, kAXSizeAttribute),
                identifier: AXRead.string(element, kAXIdentifierAttribute)
            )
        }
        let duration = clock.now - start
        if error != .success && error != .noValue {
            Log.ax.info("\(app.name, privacy: .public) (pid \(app.pid)) did not list its windows: AXError \(error.rawValue)")
        }
        return AppReadResult(app: app, windows: windows, error: error, duration: duration)
    }
}

/// Returns the work's result, or the fallback if the deadline passes first. The work keeps
/// running in the background and its late result is dropped. Unstructured tasks are used on
/// purpose: a task group would wait for the blocked work before returning.
func firstResult<T: Sendable>(
    _ work: @escaping @Sendable () async -> T,
    orAfter deadline: Duration,
    fallback: T
) async -> T {
    await withCheckedContinuation { continuation in
        let once = ResumeOnce(continuation)
        Task.detached { once.resume(with: await work()) }
        Task.detached {
            try? await Task.sleep(for: deadline)
            once.resume(with: fallback)
        }
    }
}

/// Resumes a continuation exactly once, whichever side arrives first.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    // @unchecked: the continuation is only touched under the lock.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Never>?

    init(_ continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(with value: T) {
        let pending: CheckedContinuation<T, Never>? = lock.withLock {
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
    }
}
