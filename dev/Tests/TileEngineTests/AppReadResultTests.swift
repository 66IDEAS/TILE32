import ApplicationServices
import Testing
@testable import TileAX

@Suite("Apps whose windows cannot be read keep their tiles (TA-13)")
struct AppReadResultTests {
    private func result(_ error: AXError) -> AppReadResult {
        AppReadResult(app: AppInfo(pid: 1, bundleID: "com.example", name: "Example"), windows: [], error: error, duration: .zero)
    }

    @Test func successAndNoWindowsAreReadings() {
        #expect(!result(.success).listingFailed)
        #expect(!result(.noValue).listingFailed)
    }

    @Test(arguments: [AXError.cannotComplete, .apiDisabled, .invalidUIElement, .failure])
    func everyErrorCountsAsUnanswered(error: AXError) {
        #expect(result(error).listingFailed)
    }
}
