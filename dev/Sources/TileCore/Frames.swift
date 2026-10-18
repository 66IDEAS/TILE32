// Frame computation (architecture TA-5, rule L7).
import CoreGraphics
import Foundation

extension LayoutTree {
    /// Exact tiles without gaps or rounding. Used for hit testing and the overlay, so a
    /// drop zone never depends on the gap size.
    public func rawShares(in rect: CGRect) -> [WindowID: CGRect] {
        var result: [WindowID: CGRect] = [:]
        root?.collectShares(in: rect, rounded: false, into: &result)
        return result
    }

    /// Window frames: the layout rect and every tile are inset by `gap / 2`, which leaves
    /// `gap` between tiles and at the display edge. Boundaries are rounded once and shared
    /// by both neighbours, so there are never one-point seams.
    public func frames(in rect: CGRect, gap: CGFloat) -> [WindowID: CGRect] {
        let half = gap / 2
        let inner = CGRect(
            x: rect.minX + half, y: rect.minY + half,
            width: max(0, rect.width - gap), height: max(0, rect.height - gap)
        )
        var tiles: [WindowID: CGRect] = [:]
        root?.collectShares(in: inner.roundedEdges, rounded: true, into: &tiles)
        return tiles.mapValues { tile in
            CGRect(
                x: tile.minX + half, y: tile.minY + half,
                width: max(0, tile.width - gap), height: max(0, tile.height - gap)
            ).roundedEdges
        }
    }
}

extension LayoutNode {
    func collectShares(in rect: CGRect, rounded: Bool, into result: inout [WindowID: CGRect]) {
        switch self {
        case .leaf(let id):
            result[id] = rect
        case .split(let direction, let children):
            for (child, childRect) in zip(children, Self.childRects(direction, children, in: rect, rounded: rounded)) {
                child.node.collectShares(in: childRect, rounded: rounded, into: &result)
            }
        }
    }

    /// Divides a rect by the children's weights. Each boundary sits at the cumulative sum
    /// of the weights before it; with `rounded` it is rounded once to a whole point.
    static func childRects(_ direction: SplitDirection, _ children: [SplitChild], in rect: CGRect, rounded: Bool) -> [CGRect] {
        let start = direction == .horizontal ? rect.minX : rect.minY
        let length = direction == .horizontal ? rect.width : rect.height

        var boundaries: [CGFloat] = [start]
        var cumulative = 0.0
        for child in children.dropLast() {
            cumulative += child.weight
            let position = start + CGFloat(cumulative) * length
            boundaries.append(rounded ? position.rounded() : position)
        }
        boundaries.append(start + length)

        return (0..<children.count).map { index in
            let from = boundaries[index]
            let to = max(from, boundaries[index + 1])
            return direction == .horizontal
                ? CGRect(x: from, y: rect.minY, width: to - from, height: rect.height)
                : CGRect(x: rect.minX, y: from, width: rect.width, height: to - from)
        }
    }
}

extension CGRect {
    /// Rounds each edge to a whole point (not the size), so shared edges stay shared.
    var roundedEdges: CGRect {
        let left = minX.rounded(), top = minY.rounded()
        return CGRect(x: left, y: top, width: maxX.rounded() - left, height: maxY.rounded() - top)
    }
}
