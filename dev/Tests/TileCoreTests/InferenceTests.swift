import CoreGraphics
import Testing
@testable import TileCore

private let F = WindowID(6), G = WindowID(7), H = WindowID(8)
private let dell = CGRect(x: 0, y: 30, width: 5120, height: 1353)

@Suite("Reading a layout back from window frames (US-26)")
struct InferenceTests {
    private func roundTrip(_ tree: LayoutTree, file: String = #file, line: Int = #line) -> LayoutTree? {
        let frames = tree.frames(in: dell, gap: 6)
        guard let inferred = LayoutTree.inferred(from: frames, in: dell, gap: 6) else { return nil }
        #expect(inferred.frames(in: dell, gap: 6) == frames)
        return inferred
    }

    @Test func gridOfFourColumnsComesBackExactly() {
        let grid = LayoutTree.arranged([A, C, E, G, B, D, F, H], availableWidth: 5120)
        let inferred = roundTrip(grid)
        #expect(inferred.map(shape) == "H(V(1,2),V(3,4),V(5,6),V(7,8))")
    }

    @Test func unequalProportionsComeBack() {
        let tree = LayoutTree(root: split(.horizontal, (leaf(A), 0.5), (split(.vertical, (leaf(B), 0.3), (leaf(C), 0.7)), 0.25), (leaf(D), 0.25)))
        let inferred = roundTrip(tree)
        #expect(inferred.map(shape) == "H(1,V(2,3),4)")
        #expect(approx(inferred.map(topWeights) ?? [], [0.5, 0.25, 0.25], tolerance: 1e-3))
    }

    @Test func fullHeightColumnBesideAGrid() {
        let grid = LayoutTree.arranged([A, C, E, B, D, F], availableWidth: 5120).placing(G, atDisplayEdge: .right)
        #expect(roundTrip(grid).map(shape) == shape(grid))
    }

    @Test func stepSizedWindowsWithinTheToleranceStillCount() {
        var frames = LayoutTree.flat([A, B, C]).frames(in: dell, gap: 6)
        frames[B]!.size.width -= 3   // Terminal ends a character step short
        frames[B]!.size.height -= 5
        let inferred = LayoutTree.inferred(from: frames, in: dell, gap: 6)
        #expect(inferred.map(shape) == "H(1,2,3)")
    }

    @Test func overlappingWindowsAreNotATiling() {
        let frames: [WindowID: CGRect] = [
            A: CGRect(x: 100, y: 100, width: 1200, height: 800),
            B: CGRect(x: 600, y: 300, width: 1200, height: 800),
        ]
        #expect(LayoutTree.inferred(from: frames, in: dell, gap: 6) == nil)
    }

    @Test func pinwheelCannotBeCut() {
        // Four windows around a fifth: no straight cut runs through without crossing one.
        let frames: [WindowID: CGRect] = [
            A: CGRect(x: 0, y: 0, width: 600, height: 200),
            B: CGRect(x: 610, y: 0, width: 200, height: 600),
            C: CGRect(x: 210, y: 610, width: 600, height: 200),
            D: CGRect(x: 0, y: 210, width: 200, height: 600),
            E: CGRect(x: 210, y: 210, width: 390, height: 390),
        ]
        #expect(LayoutTree.inferred(from: frames, in: CGRect(x: 0, y: 0, width: 810, height: 810), gap: 0) == nil)
    }

    @Test func singleWindowIsALeaf() {
        #expect(LayoutTree.inferred(from: [A: CGRect(x: 300, y: 300, width: 500, height: 400)], in: dell, gap: 6)
            .map(shape) == "1")
        #expect(LayoutTree.inferred(from: [:], in: dell, gap: 6) == nil)
    }
}
