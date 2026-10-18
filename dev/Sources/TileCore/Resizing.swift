// Resizing by edge (rule L8, architecture TA-4 and TA-25).
import CoreGraphics
import Foundation

public enum ResizeLimits {
    /// No tile becomes smaller than 10 percent of its split or 200 points (rule L8).
    public static let minimumShare: CGFloat = 0.10
    public static let minimumPoints: CGFloat = 200
    /// Boundaries snap to these positions within their split (rule L8).
    public static let snapRatios: [CGFloat] = [1.0 / 4, 1.0 / 3, 1.0 / 2, 2.0 / 3, 3.0 / 4]
    public static let snapTolerance: CGFloat = 0.01
}

/// The nearest snap ratio within the tolerance, otherwise the ratio itself.
public func snappedRatio(_ ratio: CGFloat) -> CGFloat {
    let nearest = ResizeLimits.snapRatios.min { abs($0 - ratio) < abs($1 - ratio) } ?? ratio
    return abs(nearest - ratio) <= ResizeLimits.snapTolerance + 1e-9 ? nearest : ratio
}

extension LayoutTree {
    /// Moves the boundary across `edge` of the window to `position`, given in the same
    /// coordinates as `rect` (raw shares, without gaps). Only the two parts on either side
    /// of that boundary change. The boundary belongs to the nearest ancestor split in the
    /// edge's direction where the window's branch has a neighbour on that side, so
    /// dragging a window's edge inside a column resizes the whole column.
    ///
    /// Returns the tree unchanged for an outer edge (no neighbour, US-19.2) or when the
    /// two parts are too small to respect the minimum.
    public func resizing(window: WindowID, edge: Edge, to position: CGFloat, in rect: CGRect, snap: Bool = false) -> LayoutTree {
        guard let root, let path = root.path(to: window) else { return self }

        // The split nodes along the path, each with its own rect.
        var ancestors: [(node: LayoutNode, rect: CGRect)] = []
        var node = root
        var nodeRect = rect
        for index in path {
            guard case .split(let direction, let children) = node else { break }
            ancestors.append((node, nodeRect))
            nodeRect = LayoutNode.childRects(direction, children, in: nodeRect, rounded: false)[index]
            node = children[index].node
        }

        for depth in stride(from: ancestors.count - 1, through: 0, by: -1) {
            guard case .split(let direction, var children) = ancestors[depth].node, direction == edge.axis else { continue }
            let first = edge.facesNextSibling ? path[depth] : path[depth] - 1
            guard first >= 0, first + 1 < children.count else { continue }

            let splitRect = ancestors[depth].rect
            let start = direction == .horizontal ? splitRect.minX : splitRect.minY
            let length = direction == .horizontal ? splitRect.width : splitRect.height
            guard length > 0 else { return self }

            let before = children[..<first].reduce(0) { $0 + $1.weight }
            let pairWeight = children[first].weight + children[first + 1].weight
            let pairStart = start + CGFloat(before) * length
            let pairEnd = pairStart + CGFloat(pairWeight) * length

            let minimum = max(ResizeLimits.minimumShare * length, ResizeLimits.minimumPoints)
            guard pairEnd - pairStart >= 2 * minimum else { return self }

            var boundary = position
            if snap {
                boundary = start + snappedRatio((boundary - start) / length) * length
            }
            boundary = min(max(boundary, pairStart + minimum), pairEnd - minimum)

            children[first].weight = Double((boundary - pairStart) / length)
            children[first + 1].weight = Double((pairEnd - boundary) / length)

            let updated = LayoutNode.split(direction, children)
            return LayoutTree(root: root.replacingNode(atPath: path[..<depth], with: updated)).normalized()
        }
        return self
    }
}
