// What the menu bar shows. The menu displays this state and sends commands; it makes no
// layout decisions itself (architecture TA-17, constitution technical rule 6).
import Foundation
import TileCore

/// The three icon states of UX-2. They differ by shape, never by colour.
public enum IconState: Sendable, Equatable {
    case active, paused, warning

    var symbolName: String {
        switch self {
        case .active: "rectangle.split.2x2"
        case .paused: "rectangle.dashed"
        case .warning: "exclamationmark.triangle"
        }
    }

    /// VoiceOver value of the status item (UX-14).
    var accessibilityValue: String {
        switch self {
        case .active: "Tiling is on"
        case .paused: "Tiling is paused"
        case .warning: "Needs permission"
        }
    }
}

/// One display in the "Window limit" submenu (UX-17).
public struct WindowLimitMenuEntry: Sendable, Equatable {
    public let displayUUID: String
    public let displayName: String
    public let limit: Int

    public init(displayUUID: String, displayName: String, limit: Int) {
        self.displayUUID = displayUUID
        self.displayName = displayName
        self.limit = limit
    }
}

public struct MenuState: Sendable, Equatable {
    public var icon: IconState
    /// The grey first line of the menu (UX-9).
    public var statusLine: String
    /// Windows that do not fit their tile; shown as a number next to the icon (UX-2).
    public var notFitCount: Int
    public var canTileNow: Bool
    /// Leads the menu with "Open Accessibility settings..." and greys window items (UX-5).
    public var needsPermission: Bool
    public var windowLimits: [WindowLimitMenuEntry]
    /// "Untile" is available whenever there is something to restore (US-24.6).
    public var canUntile: Bool
    /// Shows "Pause tiling" while running and "Resume tiling" while paused (UX-3, UX-4).
    public var isRunning: Bool

    public init(icon: IconState, statusLine: String, notFitCount: Int = 0, canTileNow: Bool, needsPermission: Bool = false,
                windowLimits: [WindowLimitMenuEntry] = [], canUntile: Bool = false, isRunning: Bool = false) {
        self.icon = icon
        self.statusLine = statusLine
        self.notFitCount = notFitCount
        self.canTileNow = canTileNow
        self.needsPermission = needsPermission
        self.windowLimits = windowLimits
        self.canUntile = canUntile
        self.isRunning = isRunning
    }
}

/// Commands the menu sends. The app wires them to the engine.
public struct MenuActions {
    public var tileNow: @MainActor () -> Void
    /// The menu is about to open: a good moment to refresh the window list (US-3.3).
    public var menuWillOpen: @MainActor () -> Void
    /// The user chose a window in the "Windows" submenu (US-3.4).
    public var raiseWindow: @MainActor (WindowID) -> Void
    /// The user picked a window limit for a display (US-31.2).
    public var setWindowLimit: @MainActor (String, Int) -> Void
    public var untile: @MainActor () -> Void
    public var togglePause: @MainActor () -> Void
    public var openAccessibilitySettings: @MainActor () -> Void
    public var dumpLayoutTrees: @MainActor () -> Void
    public var logSpaces: @MainActor () -> Void
    public var logWindows: @MainActor () -> Void
    public var frameWriteTest: @MainActor () -> Void
    public var diagnostics: @MainActor () -> String

    public init(
        tileNow: @escaping @MainActor () -> Void,
        menuWillOpen: @escaping @MainActor () -> Void = {},
        raiseWindow: @escaping @MainActor (WindowID) -> Void = { _ in },
        setWindowLimit: @escaping @MainActor (String, Int) -> Void = { _, _ in },
        untile: @escaping @MainActor () -> Void = {},
        togglePause: @escaping @MainActor () -> Void = {},
        openAccessibilitySettings: @escaping @MainActor () -> Void,
        dumpLayoutTrees: @escaping @MainActor () -> Void,
        logSpaces: @escaping @MainActor () -> Void = {},
        logWindows: @escaping @MainActor () -> Void = {},
        frameWriteTest: @escaping @MainActor () -> Void = {},
        diagnostics: @escaping @MainActor () -> String
    ) {
        self.tileNow = tileNow
        self.menuWillOpen = menuWillOpen
        self.raiseWindow = raiseWindow
        self.setWindowLimit = setWindowLimit
        self.untile = untile
        self.togglePause = togglePause
        self.openAccessibilitySettings = openAccessibilitySettings
        self.dumpLayoutTrees = dumpLayoutTrees
        self.logSpaces = logSpaces
        self.logWindows = logWindows
        self.frameWriteTest = frameWriteTest
        self.diagnostics = diagnostics
    }
}
