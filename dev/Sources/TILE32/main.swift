// TILE32 entry point. The menu-bar app and module wiring follow in T-0.10.
import AppKit
import TileGeometry
import TileLog

Log.ui.info("TILE32 started (scaffold)")
MainActor.assumeIsolated {
    _ = DisplayMonitor { _ in }
}
