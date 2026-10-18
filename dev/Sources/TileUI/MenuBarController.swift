// The status item and its menu (architecture TA-17, UX-2, UX-3, UX-14).
import AppKit
import TileLog

@MainActor
public final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let actions: MenuActions
    private var state: MenuState

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

        #if DEBUG
        menu.addItem(debugItem())
        #endif
        menu.addItem(ActionMenuItem(title: "Quit TILE32") {
            Log.ui.info("Quit chosen from the menu")
            NSApp.terminate(nil)
        })
    }

    /// Filled with real windows in task T-0.23. Until then it shows the empty state of UX-6.
    private func windowsItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Windows", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.addItem(disabledItem("No windows to arrange"))
        item.submenu = submenu
        // Grey while the permission is missing (UX-6).
        item.isEnabled = !state.needsPermission
        return item
    }

    #if DEBUG
    private func debugItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(ActionMenuItem(title: "Dump layout trees") { [actions] in actions.dumpLayoutTrees() })
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
