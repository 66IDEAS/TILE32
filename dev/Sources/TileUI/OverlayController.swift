// The drop-zone overlay (US-16, architecture TA-15, UX-10, UX-11): one transparent,
// click-through panel per display that draws where a dragged window will go.
import AppKit
import TileCore
import TileGeometry
import TileLog

@MainActor
public final class OverlayController {
    private var panels: [DisplayID: NSPanel] = [:]
    private var shownOn: DisplayID?
    private var lastAnnounced = ""

    public init() {}

    /// The label of a drop target, exactly as in UX-11.
    public static func label(for target: DropTarget) -> String {
        switch target {
        case .emptyLayout: "Move to this display"
        case .displayEdge(let edge, _): edge == .left ? "Full height on the left" : "Full height on the right"
        case .window(_, let zone, _):
            switch zone {
            case .center: "Swap places"
            case .left: "Place on the left"
            case .right: "Place on the right"
            case .top: "Place above"
            case .bottom: "Place below"
            }
        }
    }

    /// Shows the highlight for `area` (Accessibility coordinates) on its display, with a label.
    public func show(area: CGRect, label: String, on display: Display, table: DisplayTable) {
        if let shownOn, shownOn != display.id { panels[shownOn]?.orderOut(nil) }
        let panel = panels[display.id] ?? makePanel()
        panels[display.id] = panel
        let screenFrame = table.appKitRect(fromAX: display.frame)
        if panel.frame != screenFrame { panel.setFrame(screenFrame, display: false) }
        let areaInScreen = table.appKitRect(fromAX: area)
        let local = CGRect(x: areaInScreen.minX - screenFrame.minX, y: areaInScreen.minY - screenFrame.minY,
                           width: areaInScreen.width, height: areaInScreen.height)
        (panel.contentView as? OverlayView)?.update(area: local, label: label)
        panel.orderFrontRegardless()
        shownOn = display.id
        announce(label)
    }

    /// Only the label pill, centred in `area`, without a highlight: the share while resizing (UX-16).
    public func showLabel(_ label: String, centredIn area: CGRect, on display: Display, table: DisplayTable) {
        show(area: area, label: label, on: display, table: table)
        (panels[display.id]?.contentView as? OverlayView)?.labelOnly = true
        panels[display.id]?.contentView?.needsDisplay = true
    }

    public func hide() {
        if let shownOn { panels[shownOn]?.orderOut(nil) }
        shownOn = nil
        lastAnnounced = ""
    }

    /// VoiceOver hears each new label once, politely (UX-14, UQ-2). The panel itself stays
    /// hidden from VoiceOver.
    private func announce(_ label: String) {
        guard label != lastAnnounced else { return }
        lastAnnounced = label
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: label,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.contentView = OverlayView()
        panel.setAccessibilityElement(false)
        return panel
    }
}

/// Draws the highlight and the label pill (UX-10). No animation (UX-10, Reduce Motion).
final class OverlayView: NSView {
    private var area: CGRect = .zero
    private var label = ""

    /// The highlight sits 3 points inside the tile, half the gap (UX-10).
    static let inset: CGFloat = 3
    static let cornerRadius: CGFloat = 10

    /// True while resizing: only the percentage pill is drawn (UX-16).
    var labelOnly = false

    func update(area: CGRect, label: String) {
        self.area = area
        self.label = label
        labelOnly = false
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !area.isEmpty else { return }
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = NSColor.controlAccentColor
        let box = area.insetBy(dx: Self.inset, dy: Self.inset)
        if labelOnly {
            drawLabel(in: box, color: highContrast ? .labelColor : Self.readableLabelColor(accent: accent))
            return
        }
        let path = NSBezierPath(roundedRect: box, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        accent.withAlphaComponent(dark ? 0.25 : 0.18).setFill()
        path.fill()
        let border = highContrast ? 4.0 : 3.0
        let stroke = NSBezierPath(roundedRect: box.insetBy(dx: border / 2, dy: border / 2),
                                  xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        stroke.lineWidth = border
        accent.setStroke()
        stroke.stroke()
        drawLabel(in: box, color: highContrast ? .labelColor : Self.readableLabelColor(accent: accent))
    }

    /// The accent colour when it reads well on the pill (contrast at least 4.5:1, WCAG AA),
    /// otherwise the primary text colour (UX-14, UQ-3).
    static func readableLabelColor(accent: NSColor) -> NSColor {
        let pill = NSColor.windowBackgroundColor
        return contrast(accent, pill) >= 4.5 ? accent : .labelColor
    }

    static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    static func luminance(_ color: NSColor) -> Double {
        guard let rgb = color.usingColorSpace(.sRGB) else { return 0.5 }
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
    }

    /// 13 point semibold on a pill; wraps to two lines when narrow, hidden when it still
    /// does not fit (UX-10).
    private func drawLabel(in box: CGRect, color: NSColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let padding = CGSize(width: 12, height: 6)
        let maxWidth = box.width - 16 - 2 * padding.width
        guard maxWidth > 20 else { return }
        var size = text.boundingRect(with: CGSize(width: maxWidth, height: 200), options: [.usesLineFragmentOrigin]).size
        size = CGSize(width: ceil(size.width), height: ceil(size.height))
        guard size.height <= 40, size.height + 2 * padding.height <= box.height - 8 else { return }
        let pill = CGRect(x: box.midX - size.width / 2 - padding.width, y: box.midY - size.height / 2 - padding.height,
                          width: size.width + 2 * padding.width, height: size.height + 2 * padding.height)
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        text.draw(with: CGRect(x: pill.minX + padding.width, y: pill.minY + padding.height, width: size.width, height: size.height),
                  options: [.usesLineFragmentOrigin])
    }
}
