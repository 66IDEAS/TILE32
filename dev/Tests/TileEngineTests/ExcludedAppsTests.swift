import Foundation
import Testing
@testable import TileEngine

@Suite("Excluded apps (US-22)")
struct ExcludedAppsTests {
    private func store() -> (ExcludedAppsStore, String) {
        let suite = "com.66ideas.tile32.tests.\(UInt64.random(in: 0...UInt64.max))"
        return (ExcludedAppsStore(suiteName: suite), suite)
    }

    @Test func toggleAddsAndRemovesAndTheListSurvivesARestart() {
        let (store, suite) = store()
        store.toggle(ExcludedApp(bundleID: "us.zoom.xos", name: "zoom.us"))
        store.toggle(ExcludedApp(bundleID: "com.apple.systempreferences", name: "System Settings"))
        #expect(ExcludedAppsStore(suiteName: suite).load().map(\.name) == ["zoom.us", "System Settings"])
        store.toggle(ExcludedApp(bundleID: "us.zoom.xos", name: "zoom.us"))
        #expect(store.load().map(\.bundleID) == ["com.apple.systempreferences"])
        store.remove("com.apple.systempreferences")
        #expect(store.load().isEmpty)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}
