// Spike tools for S6 and S3 (task T-0.17): what the window server and the Accessibility API
// report about Spaces, and where they disagree. Reads only; no titles are logged.
import CoreGraphics
import Foundation
import TileAX
import TileGeometry
import TileLog
import TileSpaces

public enum SpaceDiagnostics {
    /// "Log Spaces": the display-Spaces table with types, desktop numbers and UUIDs.
    public static func logSpaces(service: SpaceService, displays: DisplayTable) {
        guard service.isAvailable else {
            Log.spaces.error("S6 Space functions unavailable")
            return
        }
        for entry in service.spaceTable() {
            let desktops = entry.spaces.filter { $0.type == 0 }.count
            let fullScreen = entry.spaces.filter(\.isFullScreen).count
            Log.spaces.info("""
                S6 entry \(entry.displayIdentifier, privacy: .public): current \(entry.current.id.description, privacy: .public) \
                desktop \(entry.current.desktopNumber.map(String.init) ?? "-", privacy: .public), \
                \(desktops) desktops, \(fullScreen) full-screen Spaces
                """)
            for space in entry.spaces {
                Log.spaces.info("""
                    S6   \(space.id.description, privacy: .public) type \(space.type) \
                    desktop \(space.desktopNumber.map(String.init) ?? "-", privacy: .public) uuid \(space.uuid, privacy: .public)
                    """)
            }
        }
        for (displayID, space) in service.currentSpaces(on: displays) {
            Log.spaces.info("S6 display \(displays.display(id: displayID)?.name ?? displayID.uuid, privacy: .public) shows \(space.id.description, privacy: .public)")
        }
    }

    /// "Log windows": windows per Space from the window server, compared with what the
    /// Accessibility API lists for the regular apps.
    public static func logWindows(apps: [AppInfo], service: SpaceService, displays: DisplayTable) async {
        let regularPIDs = Set(apps.map(\.pid))
        let server = WindowServerList.normalWindows().filter { regularPIDs.contains($0.ownerPID) }
        let serverSpaces = service.spaces(of: server.map(\.number))
        let current = Set(service.currentSpaces(on: displays).values.map(\.id))

        var perSpace: [String: Int] = [:]
        for window in server {
            let key = serverSpaces[window.number]?.map(\.description).joined(separator: "+") ?? "no Space"
            perSpace[key, default: 0] += 1
        }
        let onScreen = server.filter(\.isOnScreen).count
        Log.spaces.info("S3 window server: \(server.count) normal windows of regular apps, \(onScreen) on screen")
        for (space, count) in perSpace.sorted(by: { $0.key < $1.key }) {
            Log.spaces.info("S3   \(space, privacy: .public): \(count) windows")
        }

        let scan = await WindowScan.run(apps: apps, displays: displays, spaceService: service)
        let axNumbers = Set(scan.registry.records.values.compactMap(\.snapshot.windowNumber))
        let withoutNumber = scan.registry.records.values.filter { $0.snapshot.windowNumber == nil }.count
        let axOnHidden = scan.registry.records.values.filter { record in
            !record.spaces.isEmpty && current.isDisjoint(with: record.spaces)
        }
        let serverOnCurrent = server.filter { window in
            guard let spaces = serverSpaces[window.number] else { return false }
            return !current.isDisjoint(with: spaces)
        }
        let missingFromAX = serverOnCurrent.filter { !axNumbers.contains($0.number) }

        Log.spaces.info("""
            S3 Accessibility: \(scan.registry.records.count) windows (\(withoutNumber) without window number), \
            \(axOnHidden.count) of them on a hidden Space, reading took \(scan.duration.formatted(.units(allowed: [.milliseconds])), privacy: .public)
            """)
        for record in axOnHidden {
            Log.spaces.info("""
                S3   listed on hidden Space: \(record.id.description, privacy: .public) \(record.snapshot.app.name, privacy: .public) \
                \(record.spaces.map(\.description).joined(separator: ","), privacy: .public) minimised \(record.snapshot.isMinimized)
                """)
        }
        Log.spaces.info("S3 window server lists \(serverOnCurrent.count) windows on the shown Spaces; \(missingFromAX.count) of them are missing from Accessibility")
        for window in missingFromAX {
            Log.spaces.info("S3   missing: w\(window.number) \(window.ownerName, privacy: .public) bounds \(String(describing: window.bounds), privacy: .public) on screen \(window.isOnScreen)")
        }
        let unanswered = scan.apps.filter { $0.error != .success && $0.error != .noValue }
        if !unanswered.isEmpty {
            Log.spaces.info("S3 apps that did not answer: \(unanswered.map(\.app.name).joined(separator: ", "), privacy: .public)")
        }
    }
}
