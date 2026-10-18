// One full reading of all windows, used by "Dump layout trees" until the engine's own
// discovery exists (task T-1.2). Logs per app timings for spike S3.
import CoreGraphics
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileLog
import TileSpaces

public enum WindowScan {
    public struct Result: Sendable {
        public let registry: WindowRegistry
        public let apps: [AppReadResult]
        public let duration: Duration
    }

    public static func run(apps: [AppInfo], displays: DisplayTable, spaceService: SpaceService) async -> Result {
        let clock = ContinuousClock()
        let start = clock.now
        let results = await WindowReader.readAll(apps) { spaceService.windowNumber(of: $0) }
        let snapshots = results.flatMap(\.windows)
        let spaces = spaceService.spaces(of: snapshots.compactMap(\.windowNumber))

        var registry = WindowRegistry()
        registry.update(with: snapshots, displays: displays, spaces: spaces)
        return Result(registry: registry, apps: results, duration: clock.now - start)
    }

    /// Writes the reading to the log: one line per app, one line per window.
    public static func log(_ result: Result, displays: DisplayTable) {
        Log.layout.info("Window scan: \(result.registry.records.count) windows in \(result.apps.count) apps, \(result.duration.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        let classes = result.registry.records.values.map { WindowClassifier.classify($0.snapshot) }
        let tiled = classes.filter { $0 == .tiled }.count
        let minimised = classes.filter { $0 == .minimised }.count
        let reasons = FloatReason.allCases.map { reason in "\(reason.rawValue) \(classes.filter { $0 == .floating(reason) }.count)" }
        Log.layout.info("Classification: \(tiled) tiled, \(minimised) minimised, floating: \(reasons.joined(separator: ", "), privacy: .public)")
        for app in result.apps {
            Log.ax.info("""
                App \(app.app.name, privacy: .public) pid \(app.app.pid): \(app.windows.count) windows, \
                AXError \(app.error.rawValue), \(app.duration.formatted(.units(allowed: [.milliseconds])), privacy: .public)
                """)
        }
        let records = result.registry.records.values.sorted { $0.id.raw < $1.id.raw }
        for record in records {
            let snapshot = record.snapshot
            let display = record.display.flatMap { displays.display(id: $0)?.name } ?? "no display"
            let flags = [
                snapshot.isMinimized ? "minimised" : nil,
                snapshot.isFullScreen ? "full screen" : nil,
                snapshot.isModal ? "modal" : nil,
                snapshot.isResizable ? nil : "fixed size",
            ].compactMap { $0 }.joined(separator: ", ")
            let classification: String = switch WindowClassifier.classify(snapshot) {
            case .tiled: "tiled"
            case .minimised: "minimised"
            case .floating(let reason): "floating: \(reason.rawValue)"
            }
            Log.layout.info("""
                Window \(record.id.description, privacy: .public) [\(classification, privacy: .public)] \(snapshot.app.name, privacy: .public) \
                "\(Log.title(snapshot.title), privacy: .public)" \
                \(snapshot.subrole ?? "no subrole", privacy: .public) \
                frame \(snapshot.frame.map { String(describing: $0) } ?? "unknown", privacy: .public) \
                on \(display, privacy: .public) \
                spaces \(record.spaces.map(\.description).joined(separator: ","), privacy: .public) \
                \(flags, privacy: .public)
                """)
        }
    }
}
