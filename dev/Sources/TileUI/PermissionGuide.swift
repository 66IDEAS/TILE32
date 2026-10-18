// The first-run permission explanation (UX-8, US-2.1). The only window TILE32 opens on its own.
import AppKit
import TileLog

@MainActor
public enum PermissionGuide {
    public enum Choice: Sendable {
        case openSettings, notNow
    }

    /// Shows the alert with the exact wording of UX-8 and returns the user's choice.
    public static func ask() -> Choice {
        let alert = NSAlert()
        alert.messageText = "TILE32 needs permission to move windows"
        alert.informativeText = """
            To arrange your windows, macOS must let TILE32 control them. TILE32 only reads window \
            positions, sizes and titles. It never records your screen, reads what is in a window, \
            or uses the internet.

            In System Settings, open Privacy & Security > Accessibility and switch on TILE32. \
            You do not need to restart it.

            TILE32 starts paused. When you are ready, choose Resume tiling from its menu.
            """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Not now")

        // An agent app has no window of its own; bring the alert to the front.
        NSApp.activate()
        let choice: Choice = alert.runModal() == .alertFirstButtonReturn ? .openSettings : .notNow
        Log.ui.info("Permission alert answered: \(choice == .openSettings ? "Open System Settings" : "Not now", privacy: .public)")
        return choice
    }
}
