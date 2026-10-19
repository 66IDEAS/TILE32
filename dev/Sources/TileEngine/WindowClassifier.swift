// Which windows are tiled and which float (architecture TA-10, US-21, US-22, US-30).
import CoreGraphics
import Foundation
import TileAX

/// Why a window is left alone. The menu shows these reasons (UX-6).
public enum FloatReason: String, Sendable, Equatable, CaseIterable {
    case dialog
    case panel
    case excludedApp = "excluded app"
    case fullScreen = "full screen"
    case tooSmall = "too small"
    case notResizable = "not resizable"
    /// A further window of an app whose main windows are known, for example a new email.
    case popUp = "pop-up window"
}

public enum Classification: Sendable, Equatable {
    case tiled
    case floating(FloatReason)
    /// Minimised windows leave the layout but are not floating and not an error (US-8.3).
    case minimised
}

public enum WindowClassifier {
    /// Tiny helper windows are never tiled (TA-10 rule 5).
    public static let minimumSize = CGSize(width: 200, height: 120)

    private static let dialogSubroles: Set<String> = ["AXDialog", "AXSystemDialog"]
    /// Open and save panels report an ordinary standard window, but carry these
    /// identifiers (found in T-3.1 with FakeWindows).
    private static let dialogIdentifiers: Set<String> = ["save-panel", "open-panel"]
    /// Apps whose main windows carry an identifier. Every other window of such an app floats
    /// as a pop-up window. Outlook marks its mail and calendar windows "OutlookWindow"; a new
    /// email, a new event or a message opened on its own has no identifier (found on the
    /// owner's Mac on 2026-10-19: a new email joined the layout and everything re-flowed).
    static let mainWindowIdentifiers: [String: Set<String>] = [
        "com.microsoft.Outlook": ["OutlookWindow"],
    ]

    /// Rule 1 (regular apps only) is applied by discovery: other apps are never read.
    public static func classify(_ window: WindowSnapshot, excludedBundleIDs: Set<String> = []) -> Classification {
        if let bundleID = window.app.bundleID, excludedBundleIDs.contains(bundleID) {
            return .floating(.excludedApp)
        }
        if window.isMinimized { return .minimised }
        if window.isFullScreen { return .floating(.fullScreen) }
        if window.isModal || dialogSubroles.contains(window.subrole ?? "") || dialogIdentifiers.contains(window.identifier ?? "") {
            return .floating(.dialog)
        }
        if let bundleID = window.app.bundleID, let main = mainWindowIdentifiers[bundleID],
           !main.contains(window.identifier ?? "") {
            return .floating(.popUp)
        }
        // Rule 2: only standard windows. Floating panels, sheets, popovers and unknown
        // helper windows all fall out here.
        guard window.role == "AXWindow", window.subrole == "AXStandardWindow" else { return .floating(.panel) }
        if !window.isResizable { return .floating(.notResizable) }
        if let frame = window.frame, frame.width < minimumSize.width || frame.height < minimumSize.height {
            return .floating(.tooSmall)
        }
        return .tiled
    }
}
