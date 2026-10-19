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
    /// The window number. It stays the same while the app keeps running, so after a restart
    /// of TILE32 alone every window is recognised exactly. Missing in layouts stored by
    /// earlier builds.
    public var windowNumber: UInt64?

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
                result[record.id] = WindowDescriptor(bundleID: bundleID, titleHash: WindowDescriptor.hash(record.snapshot.title),
                                                     index: index, windowNumber: record.id.raw)
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
            // The same window while the app kept running; then the same app, title and
            // position; then a title that is unique; then the position. Several windows of one
            // app often share a title (found in the US-26 test).
            let found = candidates.first(where: { wanted.windowNumber != nil && $0.value.windowNumber == wanted.windowNumber })
                ?? sameTitle.first(where: { $0.value.index == wanted.index })
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
        var result: StoredLayouts = [:]
        for display in observation.displays.displays {
            guard let space = observation.currentSpaces[display.id], !space.uuid.isEmpty,
                  let tree = trees[LayoutKey(space: space.id, display: display.id)], let root = tree.root else { continue }
            // Positions are counted among the windows of this layout only, exactly as on
            // restore. Counting across both displays mixed up windows of one app (found on
            // 2026-10-19: windows were rearranged after a restart).
            let descriptors = Descriptors.make(observation.records.filter { tree.contains($0.id) })
            guard let stored = Descriptors.store(root, descriptors) else { continue }
            result["\(space.uuid)/\(display.id.uuid)"] = stored
        }
        return result
    }

    /// The remembered layouts, offered to every first visit of a layout (US-26). The
    /// coordinator passes them again after every save, so they stay current.
    public func importLayouts(_ layouts: StoredLayouts) {
        storedLayouts = layouts
    }

    /// Forgets one layout; for tests of a later first visit.
    func forgetTree(_ key: LayoutKey) {
        trees[key] = nil
    }

    /// Replaces one layout; for tests that need a structure no drop produces.
    func setTree(_ tree: LayoutTree, for key: LayoutKey) {
        trees[key] = tree
    }

    /// Forgets every remembered layout, for "Untile" (US-24).
    public func forgetStoredLayouts() {
        storedLayouts = [:]
    }

    /// The layout for the first visit of a desktop on a display (US-26), in this order:
    /// a remembered layout that already matches the windows on screen; the arrangement on
    /// screen read back from the window frames, when it is a tiling (windows that overlap
    /// others are left out and join afterwards); a remembered layout that does not
    /// match, which moves the windows back to their remembered places; nil, which arranges
    /// afresh.
    func firstVisitTree(for key: LayoutKey, space: SpaceInfo?, display: Display,
                        observed: [WindowRecord]) -> (tree: LayoutTree, source: String)? {
        let area = display.usableArea
        var current: [WindowID: CGRect] = [:]
        for record in observed { if let frame = record.snapshot.frame { current[record.id] = frame } }

        let remembered = restoredTree(for: key, space: space, observed: observed)
        if let remembered {
            let frames = remembered.frames(in: area, gap: Self.gap)
            let matches = frames.allSatisfy { id, frame in
                current[id].map { Self.close($0, frame, tolerance: FrameWriteResult.stepTolerance) } ?? false
            }
            if matches { return (remembered, "remembered layout, already on screen") }
        }

        let overlapping = Set(current.keys.filter { id in
            let frame = current[id]!.insetBy(dx: 2, dy: 2)
            return current.contains { $0.key != id && $0.value.insetBy(dx: 2, dy: 2).intersects(frame) }
        })
        let clean = current.filter { !overlapping.contains($0.key) }
        // Only a real tiling is taken over: the layout read back must give the windows the
        // frames they have. Windows that merely do not overlap are arranged afresh.
        if let adopted = LayoutTree.inferred(from: clean, in: area, gap: Self.gap),
           adopted.frames(in: area, gap: Self.gap).allSatisfy({ id, frame in
               clean[id].map { Self.close($0, frame, tolerance: FrameWriteResult.stepTolerance) } ?? false
           }) {
            return (adopted, "arrangement on screen")
        }

        if let remembered { return (remembered, "remembered layout, windows moved back") }
        return nil
    }

    /// The stored layout for a first visit, matched to the observed windows, or nil.
    func restoredTree(for key: LayoutKey, space: SpaceInfo?, observed: [WindowRecord]) -> LayoutTree? {
        guard let space, !space.uuid.isEmpty,
              let stored = storedLayouts["\(space.uuid)/\(key.display.uuid)"] else { return nil }
        let tree = Descriptors.restore(stored, Descriptors.make(observed))
        return tree.isEmpty ? nil : tree
    }
}
