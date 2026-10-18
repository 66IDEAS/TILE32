// Watches the mouse with listen-only global monitors and feeds the drag state machine
// (architecture TA-14). In task T-0.21 it only logs, for spike S1; it changes nothing.
//
// Spike approach: the window under the cursor and its frame come from the window server's
// public list, which knows the front-to-back order and answers in milliseconds. Whether the
// window would be tiled is looked up afterwards, only for the log.
import AppKit
import TileGeometry
import TileLog
import TileSpaces

@MainActor
public final class MouseDragTracker {
    private var state = DragStateMachine.State.idle
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private let displays: @MainActor () -> DisplayTable
    private let describe: @MainActor (CGWindowID, pid_t) async -> String
    private var lastRead = ContinuousClock.now
    private var drags = 0

    /// Reads per second while the button is held.
    private static let readInterval: Duration = .milliseconds(33)

    /// `describe` returns how TILE32 would classify the window, for the log only.
    public init(displays: @escaping @MainActor () -> DisplayTable,
                describe: @escaping @MainActor (CGWindowID, pid_t) async -> String) {
        self.displays = displays
        self.describe = describe
    }

    public var isRunning: Bool { mouseMonitor != nil }

    public func start() {
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event.type) }
        }
        // Escape only, and only acted on while dragging (US-17.1, OQ-1).
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            let isEscape = event.keyCode == 53
            MainActor.assumeIsolated {
                guard isEscape, let self, case .dragging = self.state else { return }
                Log.drag.info("S1 Escape seen during a drag")
                self.apply(.escape)
            }
        }
        // A desktop switch while the button is down ends the gesture without a drop: the user is
        // carrying the window to another desktop, which US-29 handles (session A, TA-14).
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state != .idle else { return }
                Log.drag.info("S1 gesture ended by a desktop switch")
                self.apply(.reset)
            }
        }
        Log.drag.info("S1 drag logging started (keyboard monitor \(self.keyMonitor == nil ? "unavailable" : "installed", privacy: .public))")
    }

    public func stop() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        mouseMonitor = nil
        keyMonitor = nil
        spaceObserver = nil
        apply(.reset)
        Log.drag.info("S1 drag logging stopped")
    }

    private func cursor() -> CGPoint {
        displays().axPoint(fromAppKit: NSEvent.mouseLocation)
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            let point = cursor()
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let press = WindowServerList.window(at: point, margin: DragStateMachine.edgeMargin, excludingPID: ownPID).map { window in
                DragStateMachine.Press(window: window.number, pid: window.ownerPID, frame: window.bounds, point: point)
            }
            apply(.press(press))
        case .leftMouseDragged:
            let number: CGWindowID
            switch state {
            case .pressed(let press), .dragging(let press, _), .resizing(let press, _): number = press.window
            case .idle: return
            }
            let now = ContinuousClock.now
            guard now - lastRead >= Self.readInterval else { return }
            lastRead = now
            let point = cursor()
            if case .pressed(let press) = state,
               hypot(point.x - press.point.x, point.y - press.point.y) < DragStateMachine.travelThreshold {
                return
            }
            if let window = WindowServerList.window(number: number) {
                apply(.frameRead(window.bounds, cursor: point))
            }
        case .leftMouseUp:
            let point = cursor()
            // One last reading, so a quick drag between two mouse events is not missed.
            if case .pressed(let press) = state, let window = WindowServerList.window(number: press.window) {
                apply(.frameRead(window.bounds, cursor: point))
            }
            apply(.release(at: point))
        default:
            break
        }
    }

    private func apply(_ event: DragStateMachine.Event) {
        let previous = state
        let (next, outcome) = DragStateMachine.next(state, event)
        state = next
        log(outcome, previous: previous)
    }

    private func log(_ outcome: DragStateMachine.Outcome, previous: DragStateMachine.State) {
        let press: DragStateMachine.Press? = switch previous {
        case .pressed(let p), .dragging(let p, _), .resizing(let p, _): p
        case .idle: if case .pressed(let p) = state { p } else { nil }
        }
        guard let press else { return }
        let text: String
        switch outcome {
        case .none: return
        case .pressed: text = "pressed \(press.inTitleBand ? "in title band" : "below title band")"
        case .startedDrag: text = "drag started"
        case .startedResize(let edges): text = "resize started: \(edges.sorted().map(\.rawValue).joined(separator: "+"))"
        case .droppedDrag(let point): drags += 1; text = "drag dropped at \(Int(point.x)),\(Int(point.y)) (drag \(drags))"
        case .cancelledDrag: text = "drag cancelled with Escape"
        case .endedResize(let edges): text = "resize ended: \(edges.sorted().map(\.rawValue).joined(separator: "+"))"
        case .click: text = "click (window did not move)"
        case .movedOtherwise(let reason): text = "window moved, not a drag: \(reason)"
        }
        let describe = self.describe
        Task {
            let info = await describe(press.window, press.pid)
            Log.drag.info("S1 w\(press.window) \(info, privacy: .public): \(text, privacy: .public)")
        }
    }
}
