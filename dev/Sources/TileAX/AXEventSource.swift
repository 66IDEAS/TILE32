// Accessibility observers per app (architecture TA-9). The callbacks run on the observer
// thread and only forward a small event; all decisions happen in the engine.
import ApplicationServices
import Foundation
import TileLog

public enum WindowEvent: String, Sendable {
    case created, focusChanged, moved, resized, minimised, restored

    init?(notification: String) {
        switch notification {
        case kAXWindowCreatedNotification: self = .created
        case kAXFocusedWindowChangedNotification: self = .focusChanged
        case kAXWindowMovedNotification: self = .moved
        case kAXWindowResizedNotification: self = .resized
        case kAXWindowMiniaturizedNotification: self = .minimised
        case kAXWindowDeminiaturizedNotification: self = .restored
        default: return nil
        }
    }
}

public final class AXEventSource: @unchecked Sendable {
    // @unchecked: `observers` is only touched on the observer thread (TA-13).

    /// Registered on each app's application element, so every window of the app reports.
    static let notifications = [
        kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXWindowMovedNotification,
        kAXWindowResizedNotification, kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification,
    ]

    private let onEvent: @Sendable (pid_t, WindowEvent) -> Void
    private let thread: AXObserverThread
    private var observers: [pid_t: (observer: AXObserver, context: Unmanaged<Context>)] = [:]

    /// Carried through the C callback as its context pointer.
    final class Context: @unchecked Sendable {
        let pid: pid_t
        let onEvent: @Sendable (pid_t, WindowEvent) -> Void
        init(pid: pid_t, onEvent: @escaping @Sendable (pid_t, WindowEvent) -> Void) {
            self.pid = pid
            self.onEvent = onEvent
        }
    }

    public init(thread: AXObserverThread = AXWorker.shared.observerThread,
                onEvent: @escaping @Sendable (pid_t, WindowEvent) -> Void) {
        self.thread = thread
        self.onEvent = onEvent
    }

    /// Starts observing an app. Safe to call again for an app already observed.
    public func watch(_ pid: pid_t) {
        thread.perform { [self] in
            guard observers[pid] == nil else { return }
            var created: AXObserver?
            let callback: AXObserverCallback = { _, _, notification, refcon in
                guard let refcon else { return }
                let context = Unmanaged<Context>.fromOpaque(refcon).takeUnretainedValue()
                if let event = WindowEvent(notification: notification as String) {
                    context.onEvent(context.pid, event)
                }
            }
            guard AXObserverCreate(pid, callback, &created) == .success, let observer = created else {
                Log.ax.info("No observer for pid \(pid)")
                return
            }
            let context = Unmanaged.passRetained(Context(pid: pid, onEvent: onEvent))
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, AXWorker.messagingTimeout)
            var added = 0
            for name in Self.notifications where AXObserverAddNotification(observer, app, name as CFString, context.toOpaque()) == .success {
                added += 1
            }
            CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = (observer, context)
            Log.ax.debug("Observing pid \(pid): \(added) of \(Self.notifications.count) notifications")
        }
    }

    /// Stops observing an app that quit.
    public func unwatch(_ pid: pid_t) {
        thread.perform { [self] in
            guard let entry = observers.removeValue(forKey: pid) else { return }
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
            entry.context.release()
        }
    }

    public func unwatchAll() {
        thread.perform { [self] in
            for (_, entry) in observers {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(entry.observer), .defaultMode)
                entry.context.release()
            }
            observers.removeAll()
        }
    }
}
