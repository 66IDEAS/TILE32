// TileLog: one logger per category under the app's subsystem (architecture TA-23).
// Kept out of TileCore, which must not import `os` (constitution, technical rule 4).
import os

public enum Log {
    public static let subsystem = "com.66ideas.tile32"

    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let ax = Logger(subsystem: subsystem, category: "ax")
    public static let drag = Logger(subsystem: subsystem, category: "drag")
    public static let resize = Logger(subsystem: subsystem, category: "resize")
    public static let spaces = Logger(subsystem: subsystem, category: "spaces")
    public static let layout = Logger(subsystem: subsystem, category: "layout")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Window titles are logged only in debug builds (TA-21, constitution technical rule 3).
    public static func title(_ title: String) -> String {
        #if DEBUG
        title
        #else
        "<title>"
        #endif
    }
}
