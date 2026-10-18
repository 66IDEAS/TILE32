// What the "Windows" submenu shows (US-3, UX-6). Pure: built from the registry, the
// displays and the shown Spaces, so it can be tested without a menu.
import CoreGraphics
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileSpaces

public struct WindowMenuEntry: Sendable, Equatable {
    public let id: WindowID
    public let text: String
}

public struct WindowMenuSection: Sendable, Equatable {
    public let header: String
    public let entries: [WindowMenuEntry]
}

public struct WindowMenuContent: Sendable, Equatable {
    public var sections: [WindowMenuSection]
    public var floating: [WindowMenuEntry]
    public var otherSpacesCount: Int

    public static let empty = WindowMenuContent(sections: [], floating: [], otherSpacesCount: 0)

    public var isEmpty: Bool { sections.allSatisfy(\.entries.isEmpty) && floating.isEmpty }
}

public enum WindowMenuModel {
    /// Titles longer than this are cut in the middle (UX-6).
    public static let maximumLength = 48

    public static func build(
        records: [WindowRecord],
        displays: DisplayTable,
        currentSpaces: [DisplayID: SpaceInfo],
        otherSpacesCount: Int,
        minimisedToMakeRoom: Set<WindowID> = []
    ) -> WindowMenuContent {
        // Primary display first, then the others from left to right.
        let ordered = displays.displays.sorted { a, b in
            a.isPrimary != b.isPrimary ? a.isPrimary : a.frame.minX < b.frame.minX
        }
        let sortedRecords = records.sorted { $0.id.raw < $1.id.raw }

        var sections: [WindowMenuSection] = []
        var floating: [WindowMenuEntry] = []
        for record in sortedRecords {
            if case .floating(let reason) = WindowClassifier.classify(record.snapshot) {
                floating.append(WindowMenuEntry(id: record.id, text: "\(entryText(record.snapshot))  (floating: \(reason.rawValue))"))
            }
        }
        for display in ordered {
            let onDisplay = sortedRecords.filter { $0.display == display.id }
            let entries = onDisplay
                .filter { WindowClassifier.classify($0.snapshot) == .tiled }
                .map { WindowMenuEntry(id: $0.id, text: entryText($0.snapshot)) }
                + onDisplay
                .filter { minimisedToMakeRoom.contains($0.id) && WindowClassifier.classify($0.snapshot) == .minimised }
                .map { WindowMenuEntry(id: $0.id, text: "\(entryText($0.snapshot))  (minimised to make room)") }
            guard !entries.isEmpty else { continue }
            let desktop = currentSpaces[display.id].flatMap(\.desktopNumber).map { " - Desktop \($0)" } ?? ""
            sections.append(WindowMenuSection(header: display.name + desktop, entries: entries))
        }
        return WindowMenuContent(sections: sections, floating: floating, otherSpacesCount: otherSpacesCount)
    }

    /// "App - title", or just the app when the window has no title.
    static func entryText(_ snapshot: WindowSnapshot) -> String {
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return middleTruncated(title.isEmpty ? snapshot.app.name : "\(snapshot.app.name) - \(title)")
    }

    static func middleTruncated(_ text: String, maximum: Int = maximumLength) -> String {
        guard text.count > maximum, maximum > 3 else { return text }
        let keep = maximum - 3
        let head = text.prefix((keep + 1) / 2)
        let tail = text.suffix(keep / 2)
        return "\(head)...\(tail)"
    }
}

/// Reads everything the submenu needs (task T-0.23; the engine takes this over in M1).
public enum WindowMenuLoader {
    public struct Result: Sendable {
        public let content: WindowMenuContent
        /// Elements of the listed windows, so a choice can raise the right window.
        public let windows: [WindowID: WindowSnapshot]
    }

    public static func load(apps: [AppInfo], displays: DisplayTable, spaceService: SpaceService,
                            minimisedToMakeRoom: Set<WindowID> = []) async -> Result {
        let scan = await WindowScan.run(apps: apps, displays: displays, spaceService: spaceService)
        let current = spaceService.currentSpaces(on: displays)
        let shown = Set(current.values.map(\.id))

        // Windows of regular apps that the window server places only on hidden Spaces.
        let pids = Set(apps.map(\.pid))
        let server = WindowServerList.normalWindows().filter { pids.contains($0.ownerPID) }
        let serverSpaces = spaceService.spaces(of: server.map(\.number))
        let elsewhere = server.filter { window in
            guard let spaces = serverSpaces[window.number], !spaces.isEmpty else { return false }
            return shown.isDisjoint(with: spaces)
        }.count

        let records = Array(scan.registry.records.values)
        let content = WindowMenuModel.build(records: records, displays: displays, currentSpaces: current,
                                            otherSpacesCount: elsewhere, minimisedToMakeRoom: minimisedToMakeRoom)
        return Result(content: content, windows: scan.registry.records.mapValues(\.snapshot))
    }
}
