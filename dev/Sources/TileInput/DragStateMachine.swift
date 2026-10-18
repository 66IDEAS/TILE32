// The drag and resize state machine (architecture TA-14), kept free of AppKit so every
// transition can be unit tested. Coordinates are global with a top-left origin.
import CoreGraphics
import Foundation

public enum DragStateMachine {
    /// The title-bar band: title bars and unified toolbars (TA-14, OQ-4).
    public static let titleBand: CGFloat = 40
    /// macOS places resize edges just outside a window's frame.
    public static let edgeMargin: CGFloat = 6
    /// Cursor travel before a press counts as a drag attempt.
    public static let travelThreshold: CGFloat = 4
    /// How closely the window must follow the cursor to count as a move by the user: an
    /// absolute floor, plus a share of the cursor's travel, because during a fast drag the
    /// window trails the cursor by a frame or two (session C: Slack, Chrome).
    public static let lockstepTolerance: CGFloat = 12
    public static let lockstepShare: CGFloat = 0.35
    /// A window that moved in the cursor's direction but less than half as far is lagging:
    /// the machine waits for the next reading instead of deciding.
    public static let laggingRatio: CGFloat = 0.5
    /// Frame differences below this are noise.
    public static let frameTolerance: CGFloat = 2

    /// What was under the cursor when the button went down.
    public struct Press: Equatable, Sendable {
        public let window: CGWindowID
        public let pid: pid_t
        public let frame: CGRect
        public let point: CGPoint
        public let inTitleBand: Bool

        public init(window: CGWindowID, pid: pid_t, frame: CGRect, point: CGPoint) {
            self.window = window
            self.pid = pid
            self.frame = frame
            self.point = point
            inTitleBand = point.y >= frame.minY - DragStateMachine.edgeMargin
                && point.y <= frame.minY + DragStateMachine.titleBand
                && point.x >= frame.minX && point.x <= frame.maxX
        }
    }

    public enum State: Equatable, Sendable {
        case idle
        case pressed(Press)
        case dragging(Press, cancelled: Bool)
        case resizing(Press, edges: Set<Edge>)
    }

    public enum Edge: String, Sendable, CaseIterable, Comparable {
        case left, right, top, bottom
        public static func < (a: Edge, b: Edge) -> Bool { a.rawValue < b.rawValue }
    }

    /// What happened, for the log (spike S1) and later for the engine.
    public enum Outcome: Equatable, Sendable {
        case none
        case pressed
        case startedDrag
        case startedResize(Set<Edge>)
        case droppedDrag(at: CGPoint)
        case cancelledDrag
        case endedResize(Set<Edge>)
        case click
        /// The window moved, but not like a title-bar drag (not lockstep, or outside the band).
        case movedOtherwise(reason: String)
    }

    public enum Event: Sendable {
        /// Button down; `window` is the frontmost window under the cursor, if any.
        case press(Press?)
        /// The window's frame was read while the cursor had travelled `cursor - press.point`.
        case frameRead(CGRect, cursor: CGPoint)
        case escape
        case release(at: CGPoint)
        case reset
    }

    /// One transition. Pure: same state and event always give the same result.
    public static func next(_ state: State, _ event: Event) -> (State, Outcome) {
        switch (state, event) {
        case (_, .reset):
            return (.idle, .none)

        case (.idle, .press(let press?)):
            return (.pressed(press), .pressed)
        case (.idle, _):
            return (.idle, .none)

        case (.pressed(let press), .frameRead(let frame, let cursor)):
            let moved = changedEdges(from: press.frame, to: frame)
            if moved.isEmpty { return (state, .none) }
            if !sizeEqual(press.frame, frame) {
                return (.resizing(press, edges: moved), .startedResize(moved))
            }
            let windowDelta = CGPoint(x: frame.minX - press.frame.minX, y: frame.minY - press.frame.minY)
            let cursorDelta = CGPoint(x: cursor.x - press.point.x, y: cursor.y - press.point.y)
            switch follow(window: windowDelta, cursor: cursorDelta) {
            case .lockstep where press.inTitleBand:
                return (.dragging(press, cancelled: false), .startedDrag)
            case .lagging:
                return (state, .none)
            case .lockstep:
                return (.idle, .movedOtherwise(reason: "outside the title band"))
            case .unrelated:
                let detail = "window \(Int(windowDelta.x)),\(Int(windowDelta.y)) cursor \(Int(cursorDelta.x)),\(Int(cursorDelta.y))"
                return (.idle, .movedOtherwise(reason: "not in lockstep with the cursor (\(detail))"))
            }
        case (.pressed, .release):
            return (.idle, .click)
        case (.pressed, _):
            return (state, .none)

        case (.dragging(let press, _), .escape):
            return (.dragging(press, cancelled: true), .cancelledDrag)
        case (.dragging(_, let cancelled), .release(let point)):
            return (.idle, cancelled ? .none : .droppedDrag(at: point))
        case (.dragging, _):
            return (state, .none)

        case (.resizing(let press, let edges), .frameRead(let frame, _)):
            return (.resizing(press, edges: edges.union(changedEdges(from: press.frame, to: frame))), .none)
        case (.resizing(_, let edges), .release):
            return (.idle, .endedResize(edges))
        case (.resizing, _):
            return (state, .none)
        }
    }

    enum Follow: Equatable { case lockstep, lagging, unrelated }

    /// Whether a window's movement follows the cursor's movement since the press.
    static func follow(window: CGPoint, cursor: CGPoint) -> Follow {
        let cursorLength = hypot(cursor.x, cursor.y)
        let windowLength = hypot(window.x, window.y)
        let difference = hypot(window.x - cursor.x, window.y - cursor.y)
        if difference <= max(lockstepTolerance, lockstepShare * cursorLength) { return .lockstep }
        guard cursorLength > 0, windowLength > 0 else { return .unrelated }
        let cosine = (window.x * cursor.x + window.y * cursor.y) / (cursorLength * windowLength)
        guard cosine >= 0.8 else { return .unrelated }
        let ratio = windowLength / cursorLength
        if ratio < laggingRatio { return .lagging }
        // Session C re-test: in fast flicks windows trailed by 40 to 50 percent of the travel.
        return ratio <= 1.5 ? .lockstep : .unrelated
    }

    static func changedEdges(from a: CGRect, to b: CGRect) -> Set<Edge> {
        var edges: Set<Edge> = []
        if abs(a.minX - b.minX) > frameTolerance { edges.insert(.left) }
        if abs(a.maxX - b.maxX) > frameTolerance { edges.insert(.right) }
        if abs(a.minY - b.minY) > frameTolerance { edges.insert(.top) }
        if abs(a.maxY - b.maxY) > frameTolerance { edges.insert(.bottom) }
        return edges
    }

    static func sizeEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) <= frameTolerance && abs(a.height - b.height) <= frameTolerance
    }
}
