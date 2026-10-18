import CoreGraphics
import Testing
@testable import TileAX

private func result(_ requested: CGRect, _ actual: CGRect?) -> FrameWriteResult {
    FrameWriteResult(requested: requested, actual: actual, positionError: .success, sizeError: .success, duration: .zero)
}

private let request = CGRect(x: 1094, y: 60, width: 897, height: 578)

@Suite("Frame write results (TA-11, US-10)")
struct FrameWriteResultTests {
    @Test func exactWriteMatchesAndFits() {
        let r = result(request, request)
        #expect(r.matches && r.fits && !r.doesNotFit)
    }

    @Test func terminalStepsFitButDoNotMatch() {
        // Session B: Terminal ended at 898 x 584 for a request of 897 x 578.
        let r = result(request, CGRect(x: 1094, y: 60, width: 898, height: 584))
        #expect(!r.matches)
        #expect(r.fits)
        #expect(!r.doesNotFit)
    }

    @Test func minimumSizeDoesNotFit() {
        let r = result(request, CGRect(x: 1094, y: 60, width: 1800, height: 1032))
        #expect(!r.fits)
        #expect(r.doesNotFit)
    }

    @Test func wrongPositionDoesNotFit() {
        let r = result(request, request.offsetBy(dx: 40, dy: 0))
        #expect(!r.fits && !r.doesNotFit)
        #expect(!result(request, nil).fits)
    }
}
