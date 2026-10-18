// A scripted Space service for engine tests (architecture TA-24, TA-26).
import ApplicationServices
import CoreGraphics
import Foundation

public final class FakeSpaceService: SpaceService, @unchecked Sendable {
    // @unchecked: tests drive it from one task at a time, guarded by the lock.
    private let lock = NSLock()
    private var _isAvailable: Bool
    private var _table: [DisplaySpaces]
    private var _windowSpaces: [CGWindowID: [SpaceID]]

    public init(isAvailable: Bool = true, table: [DisplaySpaces] = [], windowSpaces: [CGWindowID: [SpaceID]] = [:]) {
        _isAvailable = isAvailable
        _table = table
        _windowSpaces = windowSpaces
    }

    public var isAvailable: Bool {
        get { lock.withLock { _isAvailable } }
        set { lock.withLock { _isAvailable = newValue } }
    }

    public var table: [DisplaySpaces] {
        get { lock.withLock { _table } }
        set { lock.withLock { _table = newValue } }
    }

    public var windowSpaces: [CGWindowID: [SpaceID]] {
        get { lock.withLock { _windowSpaces } }
        set { lock.withLock { _windowSpaces = newValue } }
    }

    public func spaceTable() -> [DisplaySpaces] {
        isAvailable ? table : []
    }

    public func spaces(of windows: [CGWindowID]) -> [CGWindowID: [SpaceID]] {
        guard isAvailable else { return [:] }
        let all = windowSpaces
        return Dictionary(uniqueKeysWithValues: windows.compactMap { id in all[id].map { (id, $0) } })
    }

    public func windowNumber(of element: AXUIElement) -> CGWindowID? {
        nil
    }
}
