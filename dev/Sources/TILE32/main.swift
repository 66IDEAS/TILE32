// TILE32 entry point: a menu-bar app with no Dock icon and no main window (US-1, TA-17).
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
