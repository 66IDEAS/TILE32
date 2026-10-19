import CoreGraphics
import Testing
@testable import TileCore

private let F = WindowID(6), G = WindowID(7), H = WindowID(8)

@Suite("Display edge drops (US-32)")
struct DisplayEdgeTests {
    /// The owner's desktop 2: four columns of two windows each.
    private let grid = LayoutTree.arranged([A, C, E, G, B, D, F, H], availableWidth: 5120)

    @Test func gridIsFourColumnsOfTwo() {
        #expect(shape(grid) == "H(V(1,2),V(3,4),V(5,6),V(7,8))")
    }

    @Test func rightEdgeMakesAFullHeightColumnWithAnEqualShare() {
        let placed = grid.placing(E, atDisplayEdge: .right)
        #expect(shape(placed) == "H(V(1,2),V(3,4),6,V(7,8),5)")
        #expect(approx(topWeights(placed), [0.2, 0.2, 0.2, 0.2, 0.2]))
    }

    @Test func leftEdgeAroundRowsWrapsTheLayout() {
        let rows = LayoutTree(root: split(.vertical, (split(.horizontal, (leaf(A), 0.5), (leaf(B), 0.5)), 0.5), (leaf(C), 0.5)))
        let placed = rows.placing(D, atDisplayEdge: .left)
        #expect(shape(placed) == "H(4,V(H(1,2),3))")
        #expect(approx(topWeights(placed), [0.5, 0.5]))
    }

    @Test func placingTheOnlyWindowKeepsItAlone() {
        #expect(shape(LayoutTree(root: leaf(A)).placing(A, atDisplayEdge: .right)) == "1")
        #expect(shape(LayoutTree().placing(A, atDisplayEdge: .left)) == "1")
    }

    @Test func pointInTheRightBandIsADisplayEdgeTarget() {
        let target = grid.dropTarget(at: CGPoint(x: 5100, y: 700), in: ultrawide, excluding: E)
        guard case .displayEdge(let edge, let area)? = target else { Issue.record("no edge target"); return }
        #expect(edge == .right)
        #expect(abs(area.width - 1024) < 1e-6)
        #expect(area.maxX == ultrawide.maxX && area.height == ultrawide.height)
        #expect(previewRect(for: target!) == area)
    }

    @Test func bandBoundaries() {
        let band = DisplayEdgeGeometry.band
        if case .displayEdge(.left, _)? = grid.dropTarget(at: CGPoint(x: band - 1, y: 700), in: ultrawide, excluding: E) {} else {
            Issue.record("left band missed")
        }
        if case .window? = grid.dropTarget(at: CGPoint(x: band + 1, y: 700), in: ultrawide, excluding: E) {} else {
            Issue.record("window zone expected just inside the band")
        }
        // No band at the top: the title-bar height belongs to the windows.
        if case .window? = grid.dropTarget(at: CGPoint(x: 2000, y: 10), in: ultrawide, excluding: E) {} else {
            Issue.record("window zone expected at the top")
        }
    }
}
