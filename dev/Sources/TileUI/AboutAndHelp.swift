// "About TILE32" and "TILE32 Help" (UX-18). The brand files are copied from the 66ideas
// brand kit into Resources/Brand by sync-brand.sh.
import AppKit
import TileLog

/// Links that leave the app. Help points to the website once it exists.
public enum AppLinks {
    /// Set this when the website is online; until then Help opens the bundled page.
    public static let website: URL? = nil
}

@MainActor
public enum AboutPanel {
    /// The standard About panel with the app icon, name, version and build from the bundle,
    /// and the 66ideas logo in the credits, in the variant for the current appearance.
    public static func show() {
        NSApp.activate()
        var options: [NSApplication.AboutPanelOptionKey: Any] = [.credits: credits()]
        if let icon = NSImage(named: "AppIcon") { options[.applicationIcon] = icon }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    private static func credits() -> NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        let text = NSMutableAttributedString()

        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let name = dark ? "66ideas-lockup-dark" : "66ideas-lockup-light"
        if let url = Bundle.main.url(forResource: name, withExtension: "svg"), let logo = NSImage(contentsOf: url) {
            let width: CGFloat = 160
            logo.size = NSSize(width: width, height: width * logo.size.height / max(logo.size.width, 1))
            let attachment = NSTextAttachment()
            attachment.image = logo
            attachment.bounds = CGRect(origin: .zero, size: logo.size)
            logo.accessibilityDescription = "66ideas"
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: "\n\n"))
        }
        text.append(NSAttributedString(string: "Your windows side by side, arranged with the mouse.", attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        text.addAttribute(.paragraphStyle, value: centred, range: NSRange(location: 0, length: text.length))
        return text
    }
}

@MainActor
public enum HelpPage {
    /// Opens the website when it is set, otherwise the help page inside the app.
    public static func open() {
        if let website = AppLinks.website {
            NSWorkspace.shared.open(website)
        } else if let page = Bundle.main.url(forResource: "Help", withExtension: "html") {
            NSWorkspace.shared.open(page)
        } else {
            Log.ui.error("The help page is missing from the app bundle")
        }
    }
}
