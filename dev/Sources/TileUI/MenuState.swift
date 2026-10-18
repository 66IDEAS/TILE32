// What the menu bar shows. The menu displays this state and sends commands; it makes no
// layout decisions itself (architecture TA-17, constitution technical rule 6).
import Foundation

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

public struct MenuState: Sendable, Equatable {
    public var icon: IconState
    /// The grey first line of the menu (UX-9).
    public var statusLine: String
    /// Windows that do not fit their tile; shown as a number next to the icon (UX-2).
    public var notFitCount: Int
    public var canTileNow: Bool
    /// Leads the menu with "Open Accessibility settings..." and greys window items (UX-5).
    public var needsPermission: Bool

    public init(icon: IconState, statusLine: String, notFitCount: Int = 0, canTileNow: Bool, needsPermission: Bool = false) {
        self.icon = icon
        self.statusLine = statusLine
        self.notFitCount = notFitCount
        self.canTileNow = canTileNow
        self.needsPermission = needsPermission
    }
}

/// Commands the menu sends. The app wires them to the engine.
public struct MenuActions {
    public var tileNow: @MainActor () -> Void
    public var openAccessibilitySettings: @MainActor () -> Void
    public var dumpLayoutTrees: @MainActor () -> Void
    public var logSpaces: @MainActor () -> Void
    public var logWindows: @MainActor () -> Void
    public var diagnostics: @MainActor () -> String

    public init(
        tileNow: @escaping @MainActor () -> Void,
        openAccessibilitySettings: @escaping @MainActor () -> Void,
        dumpLayoutTrees: @escaping @MainActor () -> Void,
        logSpaces: @escaping @MainActor () -> Void = {},
        logWindows: @escaping @MainActor () -> Void = {},
        diagnostics: @escaping @MainActor () -> String
    ) {
        self.tileNow = tileNow
        self.openAccessibilitySettings = openAccessibilitySettings
        self.dumpLayoutTrees = dumpLayoutTrees
        self.logSpaces = logSpaces
        self.logWindows = logWindows
        self.diagnostics = diagnostics
    }
}
