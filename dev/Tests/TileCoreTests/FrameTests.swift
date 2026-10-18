import CoreGraphics
import Testing
@testable import TileCore

@Suite("Frames, gaps and rounding (TA-5, L7)")
struct FrameTests {
    let gap: CGFloat = 6

    @Test func thirdsOnTheUltrawide() {
        let frames = LayoutTree.flat([A, B, C]).frames(in: ultrawide, gap: gap)
        #expect(frames[A] == CGRect(x: 6, y: 6, width: 1699, height: 1428))
        #expect(frames[B] == CGRect(x: 1711, y: 6, width: 1698, height: 1428))
        #expect(frames[C] == CGRect(x: 3415, y: 6, width: 1699, height: 1428))
    }

    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 5120, height: 1440),
        CGRect(x: 0, y: 0, width: 1440, height: 5120),
        CGRect(x: 3456, y: 0, width: 1728, height: 1079),
        CGRect(x: 0, y: 25, width: 1001, height: 777),
    ])
    func gapsAreEvenAndNothingOverlaps(rect: CGRect) {
        let tree = LayoutTree(root: split(.horizontal,
                                          (split(.vertical, (leaf(A), 0.37), (leaf(D), 0.63)), 0.5),
                                          (leaf(B), 0.21), (leaf(C), 0.29)))
        let frames = tree.frames(in: rect, gap: gap)
        #expect(frames.count == 4)

        for frame in frames.values {
            #expect(frame.minX == frame.minX.rounded() && frame.maxX == frame.maxX.rounded())
            #expect(frame.minY == frame.minY.rounded() && frame.maxY == frame.maxY.rounded())
            #expect(frame.minX >= rect.minX + gap - 1 && frame.maxX <= rect.maxX - gap + 1)
            #expect(frame.minY >= rect.minY + gap - 1 && frame.maxY <= rect.maxY - gap + 1)
        }
        let all = Array(frames.values)
        for i in all.indices {
            for j in all.indices where i < j {
                #expect(!all[i].intersects(all[j]), "tiles overlap")
            }
        }
        // Neighbours side by side are exactly one gap apart.
        #expect(frames[B]!.minX - frames[A]!.maxX == gap)
        #expect(frames[C]!.minX - frames[B]!.maxX == gap)
        #expect(frames[D]!.minY - frames[A]!.maxY == gap)
    }

    @Test func singleWindowFillsTheRectMinusTheGap() {
        let frames = LayoutTree(root: leaf(A)).frames(in: ultrawide, gap: gap)
        #expect(frames[A] == CGRect(x: 6, y: 6, width: 5108, height: 1428))
    }

    @Test func emptyTreeHasNoFrames() {
        #expect(LayoutTree().frames(in: ultrawide, gap: gap).isEmpty)
    }

    @Test func rawSharesFollowWeightsExactly() {
        let tree = LayoutTree(root: split(.horizontal, (leaf(A), 0.5), (leaf(B), 0.25), (leaf(C), 0.25)))
        let shares = tree.rawShares(in: ultrawide)
        #expect(shares[A] == CGRect(x: 0, y: 0, width: 2560, height: 1440))
        #expect(shares[B] == CGRect(x: 2560, y: 0, width: 1280, height: 1440))
        #expect(shares[C] == CGRect(x: 3840, y: 0, width: 1280, height: 1440))
    }
}
