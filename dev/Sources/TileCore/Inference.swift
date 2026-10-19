// Rebuilding a layout from window frames that already tile a display (US-26). This is the
// inverse of `frames(in:gap:)`: when TILE32 starts and the windows are still where it left
// them, the layout is read back from the screen and nothing moves (found on 2026-10-19:
// after a restart the windows were rearranged).
import CoreGraphics
import Foundation

extension LayoutTree {
    /// The layout whose frames are the given window frames, or nil when the frames cannot be
    /// cut into columns and rows without crossing a window. Columns are tried before rows.
    /// `tolerance` allows windows that end a few points away from their tile, for example
    /// Terminal, which sizes in character steps.
    public static func inferred(from frames: [WindowID: CGRect], in rect: CGRect, gap: CGFloat,
                                tolerance: CGFloat = 4) -> LayoutTree? {
        guard !frames.isEmpty else { return nil }
        let half = gap / 2
        let inner = CGRect(x: rect.minX + half, y: rect.minY + half,
                           width: max(0, rect.width - gap), height: max(0, rect.height - gap))
        let items = frames.map { Item(id: $0.key, frame: $0.value) }.sorted { $0.id.raw < $1.id.raw }
        guard let node = infer(items, in: inner, tolerance: tolerance) else { return nil }
        return LayoutTree(root: node).normalized()
    }

    private struct Item {
        let id: WindowID
        let frame: CGRect
    }

    private static func infer(_ items: [Item], in tile: CGRect, tolerance: CGFloat) -> LayoutNode? {
        if items.count == 1 { return .leaf(items[0].id) }
        for direction in [SplitDirection.horizontal, .vertical] {
            let groups = cut(items, direction, tolerance: tolerance)
            guard groups.count > 1 else { continue }
            let horizontal = direction == .horizontal
            let start = horizontal ? tile.minX : tile.minY
            let length = horizontal ? tile.width : tile.height
            guard length > 0 else { return nil }

            // A tile boundary lies in the middle of the gap between two groups, exactly where
            // `frames(in:gap:)` put it.
            var boundaries = [start]
            for index in 0..<(groups.count - 1) {
                let end = groups[index].map { horizontal ? $0.frame.maxX : $0.frame.maxY }.max() ?? start
                let next = groups[index + 1].map { horizontal ? $0.frame.minX : $0.frame.minY }.min() ?? end
                boundaries.append(min(max((end + next) / 2, start), start + length))
            }
            boundaries.append(start + length)

            var children: [SplitChild] = []
            for (index, group) in groups.enumerated() {
                let from = boundaries[index], to = boundaries[index + 1]
                guard to > from else { return nil }
                let childTile = horizontal
                    ? CGRect(x: from, y: tile.minY, width: to - from, height: tile.height)
                    : CGRect(x: tile.minX, y: from, width: tile.width, height: to - from)
                guard let node = infer(group, in: childTile, tolerance: tolerance) else { return nil }
                children.append(SplitChild(node, weight: Double((to - from) / length)))
            }
            return .split(direction, children)
        }
        return nil
    }

    /// Groups the windows into columns (horizontal) or rows (vertical): a new group starts
    /// where no window of the previous groups reaches across.
    private static func cut(_ items: [Item], _ direction: SplitDirection, tolerance: CGFloat) -> [[Item]] {
        let horizontal = direction == .horizontal
        func low(_ item: Item) -> CGFloat { horizontal ? item.frame.minX : item.frame.minY }
        func high(_ item: Item) -> CGFloat { horizontal ? item.frame.maxX : item.frame.maxY }

        var groups: [[Item]] = []
        var current: [Item] = []
        var reach = -CGFloat.infinity
        for item in items.sorted(by: { (low($0), $0.id.raw) < (low($1), $1.id.raw) }) {
            if !current.isEmpty, low(item) >= reach - tolerance {
                groups.append(current)
                current = []
                reach = -.infinity
            }
            current.append(item)
            reach = max(reach, high(item))
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
}
