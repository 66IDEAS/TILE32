import Testing
@testable import TileCore

@Suite("Tree operations (TA-4)")
struct TreeOperationTests {
    // MARK: flat (L2)

    @Test func flatBuildsEqualColumns() {
        let tree = LayoutTree.flat([A, B, C])
        #expect(shape(tree) == "H(1,2,3)")
        #expect(approx(topWeights(tree), [third, third, third]))
        #expect(LayoutTree.flat([]).isEmpty)
        #expect(LayoutTree.flat([A]).root == leaf(A))
    }

    // MARK: appending (L3)

    @Test func appendingToEmptyAndToLeaf() {
        #expect(LayoutTree().appending(A).root == leaf(A))
        let two = LayoutTree(root: leaf(A)).appending(B)
        #expect(shape(two) == "H(1,2)")
        #expect(approx(topWeights(two), [0.5, 0.5]))
    }

    @Test func appendingToVerticalRootWrapsIt() {
        let tree = LayoutTree(root: split(.vertical, (leaf(A), 0.5), (leaf(B), 0.5))).appending(C)
        #expect(shape(tree) == "H(V(1,2),3)")
        #expect(approx(topWeights(tree), [0.5, 0.5]))
    }

    @Test func appendingShrinksColumnsInProportion() {
        // L3 example: 50, 25, 25 plus a new window gives 37.5, 18.75, 18.75, 25.
        let tree = LayoutTree(root: split(.horizontal, (leaf(A), 0.5), (leaf(B), 0.25), (leaf(C), 0.25))).appending(D)
        #expect(shape(tree) == "H(1,2,3,4)")
        #expect(approx(topWeights(tree), [0.375, 0.1875, 0.1875, 0.25]))
    }

    @Test func appendingAnExistingWindowDoesNothing() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.appending(A) == tree)
    }

    // MARK: removing (L4)

    @Test func removingGrowsNeighboursInProportion() {
        // L4 example: 50, 25, 25 and the 50 percent window closes gives 50, 50.
        let tree = LayoutTree(root: split(.horizontal, (leaf(A), 0.5), (leaf(B), 0.25), (leaf(C), 0.25))).removing(A)
        #expect(shape(tree) == "H(2,3)")
        #expect(approx(topWeights(tree), [0.5, 0.5]))
    }

    @Test func removingLastWindowEmptiesTheTree() {
        #expect(LayoutTree(root: leaf(A)).removing(A).isEmpty)
    }

    @Test func removingFromAColumnCollapsesIt() {
        let tree = LayoutTree(root: split(.horizontal, (split(.vertical, (leaf(A), 0.5), (leaf(D), 0.5)), 0.5), (leaf(B), 0.5)))
        let result = tree.removing(D)
        #expect(shape(result) == "H(1,2)")
        #expect(approx(topWeights(result), [0.5, 0.5]))
    }

    @Test func removingUnknownWindowDoesNothing() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.removing(E) == tree)
    }

    // MARK: Prototype scenarios (US-15.4, L5)

    @Test func prototypeScenarioDBelowA() {
        let tree = LayoutTree.flat([A, B, C]).appending(D).dropping(D, on: A, zone: .bottom)
        #expect(shape(tree) == "H(V(1,4),2,3)")
        #expect(approx(topWeights(tree), [third, third, third]))
        guard case .split(_, let children)? = tree.root else { Issue.record("not a split"); return }
        #expect(approx(weights(of: children[0].node), [0.5, 0.5]))
    }

    @Test func prototypeScenarioDRightOfBKeepsSizes() {
        // L5 example: D takes half of B's tile; flattening keeps every size.
        let tree = LayoutTree.flat([A, B, C]).appending(D).dropping(D, on: B, zone: .right)
        #expect(shape(tree) == "H(1,2,4,3)")
        #expect(approx(topWeights(tree), [third, sixth, sixth, third]))
    }

    @Test func leftAndTopPutTheDraggedWindowFirst() {
        let base = LayoutTree.flat([A, B, C])
        #expect(shape(base.dropping(C, on: A, zone: .left)) == "H(3,1,2)")
        #expect(shape(base.dropping(C, on: A, zone: .top)) == "H(V(3,1),2)")
        #expect(shape(base.dropping(C, on: A, zone: .bottom)) == "H(V(1,3),2)")
    }

    // MARK: swapping (L1, US-14)

    @Test func centreDropSwapsAndSizesStayWithTiles() {
        let tree = LayoutTree(root: split(.horizontal,
                                          (split(.vertical, (leaf(A), 0.5), (leaf(D), 0.5)), 0.5),
                                          (leaf(B), 0.25), (leaf(C), 0.25)))
        let swapped = tree.dropping(D, on: C, zone: .center)
        #expect(shape(swapped) == "H(V(1,3),2,4)")
        #expect(approx(topWeights(swapped), [0.5, 0.25, 0.25]))
    }

    @Test func swappingWithMissingWindowDoesNothing() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.swapping(A, E) == tree)
        #expect(tree.swapping(A, A) == tree)
    }

    // MARK: Edge cases

    @Test func droppingOnItselfDoesNothing() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.dropping(A, on: A, zone: .left) == tree)
    }

    @Test func droppingOnUnknownTargetDoesNothing() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.dropping(A, on: E, zone: .left) == tree)
    }

    @Test func oneWindowTree() {
        let tree = LayoutTree(root: leaf(A))
        #expect(tree.dropping(A, on: A, zone: .bottom) == tree)
        #expect(tree.swapping(A, B) == tree)
        #expect(tree.removing(A).isEmpty)
    }

    @Test func insertingAWindowFromAnotherTree() {
        // Cross-display or cross-Space drop, and the return hint after minimising:
        // the window is not in this tree yet.
        let tree = LayoutTree.flat([A, B]).splitting(target: A, with: E, zone: .left)
        #expect(shape(tree) == "H(5,1,2)")
        #expect(approx(topWeights(tree), [0.25, 0.25, 0.5]))
    }

    // MARK: equalized (US-28.9)

    @Test func equalizedResetsWeightsButKeepsStructure() {
        let tree = LayoutTree(root: split(.horizontal,
                                          (split(.vertical, (leaf(A), 0.3), (leaf(D), 0.7)), 0.5),
                                          (leaf(B), 0.3), (leaf(C), 0.2))).equalized()
        #expect(shape(tree) == "H(V(1,4),2,3)")
        #expect(approx(topWeights(tree), [third, third, third]))
        guard case .split(_, let children)? = tree.root else { Issue.record("not a split"); return }
        #expect(approx(weights(of: children[0].node), [0.5, 0.5]))
    }

    // MARK: Weight drift

    @Test func weightsStayValidThroughManyOperations() {
        var random = LCG(state: 32)
        var tree = LayoutTree()
        let zones = DropZone.allCases
        for step in 0..<2000 {
            let ids = tree.windowIDs
            switch random.next(5) {
            case 0, 1:
                tree = tree.appending(WindowID(UInt64(step + 10)))
            case 2 where ids.count > 1:
                tree = tree.removing(ids[random.next(ids.count)])
            case 3 where ids.count > 1:
                let a = ids[random.next(ids.count)], b = ids[random.next(ids.count)]
                tree = tree.dropping(a, on: b, zone: zones[random.next(zones.count)])
            case 4 where ids.count > 1:
                let id = ids[random.next(ids.count)]
                let edge = Edge.allCases[random.next(4)]
                tree = tree.resizing(window: id, edge: edge, to: CGFloat(random.next(5120)), in: ultrawide)
            default:
                break
            }
            #expect(weightsAreValid(tree.root), "invalid weights after step \(step)")
            #expect(Set(tree.windowIDs).count == tree.windowIDs.count, "duplicate window after step \(step)")
        }
    }
}

import CoreGraphics

@Suite("Replacing (L9)")
struct ReplacingTests {
    @Test func newWindowTakesTheTileAndItsSize() {
        let tree = LayoutTree(root: split(.horizontal, (split(.vertical, (leaf(A), 0.3), (leaf(D), 0.7)), 0.5),
                                          (leaf(B), 0.25), (leaf(C), 0.25)))
        let replaced = tree.replacing(D, with: E)
        #expect(shape(replaced) == "H(V(1,5),2,3)")
        #expect(approx(topWeights(replaced), [0.5, 0.25, 0.25]))
        guard case .split(_, let children)? = replaced.root else { Issue.record("not a split"); return }
        #expect(approx(weights(of: children[0].node), [0.3, 0.7]))
    }

    @Test func missingOldOrPresentNewChangesNothing() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.replacing(E, with: D) == tree)
        #expect(tree.replacing(A, with: B) == tree)
        #expect(tree.replacing(A, with: A) == tree)
    }
}

@Suite("Default arrangement (L2, D-8)")
struct ArrangedTests {
    private func ids(_ n: Int) -> [WindowID] { (1...n).map { WindowID(UInt64($0)) } }

    @Test func twelveWindowsOnTheDellBecomeTwoRowsOfSix() {
        let tree = LayoutTree.arranged(ids(12), availableWidth: 5108)
        #expect(shape(tree) == "H(V(1,7),V(2,8),V(3,9),V(4,10),V(5,11),V(6,12))")
        #expect(approx(topWeights(tree), Array(repeating: 1.0 / 6, count: 6)))
    }

    @Test func oddCountLeavesTheLastColumnFullHeight() {
        #expect(shape(LayoutTree.arranged(ids(11), availableWidth: 5108)) == "H(V(1,7),V(2,8),V(3,9),V(4,10),V(5,11),6)")
    }

    @Test func wideEnoughStaysColumns() {
        // 5 windows on the Dell: 1021 points each.
        #expect(shape(LayoutTree.arranged(ids(5), availableWidth: 5108)) == "H(1,2,3,4,5)")
        // 2 windows on the laptop: 858 points each.
        #expect(shape(LayoutTree.arranged(ids(2), availableWidth: 1716)) == "H(1,2)")
    }

    @Test func sixWindowsOnTheLaptopBecomeThreeColumnsInTwoRows() {
        #expect(shape(LayoutTree.arranged(ids(6), availableWidth: 1716)) == "H(V(1,4),V(2,5),V(3,6))")
    }

    @Test func singleAndNoWindow() {
        #expect(LayoutTree.arranged(ids(1), availableWidth: 100).root == leaf(A))
        #expect(LayoutTree.arranged([], availableWidth: 5108).isEmpty)
    }
}
