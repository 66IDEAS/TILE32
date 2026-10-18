// Window limit per display (rule L9, US-31, architecture TA-27).
import CoreGraphics
import Foundation
import TileGeometry

public struct WindowLimits: Sendable, Equatable {
    public static let range = 2...16
    /// Displays at least this wide default to 12 windows, smaller ones to 6 (decision D-7).
    public static let wideDisplayWidth: CGFloat = 3840
    public static let wideDefault = 12
    public static let narrowDefault = 6

    /// Limits the user chose, by display UUID.
    public private(set) var chosen: [String: Int]

    public init(chosen: [String: Int] = [:]) {
        self.chosen = chosen.filter { Self.range.contains($0.value) }
    }

    public static func defaultLimit(for display: Display) -> Int {
        display.frame.width >= wideDisplayWidth ? wideDefault : narrowDefault
    }

    public func limit(for display: Display) -> Int {
        chosen[display.id.uuid] ?? Self.defaultLimit(for: display)
    }

    public mutating func set(_ limit: Int, for display: DisplayID) {
        chosen[display.uuid] = min(max(limit, Self.range.lowerBound), Self.range.upperBound)
    }
}

/// Keeps the limits in `UserDefaults` (TA-19).
public struct WindowLimitStore: Sendable {
    private static let key = "windowLimits"
    private let suiteName: String?

    /// `suiteName` lets tests use their own defaults domain.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() -> WindowLimits {
        WindowLimits(chosen: defaults.dictionary(forKey: Self.key) as? [String: Int] ?? [:])
    }

    public func save(_ limits: WindowLimits) {
        defaults.set(limits.chosen, forKey: Self.key)
    }
}
