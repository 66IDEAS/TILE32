import Testing
import TileLog

/// Window titles appear in logs only in debug builds (TA-21, constitution technical rule 3).
/// Run in both configurations: `swift test` and `swift test -c release -Xswiftc -enable-testing`.
@Test func titlesAreHiddenOutsideDebugBuilds() {
    #if DEBUG
    #expect(Log.title("Inbox") == "Inbox")
    #else
    #expect(Log.title("Inbox") == "<title>")
    #endif
}
