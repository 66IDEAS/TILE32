// The status item and its menu (architecture TA-17, UX-2, UX-3, UX-14).
import AppKit
import TileCore
import TileEngine
import TileLog

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let actions: MenuActions
    private var state: MenuState
    /// Kept across rebuilds so it can be refreshed while the menu is open.
    private let windowsSubmenu = NSMenu()
    private var windowContent = WindowMenuContent.empty

    public init(state: MenuState, actions: MenuActions) {
        self.state = state
        self.actions = actions
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel("TILE32")
        statusItem.button?.setAccessibilityHelp("Opens the TILE32 menu")
        applyIcon()
    }

    /// New window list; updates the submenu in place, also while it is open.
    public func setWindowContent(_ content: WindowMenuContent) {
        guard content != windowContent else { return }
        windowContent = content
        fillWindowsSubmenu()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        actions.menuWillOpen()
    }

    public func update(_ newState: MenuState) {
        guard newState != state else { return }
        state = newState
        applyIcon()
    }

    // MARK: Icon

    private func applyIcon() {
        guard let button = statusItem.button else { return }
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let image = NSImage(systemSymbolName: state.icon.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        // The only badge: how many windows do not fit their tile (UX-2).
        button.title = state.notFitCount > 0 ? " \(state.notFitCount)" : ""
        button.setAccessibilityValue(state.icon.accessibilityValue)
    }

    // MARK: Menu, rebuilt every time it opens (US-3.3)

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(disabledItem(state.statusLine))
        menu.addItem(.separator())

        if state.needsPermission {
            menu.addItem(ActionMenuItem(title: "Open Accessibility settings...") { [actions] in
                actions.openAccessibilitySettings()
            })
            menu.addItem(.separator())
        }

        let tileNow = ActionMenuItem(title: "Tile now") { [actions] in actions.tileNow() }
        tileNow.isEnabled = state.canTileNow
        menu.addItem(tileNow)
        menu.addItem(windowsItem())
        menu.addItem(.separator())
        menu.addItem(windowLimitItem())
        menu.addItem(.separator())

        #if DEBUG
        menu.addItem(debugItem())
        #endif
        menu.addItem(ActionMenuItem(title: "Quit TILE32") {
            Log.ui.info("Quit chosen from the menu")
            NSApp.terminate(nil)
        })
    }

    private func windowsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        windowsSubmenu.autoenablesItems = false
        fillWindowsSubmenu()
        item.submenu = windowsSubmenu
        // Grey while the permission is missing (UX-6).
        item.isEnabled = !state.needsPermission
        return item
    }

    /// Display groups with headers, then floating windows, then the count on other Spaces (UX-6).
    private func fillWindowsSubmenu() {
        windowsSubmenu.removeAllItems()
        if windowContent.isEmpty {
            windowsSubmenu.addItem(disabledItem("No windows to arrange"))
        }
        for section in windowContent.sections {
            windowsSubmenu.addItem(NSMenuItem.sectionHeader(title: section.header))
            for entry in section.entries { windowsSubmenu.addItem(windowItem(entry)) }
        }
        if !windowContent.floating.isEmpty {
            windowsSubmenu.addItem(NSMenuItem.sectionHeader(title: "Floating"))
            for entry in windowContent.floating { windowsSubmenu.addItem(windowItem(entry)) }
        }
        if windowContent.otherSpacesCount > 0 {
            let count = windowContent.otherSpacesCount
            windowsSubmenu.addItem(.separator())
            windowsSubmenu.addItem(disabledItem("\(count) \(count == 1 ? "window" : "windows") on other Spaces"))
        }
    }

    /// One group per display with the choices 2 to 16 (UX-17).
    private func windowLimitItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Window limit", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for entry in state.windowLimits {
            submenu.addItem(NSMenuItem.sectionHeader(title: entry.displayName))
            for value in 2...16 {
                let choice = ActionMenuItem(title: "\(value)") { [actions] in actions.setWindowLimit(entry.displayUUID, value) }
                choice.state = value == entry.limit ? .on : .off
                choice.indentationLevel = 1
                submenu.addItem(choice)
            }
        }
        item.submenu = submenu
        item.isEnabled = !state.needsPermission && !state.windowLimits.isEmpty
        return item
    }

    private func windowItem(_ entry: WindowMenuEntry) -> NSMenuItem {
        let item = ActionMenuItem(title: entry.text) { [actions] in actions.raiseWindow(entry.id) }
        item.indentationLevel = 1
        return item
    }

    #if DEBUG
    private func debugItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(ActionMenuItem(title: "Dump layout trees") { [actions] in actions.dumpLayoutTrees() })
        submenu.addItem(ActionMenuItem(title: "Log Spaces") { [actions] in actions.logSpaces() })
        submenu.addItem(ActionMenuItem(title: "Log windows") { [actions] in actions.logWindows() })
        submenu.addItem(.separator())
        // Moves windows: only when the owner agrees (working agreement 1).
        submenu.addItem(ActionMenuItem(title: "Frame write test (moves windows)") { [actions] in actions.frameWriteTest() })
        submenu.addItem(ActionMenuItem(title: "Copy diagnostics") { [actions] in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(actions.diagnostics(), forType: .string)
            Log.ui.info("Diagnostics copied to the clipboard")
        })
        item.submenu = submenu
        return item
    }
    #endif

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// A menu item that runs a closure, so menus can be built without selectors per command.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(title: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("not used")
    }

    @objc private func fire() {
        handler()
    }
}
