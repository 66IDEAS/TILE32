// Spike tool for S2 (task T-0.19): writes test frames to tiled windows, reads them back,
// logs differences and timings, and puts every window back where it was. This tool moves
// windows, so it only runs when the owner agrees (tasks, working agreement 1), or limited
// to FakeWindows windows.
import CoreGraphics
import Foundation
import TileAX
import TileGeometry
import TileLog
import TileSpaces

public enum FrameWriteTest {
    public static func run(apps: [AppInfo], displays: DisplayTable, spaceService: SpaceService, onlyBundleID: String? = nil) async {
        let targets = apps.filter { onlyBundleID == nil || $0.bundleID == onlyBundleID }
        let scan = await WindowScan.run(apps: targets, displays: displays, spaceService: spaceService)
        let windows = scan.registry.records.values
            .filter { WindowClassifier.classify($0.snapshot) == .tiled && $0.snapshot.frame != nil }
            .sorted { $0.id.raw < $1.id.raw }
        Log.layout.info("S2 frame write test: \(windows.count) tiled windows\(onlyBundleID.map { " of \($0)" } ?? "", privacy: .public)")

        for record in windows {
            guard let original = record.snapshot.frame,
                  let home = record.display.flatMap(displays.display(id:)) else { continue }
            var cases: [(String, CGRect)] = [
                ("smaller", CGRect(x: original.minX + 40, y: original.minY + 30,
                                   width: max(300, original.width - 120), height: max(200, original.height - 90))),
                ("half of display", CGRect(x: home.usableArea.minX + 6, y: home.usableArea.minY + 6,
                                           width: home.usableArea.width / 2 - 9, height: home.usableArea.height - 12)),
            ]
            if let other = displays.displays.first(where: { $0.id != home.id }) {
                cases.append(("other display", CGRect(x: other.usableArea.minX + 6, y: other.usableArea.minY + 6,
                                                      width: min(1000, other.usableArea.width - 12),
                                                      height: min(700, other.usableArea.height - 12))))
            }

            for (name, frame) in cases {
                for workaround in [false, true] {
                    let result = await AXWorker.shared.run(for: record.snapshot.app.pid) {
                        FrameWriter.write(frame, to: record.snapshot.element, pid: record.snapshot.app.pid, disableEnhancedUI: workaround)
                    }
                    log(record, case: name, workaround: workaround, result: result)
                }
            }
            let restore = await AXWorker.shared.run(for: record.snapshot.app.pid) {
                FrameWriter.write(original, to: record.snapshot.element, pid: record.snapshot.app.pid)
            }
            Log.layout.info("S2   \(record.id.description, privacy: .public) restored: \(restore.matches ? "yes" : "no", privacy: .public)")
        }
        Log.layout.info("S2 frame write test finished")
    }

    private static func log(_ record: WindowRecord, case name: String, workaround: Bool, result: FrameWriteResult) {
        let outcome = result.matches ? "matches" : result.doesNotFit ? "does not fit" : "differs"
        Log.layout.info("""
            S2   \(record.id.description, privacy: .public) \(record.snapshot.app.name, privacy: .public) \
            \(name, privacy: .public)\(workaround ? " with workaround" : "", privacy: .public): \(outcome, privacy: .public), \
            requested \(String(describing: result.requested), privacy: .public) \
            actual \(result.actual.map { String(describing: $0) } ?? "unreadable", privacy: .public), \
            errors \(result.sizeError.rawValue)/\(result.positionError.rawValue), \
            \(result.duration.formatted(.units(allowed: [.milliseconds])), privacy: .public)
            """)
    }
}
