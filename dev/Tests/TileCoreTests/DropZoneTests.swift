import CoreGraphics
import Testing
@testable import TileCore

@Suite("Drop zones and drop targets (TA-6, L6)")
struct DropZoneTests {
    let tile = CGRect(x: 0, y: 0, width: 100, height: 100)

    @Test(arguments: [
        (27.9, DropZone.left), (28.0, .left), (28.1, .center),
        (71.9, .center), (72.0, .right), (72.1, .right),
    ])
    func horizontalBoundaries(x: Double, expected: DropZone) {
        #expect(dropZone(at: CGPoint(x: x, y: 50), in: tile) == expected)
    }

    @Test(arguments: [(27.9, DropZone.top), (28.1, .center), (71.9, .center), (72.1, .bottom)])
    func verticalBoundaries(y: Double, expected: DropZone) {
        #expect(dropZone(at: CGPoint(x: 50, y: y), in: tile) == expected)
    }

    @Test func cornerTiesResolveLeftRightTopBottom() {
        #expect(dropZone(at: CGPoint(x: 10, y: 10), in: tile) == .left)
        #expect(dropZone(at: CGPoint(x: 90, y: 10), in: tile) == .right)
        #expect(dropZone(at: CGPoint(x: 10, y: 90), in: tile) == .left)
        #expect(dropZone(at: CGPoint(x: 90, y: 90), in: tile) == .right)
    }

    @Test func zonesUseRelativePositionOnAVeryWideTile() {
        // On a full-width tile of the ultrawide, the centre zone is 2253 points wide.
        #expect(dropZone(at: CGPoint(x: 1440, y: 720), in: ultrawide) == .center)
        #expect(dropZone(at: CGPoint(x: 1400, y: 720), in: ultrawide) == .left)
        #expect(dropZone(at: CGPoint(x: 2560, y: 100), in: ultrawide) == .top)
    }

    @Test func dropTargetFindsTheWindowAndZone() {
        let tree = LayoutTree.flat([A, B, C, D])
        let target = tree.dropTarget(at: CGPoint(x: 640, y: 1400), in: ultrawide, excluding: D)
        #expect(target == .window(A, .bottom, tile: CGRect(x: 0, y: 0, width: 1280, height: 1440)))
    }

    @Test func ownTileAndOutsideAreNoTarget() {
        let tree = LayoutTree.flat([A, B])
        #expect(tree.dropTarget(at: CGPoint(x: 100, y: 100), in: ultrawide, excluding: A) == nil)
        #expect(tree.dropTarget(at: CGPoint(x: 6000, y: 100), in: ultrawide, excluding: A) == nil)
    }

    @Test func layoutWithoutOtherWindowsIsAnEmptyTarget() {
        #expect(LayoutTree().dropTarget(at: CGPoint(x: 10, y: 10), in: ultrawide, excluding: A) == .emptyLayout(ultrawide))
        #expect(LayoutTree(root: leaf(A)).dropTarget(at: CGPoint(x: 10, y: 10), in: ultrawide, excluding: A) == .emptyLayout(ultrawide))
    }

    @Test func previewRects() {
        #expect(previewRect(for: .window(A, .center, tile: tile)) == tile)
        #expect(previewRect(for: .window(A, .left, tile: tile)) == CGRect(x: 0, y: 0, width: 50, height: 100))
        #expect(previewRect(for: .window(A, .right, tile: tile)) == CGRect(x: 50, y: 0, width: 50, height: 100))
        #expect(previewRect(for: .window(A, .top, tile: tile)) == CGRect(x: 0, y: 0, width: 100, height: 50))
        #expect(previewRect(for: .window(A, .bottom, tile: tile)) == CGRect(x: 0, y: 50, width: 100, height: 50))
        #expect(previewRect(for: .emptyLayout(ultrawide)) == ultrawide)
    }
}
