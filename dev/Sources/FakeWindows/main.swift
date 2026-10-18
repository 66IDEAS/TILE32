// FakeWindows: opens windows with configurable behaviour, so the cases of US-10, US-11,
// US-21 and US-30 can be repeated on demand (architecture TA-24, task T-0.16).
//
// Buttons in the control window open each case. For scripted checks the same cases can be
// started from the command line, for example:
//   open -n FakeWindows.app --args --open normal,minsize --hang-after 2 --hang-seconds 8 --quit-after 15
import AppKit

@MainActor
final class FakeWindowsApp: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var counter = 0
    private var resizeTimers: [Timer] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        openControlWindow()
        runCommandLine()
        // Scripted runs stay in the background so they never take the owner's keyboard focus.
        if !CommandLine.arguments.contains("--open") { NSApp.activate() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Cases

    private struct Case {
        let key: String
        let title: String
        let action: @MainActor (FakeWindowsApp) -> Void
    }

    private let cases: [Case] = [
        Case(key: "normal", title: "Normal window") { $0.openWindow(kind: "Normal") },
        Case(key: "minsize", title: "Window with a minimum size (1800 x 1000)") {
            $0.openWindow(kind: "Minimum size").contentMinSize = NSSize(width: 1800, height: 1000)
        },
        Case(key: "delayed", title: "Window that appears after 3 seconds") { app in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { app.openWindow(kind: "Delayed") }
        },
        Case(key: "five", title: "Five windows at once") { app in
            for _ in 0..<5 { app.openWindow(kind: "Batch") }
        },
        Case(key: "splash", title: "Splash window that closes after 0.3 seconds") { app in
            let window = app.openWindow(kind: "Splash")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.close() }
        },
        Case(key: "dialog", title: "Free-standing alert (dialog)") { _ in
            let alert = NSAlert()
            alert.messageText = "FakeWindows dialog"
            alert.informativeText = "A free-standing alert. TILE32 must leave it floating."
            alert.runModal()
        },
        Case(key: "sheet", title: "Sheet on a new window") { app in
            let window = app.openWindow(kind: "With sheet")
            let alert = NSAlert()
            alert.messageText = "FakeWindows sheet"
            alert.beginSheetModal(for: window)
        },
        Case(key: "panel", title: "Floating tool panel") { app in app.openPanel() },
        Case(key: "save", title: "Save panel") { _ in
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "FakeWindows.txt"
            panel.begin { _ in }
        },
        Case(key: "selfresize", title: "Window that resizes itself every 3 seconds") { app in
            let window = app.openWindow(kind: "Resizes itself")
            var grow = true
            let timer = Timer(timeInterval: 3, repeats: true) { _ in
                MainActor.assumeIsolated {
                    var frame = window.frame
                    frame.size.width += grow ? 200 : -200
                    grow.toggle()
                    window.setFrame(frame, display: true)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            app.resizeTimers.append(timer)
        },
        Case(key: "fullscreen", title: "Window that toggles full screen") { app in
            let window = app.openWindow(kind: "Full screen")
            window.collectionBehavior.insert(.fullScreenPrimary)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { window.toggleFullScreen(nil) }
        },
        Case(key: "hang", title: "Hang for 10 seconds (no answers to any app)") { _ in
            Thread.sleep(forTimeInterval: 10)
        },
    ]

    // MARK: Windows

    private func openControlWindow() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for testCase in cases {
            let button = NSButton(title: testCase.title, target: self, action: #selector(runCase(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(testCase.key)
            stack.addArrangedSubview(button)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false
        )
        window.title = "FakeWindows control"
        window.contentView = stack
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
    }

    @discardableResult
    private func openWindow(kind: String) -> NSWindow {
        counter += 1
        let window = NSWindow(
            contentRect: NSRect(x: 120 + counter * 30, y: 200 + counter * 20, width: 640, height: 420),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "FakeWindows \(counter): \(kind)"
        window.isReleasedWhenClosed = false
        let label = NSTextField(labelWithString: "\(kind) #\(counter)")
        label.font = .systemFont(ofSize: 24)
        label.alignment = .center
        window.contentView = label
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        return window
    }

    private func openPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 300, width: 260, height: 180),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "FakeWindows tool panel"
        panel.isFloatingPanel = true
        panel.contentView = NSTextField(labelWithString: "Tool panel")
        panel.orderFront(nil)
        windows.append(panel)
    }

    @objc private func runCase(_ sender: NSButton) {
        guard let key = sender.identifier?.rawValue, let testCase = cases.first(where: { $0.key == key }) else { return }
        testCase.action(self)
    }

    // MARK: Command line

    private func runCommandLine() {
        let arguments = CommandLine.arguments
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        for key in value("--open")?.split(separator: ",").map(String.init) ?? [] {
            cases.first { $0.key == key }?.action(self)
        }
        if let delay = value("--hang-after").flatMap(Double.init) {
            let seconds = value("--hang-seconds").flatMap(Double.init) ?? 10
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { Thread.sleep(forTimeInterval: seconds) }
        }
        if let quit = value("--quit-after").flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + quit) { NSApp.terminate(nil) }
        }
    }
}

let app = NSApplication.shared
let delegate = FakeWindowsApp()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
