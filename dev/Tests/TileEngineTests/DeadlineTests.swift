import Foundation
import Testing
@testable import TileAX

@Suite("Reading deadline (TA-13)")
struct DeadlineTests {
    @Test func fastWorkWins() async {
        let value = await firstResult({ 42 }, orAfter: .seconds(2), fallback: 0)
        #expect(value == 42)
    }

    @Test func blockedWorkLosesToTheDeadline() async {
        let clock = ContinuousClock()
        let start = clock.now
        // Simulates an app that does not answer: the work blocks a thread for 3 seconds.
        let value = await firstResult({ blockThread(seconds: 3) }, orAfter: .milliseconds(200), fallback: -1)
        #expect(value == -1)
        #expect(clock.now - start < .seconds(1))
    }
}

/// Blocks the current thread like an app that does not answer.
private func blockThread(seconds: Double) -> Int {
    Thread.sleep(forTimeInterval: seconds)
    return 42
}
