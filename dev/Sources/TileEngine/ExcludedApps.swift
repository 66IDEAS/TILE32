// Apps the user keeps out of tiling (US-22, TA-10 rule 6, TA-19).
import Foundation

public struct ExcludedApp: Sendable, Equatable, Codable {
    public let bundleID: String
    public let name: String

    public init(bundleID: String, name: String) {
        self.bundleID = bundleID
        self.name = name
    }
}

/// The exclude list in `UserDefaults`, most recently added last (UX-7).
public struct ExcludedAppsStore: Sendable {
    private static let key = "excludedApps"
    private let suiteName: String?

    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> [ExcludedApp] {
        guard let data = defaults.data(forKey: Self.key),
              let apps = try? JSONDecoder().decode([ExcludedApp].self, from: data) else { return [] }
        return apps
    }

    public func save(_ apps: [ExcludedApp]) {
        if let data = try? JSONEncoder().encode(apps) { defaults.set(data, forKey: Self.key) }
    }

    /// Adds the app, or removes it when it is already excluded. Returns the new list.
    @discardableResult
    public func toggle(_ app: ExcludedApp) -> [ExcludedApp] {
        var apps = load()
        if apps.contains(where: { $0.bundleID == app.bundleID }) {
            apps.removeAll { $0.bundleID == app.bundleID }
        } else {
            apps.append(app)
        }
        save(apps)
        return apps
    }

    @discardableResult
    public func remove(_ bundleID: String) -> [ExcludedApp] {
        var apps = load()
        apps.removeAll { $0.bundleID == bundleID }
        save(apps)
        return apps
    }
}
