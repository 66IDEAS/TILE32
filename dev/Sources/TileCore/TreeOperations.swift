// Tree operations (architecture TA-4), ported from the prototype's `without`, `addWin`,
// `swapIds`, `applyDrop` and `repl`, extended with weights. All return a new tree.
import CoreGraphics
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

    /// The default arrangement (rule L2): equal columns, or two rows of columns when equal
    /// columns would be narrower than `minimumColumnWidth` (decision D-8). With two rows the
    /// first half of the list fills the top row and the rest the bottom row; an odd window out
    /// takes the full height of the last column.
    public static func arranged(_ ids: [WindowID], availableWidth: CGFloat, minimumColumnWidth: CGFloat = 800) -> LayoutTree {
        guard ids.count > 1, availableWidth / CGFloat(ids.count) < minimumColumnWidth else { return flat(ids) }
        let columns = (ids.count + 1) / 2
        let top = Array(ids.prefix(columns))
        let bottom = Array(ids.dropFirst(columns))
        let weight = 1.0 / Double(columns)
        let children = top.enumerated().map { index, id -> SplitChild in
            guard index < bottom.count else { return SplitChild(.leaf(id), weight: weight) }
            return SplitChild(.split(.vertical, [SplitChild(.leaf(id), weight: 0.5), SplitChild(.leaf(bottom[index]), weight: 0.5)]),
                              weight: weight)
        }
        return LayoutTree(root: .split(.horizontal, children))
    }

    /// Places the window as a full-height column at the left or right display edge, or a
    /// full-width row at the top or bottom (US-32). It leaves its old place first, then gets
    /// an equal share, and the other columns shrink in proportion, as in rule L3.
    public func placing(_ id: WindowID, atDisplayEdge edge: Edge) -> LayoutTree {
        let base = removing(id)
        guard let root = base.root else { return LayoutTree(root: .leaf(id)) }
        let direction: SplitDirection = edge == .left || edge == .right ? .horizontal : .vertical
        let children: [SplitChild]
        if case .split(let existing, let list) = root, existing == direction {
            children = list
        } else {
            children = [SplitChild(root, weight: 1)]
        }
        let count = Double(children.count)
        let scaled = children.map { SplitChild($0.node, weight: $0.weight * count / (count + 1)) }
        let new = SplitChild(.leaf(id), weight: 1 / (count + 1))
        let ordered = edge == .left || edge == .top ? [new] + scaled : scaled + [new]
        return LayoutTree(root: .split(direction, ordered)).normalized()
    }

    /// Removes the window. Its siblings grow in proportion (rule L4).
    public func removing(_ id: WindowID) -> LayoutTree {
        guard contains(id) else { return self }
        return LayoutTree(root: root?.without(id)).normalized()
    }

    /// Adds the window as one more column at the right end of the top level (rule L3).
    /// It gets 1 / (n + 1), and the existing columns shrink in proportion. When one more
    /// column would be narrower than `minimumColumnWidth`, the window fills a second row
    /// instead: it goes below the leftmost column that holds a single window, so windows
    /// arriving one by one end up like "Tile now" would arrange them (decision D-9).
    public func appending(_ id: WindowID, availableWidth: CGFloat = .infinity, minimumColumnWidth: CGFloat = 800) -> LayoutTree {
        guard !contains(id) else { return self }
        guard let root else { return LayoutTree(root: .leaf(id)) }

        let columns: Int
        if case .split(.horizontal, let children) = root { columns = children.count } else { columns = 1 }
        if availableWidth / CGFloat(columns + 1) < minimumColumnWidth {
            switch root {
            case .leaf:
                return LayoutTree(root: .split(.vertical, [SplitChild(root, weight: 0.5), SplitChild(.leaf(id), weight: 0.5)]))
            case .split(.horizontal, var children):
                if let index = children.firstIndex(where: { if case .leaf = $0.node { true } else { false } }) {
                    children[index].node = .split(.vertical, [SplitChild(children[index].node, weight: 0.5),
                                                              SplitChild(.leaf(id), weight: 0.5)])
                    return LayoutTree(root: .split(.horizontal, children)).normalized()
                }
            default:
                break
            }
        }

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

    /// Puts `new` in the place of `old`; the arrangement and the weights stay the same
    /// (rule L9: a window swapped in takes the tile of the least recently used one).
    /// Unchanged if `old` is missing or `new` is already in the tree.
    public func replacing(_ old: WindowID, with new: WindowID) -> LayoutTree {
        guard old != new, contains(old), !contains(new) else { return self }
        return LayoutTree(root: root?.mappingLeaves { $0 == old ? new : $0 })
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
