// The window registry (architecture TA-20): every window TILE32 knows, keyed by an id that
// stays the same while the window lives. Owned by the engine (constitution technical rule 6).
import CoreGraphics
import Foundation
import TileAX
import TileCore
import TileGeometry
import TileSpaces

public struct WindowRecord: Sendable {
    public let id: WindowID
    public let snapshot: WindowSnapshot
    /// The display holding the largest part of the window, if any.
    public let display: DisplayID?
    /// The Spaces the window is on; empty when unknown (fallback mode).
    public let spaces: [SpaceID]
}

public struct WindowRegistry: Sendable {
    /// Ids for windows without a window number start here, far above any real number.
    static let firstFallbackID: UInt64 = 1 << 40

    public private(set) var records: [WindowID: WindowRecord] = [:]
    private var fallbackIDs: [AXElementBox: WindowID] = [:]
    private var nextFallbackID = firstFallbackID

    public init() {}

    /// The window's id: its window number when known, otherwise a stable id per element,
    /// matched with `CFEqual` (TA-20 fallback).
    public mutating func id(for snapshot: WindowSnapshot) -> WindowID {
        if let number = snapshot.windowNumber { return WindowID(UInt64(number)) }
        if let existing = fallbackIDs[snapshot.element] { return existing }
        let id = WindowID(nextFallbackID)
        nextFallbackID += 1
        fallbackIDs[snapshot.element] = id
        return id
    }

    /// Replaces the registry with a fresh reading. Windows that are gone are dropped,
    /// including their fallback ids.
    public mutating func update(with snapshots: [WindowSnapshot], displays: DisplayTable, spaces: [CGWindowID: [SpaceID]]) {
        var updated: [WindowID: WindowRecord] = [:]
        for snapshot in snapshots {
            let id = id(for: snapshot)
            updated[id] = WindowRecord(
                id: id,
                snapshot: snapshot,
                display: snapshot.frame.flatMap { displays.display(mostlyContaining: $0)?.id },
                spaces: snapshot.windowNumber.flatMap { spaces[$0] } ?? []
            )
        }
        let alive = Set(updated.keys)
        fallbackIDs = fallbackIDs.filter { alive.contains($0.value) }
        records = updated
    }
}
