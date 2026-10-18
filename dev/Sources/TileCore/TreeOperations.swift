// Tree operations (architecture TA-4), ported from the prototype's `without`, `addWin`,
// `swapIds`, `applyDrop` and `repl`, extended with weights. All return a new tree.
import Foundation

extension LayoutTree {
    /// Equal columns from an ordered list (rule L2).
    public static func flat(_ ids: [WindowID]) -> LayoutTree {
        switch ids.count {
        case 0: return LayoutTree()
        case 1: return LayoutTree(root: .leaf(ids[0]))
        default:
            let weight = 1.0 / Double(ids.count)
            return LayoutTree(root: .split(.horizontal, ids.map { SplitChild(.leaf($0), weight: weight) }))
        }
    }

    /// Removes the window. Its siblings grow in proportion (rule L4).
    public func removing(_ id: WindowID) -> LayoutTree {
        guard contains(id) else { return self }
        return LayoutTree(root: root?.without(id)).normalized()
    }

    /// Adds the window as one more column at the right end of the top level (rule L3).
    /// It gets 1 / (n + 1), and the existing columns shrink in proportion.
    public func appending(_ id: WindowID) -> LayoutTree {
        guard !contains(id) else { return self }
        guard let root else { return LayoutTree(root: .leaf(id)) }

        if case .split(.horizontal, let children) = root {
            let count = Double(children.count)
            let scaled = children.map { SplitChild($0.node, weight: $0.weight * count / (count + 1)) }
            return LayoutTree(root: .split(.horizontal, scaled + [SplitChild(.leaf(id), weight: 1 / (count + 1))]))
                .normalized()
        }
        return LayoutTree(root: .split(.horizontal, [SplitChild(root, weight: 0.5), SplitChild(.leaf(id), weight: 0.5)]))
            .normalized()
    }

    /// Exchanges two windows. Weights stay where they are, so each window takes the
    /// other's size (rule L1). Unchanged if either window is missing.
    public func swapping(_ a: WindowID, _ b: WindowID) -> LayoutTree {
        guard a != b, contains(a), contains(b) else { return self }
        return LayoutTree(root: root?.mappingLeaves { $0 == a ? b : $0 == b ? a : $0 })
    }

    /// Applies a drop (rule L6): the centre zone swaps, an edge zone splits the target.
    /// The dragged window may come from another tree (another display or Space); then
    /// only the insertion happens here and the caller removes it from the source tree.
    public func dropping(_ dragged: WindowID, on target: WindowID, zone: DropZone) -> LayoutTree {
        zone == .center ? swapping(dragged, target) : splitting(target: target, with: dragged, zone: zone)
    }

    /// Removes the dragged window, then replaces the target with a split of two equal
    /// halves in the target's position and with the target's weight. Left and top put the
    /// dragged window first. Also used to bring a window back next to a former neighbour.
    public func splitting(target: WindowID, with dragged: WindowID, zone: DropZone) -> LayoutTree {
        guard zone != .center, target != dragged, contains(target) else { return self }

        let direction: SplitDirection = (zone == .left || zone == .right) ? .horizontal : .vertical
        let draggedFirst = (zone == .left || zone == .top)
        let pair = draggedFirst
            ? [SplitChild(.leaf(dragged), weight: 0.5), SplitChild(.leaf(target), weight: 0.5)]
            : [SplitChild(.leaf(target), weight: 0.5), SplitChild(.leaf(dragged), weight: 0.5)]

        let withoutDragged = removing(dragged)
        guard let root = withoutDragged.root, let path = root.path(to: target) else { return self }
        return LayoutTree(root: root.replacingNode(atPath: path[...], with: .split(direction, pair))).normalized()
    }

    /// Sets every split back to equal shares without changing the arrangement (US-28.9).
    public func equalized() -> LayoutTree {
        LayoutTree(root: root?.equalized())
    }
}

extension LayoutNode {
    func without(_ id: WindowID) -> LayoutNode? {
        switch self {
        case .leaf(let leafID):
            return leafID == id ? nil : self
        case .split(let direction, let children):
            let remaining = children.compactMap { child in
                child.node.without(id).map { SplitChild($0, weight: child.weight) }
            }
            return .split(direction, remaining)
        }
    }

    func mappingLeaves(_ transform: (WindowID) -> WindowID) -> LayoutNode {
        switch self {
        case .leaf(let id):
            return .leaf(transform(id))
        case .split(let direction, let children):
            return .split(direction, children.map { SplitChild($0.node.mappingLeaves(transform), weight: $0.weight) })
        }
    }

    func equalized() -> LayoutNode {
        guard case .split(let direction, let children) = self else { return self }
        let weight = 1.0 / Double(children.count)
        return .split(direction, children.map { SplitChild($0.node.equalized(), weight: weight) })
    }
}
