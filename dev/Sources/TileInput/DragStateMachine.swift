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
    /// How closely the window must follow the cursor to count as a move by the user.
    public static let lockstepTolerance: CGFloat = 6
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
            let lockstep = abs(windowDelta.x - cursorDelta.x) <= lockstepTolerance
                && abs(windowDelta.y - cursorDelta.y) <= lockstepTolerance
            if lockstep && press.inTitleBand {
                return (.dragging(press, cancelled: false), .startedDrag)
            }
            let reason = lockstep ? "outside the title band" : "not in lockstep with the cursor"
            return (.idle, .movedOtherwise(reason: reason))
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
