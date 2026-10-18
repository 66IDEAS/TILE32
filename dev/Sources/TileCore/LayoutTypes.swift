// TileCore: the pure layout core (architecture TA-3 to TA-6, TA-25).
// Imports only Foundation and CoreGraphics value types (constitution, technical rule 4).
//
// Coordinates follow the Accessibility convention: origin at the top-left, y grows
// downward. The first child of a vertical split is therefore the top one.
import CoreGraphics
import Foundation

/// Opaque window identifier issued by the engine. TileCore never looks inside it.
public struct WindowID: Hashable, Sendable, CustomStringConvertible {
    public let raw: UInt64
    public init(_ raw: UInt64) { self.raw = raw }
    public var description: String { "w\(raw)" }
}

/// `horizontal` places children side by side, `vertical` one above the other.
public enum SplitDirection: Sendable, Equatable {
    case horizontal, vertical
}

/// One part of a split. The weight is the share of the split (L1); siblings sum to 1.
/// Weights sit on the parent's entries, so they belong to a position, not to a window.
public struct SplitChild: Equatable, Sendable {
    public var node: LayoutNode
    public var weight: Double

    public init(_ node: LayoutNode, weight: Double) {
        self.node = node
        self.weight = weight
    }
}

public indirect enum LayoutNode: Equatable, Sendable {
    case leaf(WindowID)
    case split(SplitDirection, [SplitChild])
}

/// The layout of one Space on one display. `nil` root means an empty layout.
public struct LayoutTree: Equatable, Sendable {
    public var root: LayoutNode?

    public init(root: LayoutNode? = nil) {
        self.root = root
    }
}

/// Where a dragged window is dropped on a target window (rule L6).
public enum DropZone: Sendable, Equatable, CaseIterable {
    case center, left, right, top, bottom
}

/// A window edge, used for resizing (rule L8).
public enum Edge: Sendable, Equatable, CaseIterable {
    case left, right, top, bottom

    var axis: SplitDirection { self == .left || self == .right ? .horizontal : .vertical }
    /// True when the neighbour across this edge comes after the window in its split.
    var facesNextSibling: Bool { self == .right || self == .bottom }
}

// MARK: - Queries

extension LayoutNode {
    /// Window ids in tree order (left to right, top to bottom).
    public var windowIDs: [WindowID] {
        switch self {
        case .leaf(let id): [id]
        case .split(_, let children): children.flatMap(\.node.windowIDs)
        }
    }

    public func contains(_ id: WindowID) -> Bool {
        switch self {
        case .leaf(let leafID): leafID == id
        case .split(_, let children): children.contains { $0.node.contains(id) }
        }
    }

    /// Child indices from this node down to the leaf, or nil if the window is not here.
    func path(to id: WindowID) -> [Int]? {
        switch self {
        case .leaf(let leafID):
            return leafID == id ? [] : nil
        case .split(_, let children):
            for (index, child) in children.enumerated() {
                if let rest = child.node.path(to: id) { return [index] + rest }
            }
            return nil
        }
    }

    func replacingNode(atPath path: ArraySlice<Int>, with replacement: LayoutNode) -> LayoutNode {
        guard let index = path.first, case .split(let direction, var children) = self else {
            return replacement
        }
        children[index].node = children[index].node.replacingNode(atPath: path.dropFirst(), with: replacement)
        return .split(direction, children)
    }
}

extension LayoutTree {
    public var windowIDs: [WindowID] { root?.windowIDs ?? [] }
    public var isEmpty: Bool { root == nil }

    public func contains(_ id: WindowID) -> Bool {
        root?.contains(id) ?? false
    }
}
