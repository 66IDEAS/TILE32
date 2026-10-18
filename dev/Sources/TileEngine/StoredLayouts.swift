// Layouts that survive a restart of TILE32 (US-26, TA-19, TA-20). Windows are described by
// app, a hash of their title (the title itself is never stored, N-4) and their position
// among the app's windows. Matching is best effort; unmatched windows join as new ones.
import CoreGraphics
import CryptoKit
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileSpaces

/// How a window is recognised after a restart.
public struct WindowDescriptor: Codable, Sendable, Equatable {
    public let bundleID: String
    public let titleHash: String
    /// Position among the app's windows, ordered by window number.
    public let index: Int

    static func hash(_ title: String) -> String {
        SHA256.hash(data: Data(title.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

/// A layout tree with descriptors instead of window ids.
public indirect enum StoredNode: Codable, Sendable, Equatable {
    case leaf(WindowDescriptor)
    case split(horizontal: Bool, children: [StoredChild])
}

public struct StoredChild: Codable, Sendable, Equatable {
    public let weight: Double
    public let node: StoredNode
}

/// Stored layouts by "Space UUID / display UUID" (numeric Space ids change after a logout).
public typealias StoredLayouts = [String: StoredNode]

public struct StoredLayoutStore: Sendable {
    private static let key = "layouts"
    private let suiteName: String?

    public init(suiteName: String? = nil) { self.suiteName = suiteName }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    /// Dropped on any parse error (TA-19).
    public func load() -> StoredLayouts {
        guard let data = defaults.data(forKey: Self.key),
              let layouts = try? JSONDecoder().decode(StoredLayouts.self, from: data) else { return [:] }
        return layouts
    }

    public func save(_ layouts: StoredLayouts) {
        if let data = try? JSONEncoder().encode(layouts) { defaults.set(data, forKey: Self.key) }
    }
}

enum Descriptors {
    /// Descriptors for the given windows, with indexes per app ordered by window number.
    static func make(_ records: [WindowRecord]) -> [WindowID: WindowDescriptor] {
        var result: [WindowID: WindowDescriptor] = [:]
        let byApp = Dictionary(grouping: records) { $0.snapshot.app.bundleID ?? "pid-\($0.snapshot.app.pid)" }
        for (bundleID, windows) in byApp {
            for (index, record) in windows.sorted(by: { $0.id.raw < $1.id.raw }).enumerated() {
                result[record.id] = WindowDescriptor(bundleID: bundleID, titleHash: WindowDescriptor.hash(record.snapshot.title), index: index)
            }
        }
        return result
    }

    static func store(_ node: LayoutNode, _ descriptors: [WindowID: WindowDescriptor]) -> StoredNode? {
        switch node {
        case .leaf(let id):
            return descriptors[id].map(StoredNode.leaf)
        case .split(let direction, let children):
            let stored = children.compactMap { child in
                store(child.node, descriptors).map { StoredChild(weight: child.weight, node: $0) }
            }
            return stored.isEmpty ? nil : .split(horizontal: direction == .horizontal, children: stored)
        }
    }

    /// Rebuilds a tree from a stored layout: each descriptor takes the best unused match
    /// (same app and title, otherwise same app and index); unmatched entries are dropped.
    static func restore(_ stored: StoredNode, _ descriptors: [WindowID: WindowDescriptor]) -> LayoutTree {
        var unused = descriptors
        func match(_ wanted: WindowDescriptor) -> WindowID? {
            let candidates = unused.filter { $0.value.bundleID == wanted.bundleID }
            let sameTitle = candidates.filter { $0.value.titleHash == wanted.titleHash }
            // Same app, title and position; then a title that is unique; then the position.
            // Several windows of one app often share a title (found in the US-26 test).
            let found = sameTitle.first(where: { $0.value.index == wanted.index })
                ?? (sameTitle.count == 1 ? sameTitle.first : nil)
                ?? candidates.first(where: { $0.value.index == wanted.index })
            if let found { unused[found.key] = nil }
            return found?.key
        }
        func build(_ node: StoredNode) -> LayoutNode? {
            switch node {
            case .leaf(let descriptor):
                return match(descriptor).map(LayoutNode.leaf)
            case .split(let horizontal, let children):
                let built = children.compactMap { child in build(child.node).map { SplitChild($0, weight: child.weight) } }
                return .split(horizontal ? .horizontal : .vertical, built)
            }
        }
        return LayoutTree(root: build(stored)).normalized()
    }
}

extension LayoutEngine {
    /// The shown layouts as stored layouts, keyed by Space UUID and display UUID.
    public func exportLayouts(_ observation: Observation) -> StoredLayouts {
        let descriptors = Descriptors.make(observation.records)
        var result: StoredLayouts = [:]
        for display in observation.displays.displays {
            guard let space = observation.currentSpaces[display.id], !space.uuid.isEmpty,
                  let root = trees[LayoutKey(space: space.id, display: display.id)]?.root,
                  let stored = Descriptors.store(root, descriptors) else { continue }
            result["\(space.uuid)/\(display.id.uuid)"] = stored
        }
        return result
    }

    /// Layouts from the last run, used once for each layout's first visit (US-26).
    public func importLayouts(_ layouts: StoredLayouts) {
        storedLayouts = layouts
    }

    /// The stored layout for a first visit, matched to the observed windows, or nil.
    func restoredTree(for key: LayoutKey, space: SpaceInfo?, observed: [WindowRecord]) -> LayoutTree? {
        guard let space, !space.uuid.isEmpty,
              let stored = storedLayouts.removeValue(forKey: "\(space.uuid)/\(key.display.uuid)") else { return nil }
        let tree = Descriptors.restore(stored, Descriptors.make(observed))
        return tree.isEmpty ? nil : tree
    }
}
