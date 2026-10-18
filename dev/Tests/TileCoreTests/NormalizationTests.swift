import Testing
@testable import TileCore

@Suite("Normalisation (L5)")
struct NormalizationTests {
    @Test func emptySplitBecomesNil() {
        #expect(LayoutNode.split(.horizontal, []).normalized() == nil)
    }

    @Test func singleChildSplitCollapses() {
        #expect(split(.horizontal, (leaf(A), 1)).normalized() == leaf(A))
    }

    @Test func sameDirectionFlattensAndKeepsSizes() {
        let node = split(.horizontal, (split(.horizontal, (leaf(A), 0.5), (leaf(B), 0.5)), 0.5), (leaf(C), 0.5))
        let result = node.normalized()!
        #expect(shape(result) == "H(1,2,3)")
        #expect(approx(weights(of: result), [0.25, 0.25, 0.5]))
    }

    @Test func otherDirectionIsKept() {
        let node = split(.horizontal, (split(.vertical, (leaf(A), 0.5), (leaf(D), 0.5)), 0.5), (leaf(B), 0.5))
        #expect(shape(node.normalized()!) == "H(V(1,4),2)")
    }

    @Test func collapsedChildFlattensIntoParent() {
        // V with a single child H(A,B) collapses to H(A,B), which then flattens into the outer H.
        let inner = split(.horizontal, (leaf(A), 0.5), (leaf(B), 0.5))
        let node = split(.horizontal, (split(.vertical, (inner, 1.0)), 0.6), (leaf(C), 0.4))
        let result = node.normalized()!
        #expect(shape(result) == "H(1,2,3)")
        #expect(approx(weights(of: result), [0.3, 0.3, 0.4]))
    }

    @Test func weightsAreRescaledToOne() {
        let result = split(.horizontal, (leaf(A), 2), (leaf(B), 6)).normalized()!
        #expect(approx(weights(of: result), [0.25, 0.75]))
    }

    @Test func invalidWeightsFallBackToEqualShares() {
        let result = split(.horizontal, (leaf(A), 0), (leaf(B), -1)).normalized()!
        #expect(approx(weights(of: result), [0.5, 0.5]))
        let notFinite = split(.vertical, (leaf(A), .nan), (leaf(B), 1)).normalized()!
        #expect(approx(weights(of: notFinite), [0.5, 0.5]))
    }

    @Test func leafIsUnchanged() {
        #expect(leaf(A).normalized() == leaf(A))
    }
}
