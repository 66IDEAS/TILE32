// Where a window was, so it can come back to the same place (US-8.2, US-30.3,
// architecture TA-9 "return hint").
import Foundation

public struct ReturnHint: Equatable, Sendable {
    /// A window that was right next to it in the same split.
    public let sibling: WindowID
    /// The side of the sibling the window was on, as a drop zone for `splitting`.
    public let zone: DropZone

    public init(sibling: WindowID, zone: DropZone) {
        self.sibling = sibling
        self.zone = zone
    }
}

extension LayoutTree {
    /// The nearest neighbour of a window and its side. Prefers the following neighbour
    /// (the window was before it: left or top), otherwise the preceding one (right or
    /// bottom). Nil for a window alone in the tree or not in it.
    public func returnHint(for id: WindowID) -> ReturnHint? {
        guard let root, let path = root.path(to: id), !path.isEmpty else { return nil }
        // The parent split of the window.
        var parent = root
        for index in path.dropLast() {
            guard case .split(_, let children) = parent else { return nil }
            parent = children[index].node
        }
        guard case .split(let direction, let children) = parent, let index = path.last else { return nil }
        if index + 1 < children.count, let next = children[index + 1].node.windowIDs.first {
            return ReturnHint(sibling: next, zone: direction == .horizontal ? .left : .top)
        }
        if index > 0, let previous = children[index - 1].node.windowIDs.last {
            return ReturnHint(sibling: previous, zone: direction == .horizontal ? .right : .bottom)
        }
        return nil
    }
}
