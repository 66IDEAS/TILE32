import CoreGraphics
import Testing
@testable import TileCore

@Suite("Resizing by edge (L8, US-28)")
struct ResizingTests {
    @Test func ownerScenarioThirdsToFiftyTwentyFiveTwentyFive() {
        // US-28.6: drag A's right edge to the middle, then B's right edge to three quarters.
        let step1 = LayoutTree.flat([A, B, C]).resizing(window: A, edge: .right, to: 2560, in: ultrawide)
        #expect(approx(topWeights(step1), [0.5, sixth, third]))
        let step2 = step1.resizing(window: B, edge: .right, to: 3840, in: ultrawide)
        #expect(approx(topWeights(step2), [0.5, 0.25, 0.25]))
    }

    @Test func leftEdgeMovesTheBoundaryBeforeTheWindow() {
        let tree = LayoutTree.flat([A, B, C]).resizing(window: B, edge: .left, to: 1280, in: ultrawide)
        #expect(approx(topWeights(tree), [0.25, quarterPlusSixth, third], tolerance: 1e-9))
    }

    @Test func edgeInsideAColumnResizesTheWholeColumn() {
        let tree = LayoutTree.flat([A, B, C]).appending(D).dropping(D, on: A, zone: .bottom)
        let resized = tree.resizing(window: D, edge: .right, to: 2560, in: ultrawide)
        #expect(shape(resized) == "H(V(1,4),2,3)")
        #expect(approx(topWeights(resized), [0.5, sixth, third]))
    }

    @Test func verticalBoundaryInsideAColumn() {
        let tree = LayoutTree.flat([A, B]).dropping(D, on: A, zone: .bottom)
        let resized = tree.resizing(window: A, edge: .bottom, to: 500, in: ultrawide)
        guard case .split(_, let children)? = resized.root else { Issue.record("not a split"); return }
        #expect(approx(weights(of: children[0].node), [500.0 / 1440, 940.0 / 1440]))
    }

    @Test func outerEdgesChangeNothing() {
        let tree = LayoutTree.flat([A, B, C])
        #expect(tree.resizing(window: A, edge: .left, to: 300, in: ultrawide) == tree)
        #expect(tree.resizing(window: C, edge: .right, to: 4000, in: ultrawide) == tree)
        #expect(tree.resizing(window: B, edge: .top, to: 300, in: ultrawide) == tree)
    }

    @Test func minimumIsTenPercentOrTwoHundredPoints() {
        let tree = LayoutTree.flat([A, B, C])
        // 10 percent of 5120 is 512, more than 200 points.
        let narrow = tree.resizing(window: A, edge: .right, to: 10, in: ultrawide)
        #expect(approx(topWeights(narrow)[0], 0.1))
        // On a 1000 point wide display, 200 points wins over 10 percent.
        let small = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let clamped = LayoutTree.flat([A, B]).resizing(window: A, edge: .right, to: 950, in: small)
        #expect(approx(topWeights(clamped), [0.8, 0.2]))
    }

    @Test func pairTooSmallForTheMinimumIsLeftAlone() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 300)
        let tree = LayoutTree.flat([A, B])
        #expect(tree.resizing(window: A, edge: .right, to: 100, in: tiny) == tree)
    }

    @Test(arguments: [(0.49, 0.5), (0.51, 0.5), (0.515, 0.515), (0.335, third), (0.76, 0.75), (0.6, 0.6)])
    func snappingOnRelease(ratio: Double, expected: Double) {
        let position = CGFloat(ratio) * ultrawide.width
        let tree = LayoutTree.flat([A, B]).resizing(window: A, edge: .right, to: position, in: ultrawide, snap: true)
        #expect(approx(topWeights(tree)[0], expected, tolerance: 1e-9))
    }

    @Test func noSnappingWhileDragging() {
        let tree = LayoutTree.flat([A, B]).resizing(window: A, edge: .right, to: 0.49 * 5120, in: ultrawide)
        #expect(approx(topWeights(tree)[0], 0.49))
    }

    @Test func unknownWindowChangesNothing() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.resizing(window: E, edge: .right, to: 1000, in: ultrawide) == tree)
    }

    @Test func otherTilesKeepTheirSize() {
        let tree = LayoutTree(root: split(.horizontal, (leaf(A), 0.4), (leaf(B), 0.3), (leaf(C), 0.3)))
        let resized = tree.resizing(window: B, edge: .right, to: 0.8 * 5120, in: ultrawide)
        #expect(approx(topWeights(resized), [0.4, 0.4, 0.2]))
    }
}

private func approx(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
    abs(a - b) <= tolerance
}
