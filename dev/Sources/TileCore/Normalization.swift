// Normalisation (rule L5), ported from the prototype's `norm` and extended with weights.
import Foundation

extension LayoutNode {
    /// Drops empty parts, collapses single-child splits, and flattens a child split of the
    /// same direction into its parent. When flattening, each grandchild's weight is
    /// multiplied by its parent's weight, so every window keeps its size on screen.
    /// Finally the weights of every split are rescaled to sum to 1.
    public func normalized() -> LayoutNode? {
        guard case .split(let direction, let children) = self else { return self }

        var flattened: [SplitChild] = []
        for child in children {
            guard let node = child.node.normalized() else { continue }
            if case .split(let childDirection, let grandchildren) = node, childDirection == direction {
                for grandchild in grandchildren {
                    flattened.append(SplitChild(grandchild.node, weight: child.weight * grandchild.weight))
                }
            } else {
                flattened.append(SplitChild(node, weight: child.weight))
            }
        }

        switch flattened.count {
        case 0: return nil
        case 1: return flattened[0].node
        default: return .split(direction, Self.rescaled(flattened))
        }
    }

    /// Rescales weights to sum to 1. Invalid weights (zero, negative, not finite) fall back
    /// to equal shares, so a corrupted tree can never produce a zero-size tile.
    static func rescaled(_ children: [SplitChild]) -> [SplitChild] {
        let valid = children.allSatisfy { $0.weight.isFinite && $0.weight > 0 }
        let total = children.reduce(0) { $0 + $1.weight }
        guard valid, total > 0 else {
            let equal = 1.0 / Double(children.count)
            return children.map { SplitChild($0.node, weight: equal) }
        }
        return children.map { SplitChild($0.node, weight: $0.weight / total) }
    }
}

extension LayoutTree {
    public func normalized() -> LayoutTree {
        LayoutTree(root: root?.normalized())
    }
}
