import ApplicationServices
import CoreGraphics
import Testing
@testable import TileAX
@testable import TileEngine

private func window(
    bundleID: String? = "com.example.app",
    role: String? = "AXWindow",
    subrole: String? = "AXStandardWindow",
    frame: CGRect? = CGRect(x: 0, y: 30, width: 1200, height: 800),
    minimised: Bool = false,
    fullScreen: Bool = false,
    modal: Bool = false,
    resizable: Bool = true,
    identifier: String? = nil
) -> WindowSnapshot {
    WindowSnapshot(
        app: AppInfo(pid: 4242, bundleID: bundleID, name: "Example"),
        element: AXElementBox(AXUIElementCreateApplication(4242)),
        windowNumber: 1, role: role, subrole: subrole, title: "", frame: frame,
        isMinimized: minimised, isFullScreen: fullScreen, isModal: modal, isResizable: resizable,
        identifier: identifier
    )
}

@Suite("Window classification (TA-10)")
struct WindowClassifierTests {
    @Test func standardResizableWindowIsTiled() {
        #expect(WindowClassifier.classify(window()) == .tiled)
    }

    @Test(arguments: ["AXDialog", "AXSystemDialog"])
    func dialogsFloat(subrole: String) {
        #expect(WindowClassifier.classify(window(subrole: subrole)) == .floating(.dialog))
    }

    @Test func modalWindowsFloatAsDialogs() {
        #expect(WindowClassifier.classify(window(modal: true)) == .floating(.dialog))
    }

    @Test(arguments: ["AXFloatingWindow", "AXSystemFloatingWindow", "AXUnknown"])
    func panelsAndHelpersFloat(subrole: String) {
        #expect(WindowClassifier.classify(window(subrole: subrole)) == .floating(.panel))
    }

    @Test func missingSubroleFloats() {
        #expect(WindowClassifier.classify(window(subrole: nil)) == .floating(.panel))
        #expect(WindowClassifier.classify(window(role: "AXSheet")) == .floating(.panel))
    }

    @Test func fixedSizeWindowsFloat() {
        #expect(WindowClassifier.classify(window(resizable: false)) == .floating(.notResizable))
    }

    @Test func tinyWindowsFloat() {
        #expect(WindowClassifier.classify(window(frame: CGRect(x: 0, y: 0, width: 199, height: 600))) == .floating(.tooSmall))
        #expect(WindowClassifier.classify(window(frame: CGRect(x: 0, y: 0, width: 600, height: 119))) == .floating(.tooSmall))
        #expect(WindowClassifier.classify(window(frame: CGRect(x: 0, y: 0, width: 200, height: 120))) == .tiled)
    }

    @Test func fullScreenWindowsFloat() {
        #expect(WindowClassifier.classify(window(fullScreen: true)) == .floating(.fullScreen))
    }

    @Test func minimisedWindowsAreNeitherTiledNorFloating() {
        #expect(WindowClassifier.classify(window(minimised: true)) == .minimised)
    }

    @Test func excludedAppsFloatFirst() {
        let excluded: Set<String> = ["us.zoom.xos"]
        #expect(WindowClassifier.classify(window(bundleID: "us.zoom.xos", minimised: true), excludedBundleIDs: excluded) == .floating(.excludedApp))
        #expect(WindowClassifier.classify(window(bundleID: "com.apple.Safari"), excludedBundleIDs: excluded) == .tiled)
    }

    @Test func outlookMainWindowsAreTiledAndItsOtherWindowsFloat() {
        let outlook = "com.microsoft.Outlook"
        #expect(WindowClassifier.classify(window(bundleID: outlook, identifier: "OutlookWindow")) == .tiled)
        #expect(WindowClassifier.classify(window(bundleID: outlook)) == .floating(.popUp))
        #expect(WindowClassifier.classify(window(bundleID: outlook, identifier: "something-else")) == .floating(.popUp))
        // Other apps are not affected by the rule.
        #expect(WindowClassifier.classify(window(bundleID: "com.apple.mail")) == .tiled)
    }

    @Test(arguments: ["save-panel", "open-panel"])
    func openAndSavePanelsFloatAsDialogsEvenWhenResizable(identifier: String) {
        #expect(WindowClassifier.classify(window(identifier: identifier)) == .floating(.dialog))
    }
}
