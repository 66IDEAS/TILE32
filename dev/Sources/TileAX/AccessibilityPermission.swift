// The Accessibility permission and its lifecycle (architecture TA-8, US-2, US-27).
import AppKit
import ApplicationServices
import TileLog

public enum AccessibilityPermission {
    /// Whether TILE32 may control other apps' windows. Never shows a system prompt.
    public static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Asks macOS for the permission. This adds TILE32 to the Accessibility list in System
    /// Settings and shows the system's own dialog, which cannot be skipped without losing
    /// the automatic listing (TA-8). Returns whether the permission is already granted.
    @discardableResult
    public static func request() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens Privacy & Security > Accessibility in System Settings.
    @MainActor
    public static func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Reports changes of the permission without a restart (US-2.3, US-27.4). Polls every
/// 2 seconds; the distributed notification only makes reactions faster, nothing depends on it.
@MainActor
public final class PermissionMonitor {
    public private(set) var isGranted: Bool
    private let onChange: @MainActor (Bool) -> Void
    private var timer: Timer?
    private var observer: NSObjectProtocol?

    public init(onChange: @escaping @MainActor (Bool) -> Void) {
        self.onChange = onChange
        isGranted = AccessibilityPermission.isGranted
        Log.engine.info("Accessibility permission at start: \(self.isGranted ? "granted" : "missing", privacy: .public)")

        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // Common modes keep polling while an alert or a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // The system updates the trust state shortly after posting the notification.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated { self?.check() }
            }
        }
    }

    isolated deinit {
        timer?.invalidate()
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
    }

    public func check() {
        let granted = AccessibilityPermission.isGranted
        guard granted != isGranted else { return }
        isGranted = granted
        Log.engine.info("Accessibility permission changed: \(granted ? "granted" : "missing", privacy: .public)")
        onChange(granted)
    }
}
