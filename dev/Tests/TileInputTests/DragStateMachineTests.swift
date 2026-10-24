import CoreGraphics
import Testing
@testable import TileInput

private typealias M = DragStateMachine
private let frame = CGRect(x: 1000, y: 100, width: 800, height: 600)

private func press(at point: CGPoint) -> M.Press {
    M.Press(window: 42, pid: 7, frame: frame, point: point)
}

/// Runs a list of events from idle and returns the final state and every outcome.
private func run(_ events: [M.Event]) -> (M.State, [M.Outcome]) {
    var state = M.State.idle
    var outcomes: [M.Outcome] = []
    for event in events {
        let (next, outcome) = M.next(state, event)
        state = next
        if outcome != .none { outcomes.append(outcome) }
    }
    return (state, outcomes)
}

@Suite("Drag state machine (TA-14)")
struct DragStateMachineTests {
    @Test func titleBandCoversTheTopFortyPoints() {
        #expect(press(at: CGPoint(x: 1200, y: 110)).inTitleBand)
        #expect(press(at: CGPoint(x: 1200, y: 140)).inTitleBand)
        #expect(!press(at: CGPoint(x: 1200, y: 141)).inTitleBand)
        #expect(!press(at: CGPoint(x: 900, y: 110)).inTitleBand)
    }

    @Test func titleBarDragInLockstep() {
        let start = CGPoint(x: 1200, y: 110)
        let (state, outcomes) = run([
            .press(press(at: start)),
            .frameRead(frame.offsetBy(dx: 300, dy: 50), cursor: CGPoint(x: 1502, y: 159)),
            .release(at: CGPoint(x: 1600, y: 200)),
        ])
        #expect(state == .idle)
        #expect(outcomes == [.pressed, .startedDrag, .droppedDrag(at: CGPoint(x: 1600, y: 200))])
    }

    @Test func clickWithoutMovementIsAClick() {
        let (_, outcomes) = run([.press(press(at: CGPoint(x: 1200, y: 110))), .release(at: CGPoint(x: 1200, y: 110))])
        #expect(outcomes == [.pressed, .click])
    }

    @Test func contentDragLeavesTheWindowInPlace() {
        let (_, outcomes) = run([
            .press(press(at: CGPoint(x: 1300, y: 400))),
            .frameRead(frame, cursor: CGPoint(x: 1500, y: 450)),
            .release(at: CGPoint(x: 1500, y: 450)),
        ])
        #expect(outcomes == [.pressed, .click])
    }

    @Test func rightEdgeResize() {
        let (state, outcomes) = run([
            .press(press(at: CGPoint(x: 1801, y: 400))),
            .frameRead(CGRect(x: 1000, y: 100, width: 950, height: 600), cursor: CGPoint(x: 1951, y: 400)),
            .release(at: CGPoint(x: 1951, y: 400)),
        ])
        #expect(state == .idle)
        #expect(outcomes == [.pressed, .startedResize([.right]), .endedResize([.right])])
    }

    @Test func cornerResizeCollectsBothEdges() {
        let (_, outcomes) = run([
            .press(press(at: CGPoint(x: 1801, y: 701))),
            .frameRead(CGRect(x: 1000, y: 100, width: 900, height: 600), cursor: CGPoint(x: 1901, y: 701)),
            .frameRead(CGRect(x: 1000, y: 100, width: 900, height: 700), cursor: CGPoint(x: 1901, y: 801)),
            .release(at: CGPoint(x: 1901, y: 801)),
        ])
        #expect(outcomes == [.pressed, .startedResize([.right]), .endedResize([.right, .bottom])])
    }

    @Test func moveNotInLockstepIsNotADrag() {
        // The app moved its own window while the button was down elsewhere.
        let (state, outcomes) = run([
            .press(press(at: CGPoint(x: 1200, y: 110))),
            .frameRead(frame.offsetBy(dx: 300, dy: 0), cursor: CGPoint(x: 1210, y: 110)),
        ])
        #expect(state == .idle)
        #expect(outcomes == [.pressed, .movedOtherwise(reason: "not in lockstep with the cursor (window 300,0 cursor 10,0)")])
    }

    @Test func lockstepMoveBelowTheBandIsADragToo() {
        // For example a Finder window with tabs, grabbed in the tab bar below the 40 point band (OQ-4).
        let (state, outcomes) = run([
            .press(press(at: CGPoint(x: 1200, y: 160))),
            .frameRead(frame.offsetBy(dx: 100, dy: 0), cursor: CGPoint(x: 1300, y: 160)),
        ])
        #expect(outcomes == [.pressed, .startedDrag])
        if case .dragging = state {} else { Issue.record("expected a drag") }
    }

    @Test func escapeCancelsAndReleaseDoesNotDrop() {
        let start = CGPoint(x: 1200, y: 110)
        let (state, outcomes) = run([
            .press(press(at: start)),
            .frameRead(frame.offsetBy(dx: 50, dy: 0), cursor: CGPoint(x: 1250, y: 110)),
            .escape,
            .release(at: CGPoint(x: 1400, y: 110)),
        ])
        #expect(state == .idle)
        #expect(outcomes == [.pressed, .startedDrag, .cancelledDrag])
    }

    @Test func pressOnNothingStaysIdle() {
        let (state, outcomes) = run([.press(nil), .release(at: .zero)])
        #expect(state == .idle)
        #expect(outcomes.isEmpty)
    }

    @Test func resetAlwaysReturnsToIdle() {
        let (state, _) = run([.press(press(at: CGPoint(x: 1200, y: 110))), .reset])
        #expect(state == .idle)
    }

    @Test func fastDragWithTheWindowTrailingStillCounts() {
        // Session C: during a fast drag the window trails the cursor by a frame or two.
        let (_, outcomes) = run([
            .press(press(at: CGPoint(x: 1200, y: 110))),
            .frameRead(frame.offsetBy(dx: 260, dy: 30), cursor: CGPoint(x: 1500, y: 150)),
        ])
        #expect(outcomes == [.pressed, .startedDrag])
    }

    @Test func laggingWindowWaitsForTheNextReading() {
        // An Electron window that has only just started to follow.
        let (state, outcomes) = run([
            .press(press(at: CGPoint(x: 1200, y: 110))),
            .frameRead(frame.offsetBy(dx: 40, dy: 0), cursor: CGPoint(x: 1400, y: 110)),
            .frameRead(frame.offsetBy(dx: 390, dy: 0), cursor: CGPoint(x: 1600, y: 110)),
        ])
        #expect(outcomes == [.pressed, .startedDrag])
        if case .dragging = state {} else { Issue.record("expected dragging") }
    }

    @Test func windowMovingTheOtherWayIsNotADrag() {
        let (state, outcomes) = run([
            .press(press(at: CGPoint(x: 1200, y: 110))),
            .frameRead(frame.offsetBy(dx: -200, dy: 0), cursor: CGPoint(x: 1400, y: 110)),
        ])
        #expect(state == .idle)
        #expect(outcomes == [.pressed, .movedOtherwise(reason: "not in lockstep with the cursor (window -200,0 cursor 200,0)")])
    }

    @Test(arguments: [
        (CGPoint(x: -260, y: 0), CGPoint(x: -515, y: 0)),
        (CGPoint(x: 16, y: 245), CGPoint(x: 33, y: 391)),
        (CGPoint(x: -597, y: -11), CGPoint(x: -990, y: -10)),
    ])
    func fastFlicksFromTheReTestCount(window: CGPoint, cursor: CGPoint) {
        // The three misses of the session C re-test (Slack twice, Chrome once).
        #expect(DragStateMachine.follow(window: window, cursor: cursor) == .lockstep)
    }

    @Test func appMovingItsWindowWhileTheCursorBarelyMovesIsUnrelated() {
        #expect(DragStateMachine.follow(window: CGPoint(x: 400, y: 0), cursor: CGPoint(x: 20, y: 0)) == .unrelated)
    }
}
