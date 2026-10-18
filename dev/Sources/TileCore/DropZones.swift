// Drop zones and drop targets (architecture TA-6, rule L6), ported from the prototype's `zoneOf`.
import CoreGraphics
import Foundation

/// The centre zone is the middle 44 percent of a tile in both directions. These two
/// numbers are the only place to change it (spec Q-10).
public enum DropZoneGeometry {
    public static let centerLow: CGFloat = 0.28
    public static let centerHigh: CGFloat = 0.72
}

/// What the overlay shows and what a release does.
public enum DropTarget: Equatable, Sendable {
    /// A window under the cursor, the zone, and the window's raw tile.
    case window(WindowID, DropZone, tile: CGRect)
    /// A layout with no window other than the dragged one: "Move to this display".
    case emptyLayout(CGRect)
}

/// The zone of a point inside a tile. Outside the centre, the nearest edge wins; ties
/// resolve in the order left, right, top, bottom, as in the prototype.
public func dropZone(at point: CGPoint, in tile: CGRect) -> DropZone {
    let rx = (point.x - tile.minX) / tile.width
    let ry = (point.y - tile.minY) / tile.height
    let low = DropZoneGeometry.centerLow, high = DropZoneGeometry.centerHigh
    if rx > low, rx < high, ry > low, ry < high { return .center }

    let distances: [(DropZone, CGFloat)] = [(.left, rx), (.right, 1 - rx), (.top, ry), (.bottom, 1 - ry)]
    // The tolerance makes ties that differ only by floating-point noise (1 - 0.9 is
    // 0.09999999999999998) resolve in the documented order.
    var best = distances[0]
    for candidate in distances.dropFirst() where candidate.1 < best.1 - 1e-9 {
        best = candidate
    }
    return best.0
}

/// The area the overlay highlights: the whole tile for a swap, the half on the chosen
/// side for a split, the whole layout rect for an empty layout.
public func previewRect(for target: DropTarget) -> CGRect {
    switch target {
    case .emptyLayout(let rect):
        return rect
    case .window(_, let zone, let tile):
        switch zone {
        case .center: return tile
        case .left: return CGRect(x: tile.minX, y: tile.minY, width: tile.width / 2, height: tile.height)
        case .right: return CGRect(x: tile.midX, y: tile.minY, width: tile.width / 2, height: tile.height)
        case .top: return CGRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height / 2)
        case .bottom: return CGRect(x: tile.minX, y: tile.midY, width: tile.width, height: tile.height / 2)
        }
    }
}

extension LayoutTree {
    /// The drop target under the cursor, or nil when nothing is highlighted (which cancels
    /// the drag, US-17.2). The dragged window's own tile is never a target.
    public func dropTarget(at point: CGPoint, in rect: CGRect, excluding dragged: WindowID?) -> DropTarget? {
        guard rect.contains(point) else { return nil }
        guard windowIDs.contains(where: { $0 != dragged }) else { return .emptyLayout(rect) }

        for (id, tile) in rawShares(in: rect) where id != dragged {
            if point.x >= tile.minX, point.x < tile.maxX, point.y >= tile.minY, point.y < tile.maxY {
                return .window(id, dropZone(at: point, in: tile), tile: tile)
            }
        }
        return nil
    }
}
