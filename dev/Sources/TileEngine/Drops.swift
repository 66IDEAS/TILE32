// Drag-to-split in the engine (milestone M2, US-14 to US-18, architecture TA-6, TA-14).
import CoreGraphics
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileLog
import TileSpaces

/// Where a drop would land, for the overlay (US-16) and for the release.
public struct DropPreview: Sendable, Equatable {
    public let target: DropTarget
    public let key: LayoutKey
    /// The area to highlight, before the overlay's own inset (UX-10).
    public let area: CGRect
}

public enum DropOutcome: Sendable, Equatable {
    case swapped, split, movedToEmptyDisplay
    /// No target under the cursor, or the window is not tiled: it goes back to its tile.
    case snappedBack
    case ignored
}

extension LayoutEngine {
    /// The shown layout that holds a window.
    func shownKey(of id: WindowID, displays: DisplayTable, currentSpaces: [DisplayID: SpaceInfo]) -> LayoutKey? {
        for display in displays.displays {
            let key = LayoutKey(space: currentSpaces[display.id]?.id, display: display.id)
            if trees[key]?.contains(id) == true { return key }
        }
        return nil
    }

    /// What a release at `point` would do (US-16). Nil means nothing is highlighted.
    public func dropPreview(for dragged: WindowID, at point: CGPoint, displays: DisplayTable,
                            currentSpaces: [DisplayID: SpaceInfo]) -> DropPreview? {
        guard shownKey(of: dragged, displays: displays, currentSpaces: currentSpaces) != nil,
              let display = displays.display(containing: point) else { return nil }
        let space = currentSpaces[display.id]
        if space?.isFullScreen == true { return nil }
        let key = LayoutKey(space: space?.id, display: display.id)
        let tree = trees[key] ?? LayoutTree()
        guard let target = tree.dropTarget(at: point, in: display.usableArea, excluding: dragged) else { return nil }
        // Dropping on the own display when it holds nothing else would change nothing.
        if case .emptyLayout = target, tree.contains(dragged) { return nil }
        return DropPreview(target: target, key: key, area: previewRect(for: target))
    }

    /// Applies a release at `point` (US-14, US-15, US-17, US-18) and writes the frames.
    /// `snapshots` holds the shown windows, so every affected window can be written.
    public func drop(_ dragged: WindowID, at point: CGPoint, displays: DisplayTable,
                     currentSpaces: [DisplayID: SpaceInfo], snapshots: [WindowID: WindowSnapshot]) async -> DropOutcome {
        guard let source = shownKey(of: dragged, displays: displays, currentSpaces: currentSpaces) else { return .ignored }
        guard let preview = dropPreview(for: dragged, at: point, displays: displays, currentSpaces: currentSpaces),
              let sourceTree = trees[source] else {
            await snapBack(dragged, displays: displays, currentSpaces: currentSpaces, snapshots: snapshots)
            return .snappedBack
        }

        let outcome: DropOutcome
        switch preview.target {
        case .window(let target, let zone, _):
            if preview.key == source {
                trees[source] = sourceTree.dropping(dragged, on: target, zone: zone)
            } else if let targetTree = trees[preview.key] {
                if zone == .center {
                    // Across displays or desktops both windows change place (US-18.2).
                    trees[source] = sourceTree.replacing(dragged, with: target)
                    trees[preview.key] = targetTree.replacing(target, with: dragged)
                } else {
                    trees[source] = Self.nonEmpty(sourceTree.removing(dragged))
                    trees[preview.key] = targetTree.splitting(target: target, with: dragged, zone: zone)
                }
            }
            outcome = zone == .center ? .swapped : .split
        case .emptyLayout:
            trees[source] = Self.nonEmpty(sourceTree.removing(dragged))
            trees[preview.key] = LayoutTree(root: .leaf(dragged))
            outcome = .movedToEmptyDisplay
        }
        let batch = frameBatch(displays: displays, currentSpaces: currentSpaces, snapshots: snapshots, force: [dragged])
        let written = await apply(batch)
        Log.layout.info("Drop: \(String(describing: outcome), privacy: .public), \(batch.count) written, \(written.failed) failed")
        return outcome
    }

    /// Puts a window back into its tile after a drag without a target or a cancel (US-19.1).
    public func snapBack(_ id: WindowID, displays: DisplayTable, currentSpaces: [DisplayID: SpaceInfo],
                         snapshots: [WindowID: WindowSnapshot]) async {
        let batch = frameBatch(displays: displays, currentSpaces: currentSpaces, snapshots: snapshots, force: [id])
            .filter { $0.id == id }
        _ = await apply(batch)
        Log.layout.info("Snapped back \(id.description, privacy: .public)")
    }

    static func nonEmpty(_ tree: LayoutTree) -> LayoutTree? {
        tree.isEmpty ? nil : tree
    }
}
