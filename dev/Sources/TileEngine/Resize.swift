// Resizing by edge (milestone M2, US-28, rule L8, architecture TA-25).
import CoreGraphics
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileLog
import TileSpaces

extension LayoutEngine {
    /// The user is dragging one or two edges of window `id`, which now has `frame`.
    /// While `final` is false only the neighbours are written (the user holds the window);
    /// on release the boundary snaps and every affected window is written (TA-25).
    /// Returns the window's share of the display along the dragged axis, for the label.
    @discardableResult
    public func resize(_ id: WindowID, to frame: CGRect, edges: Set<Edge>, final: Bool, displays: DisplayTable,
                       currentSpaces: [DisplayID: SpaceInfo], snapshots: [WindowID: WindowSnapshot]) async -> Double? {
        guard let key = shownKey(of: id, displays: displays, currentSpaces: currentSpaces),
              let display = displays.display(id: key.display), var tree = trees[key] else { return nil }
        // Tile boundaries sit half a gap outside the window's edges (rule L7).
        let half = Self.gap / 2
        let inner = display.usableArea.insetBy(dx: half, dy: half)
        for edge in edges {
            let position: CGFloat = switch edge {
            case .left: frame.minX - half
            case .right: frame.maxX + half
            case .top: frame.minY - half
            case .bottom: frame.maxY + half
            }
            tree = tree.resizing(window: id, edge: edge, to: position, in: inner, snap: final)
        }
        trees[key] = tree

        var batch = frameBatch(displays: displays, currentSpaces: currentSpaces, snapshots: snapshots,
                               force: final ? [id] : [])
        if !final { batch.removeAll { $0.id == id } }
        _ = await apply(batch)
        if final { Log.resize.info("Resize of \(id.description, privacy: .public) ended, \(batch.count) written") }

        guard let tile = tree.rawShares(in: inner)[id] else { return nil }
        let horizontal = edges.contains(.left) || edges.contains(.right)
        return Double(horizontal ? tile.width / inner.width : tile.height / inner.height)
    }
}
