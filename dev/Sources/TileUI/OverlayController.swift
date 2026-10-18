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

    public init() {}

    /// The label of a drop target, exactly as in UX-11.
    public static func label(for target: DropTarget) -> String {
        switch target {
        case .emptyLayout: "Move to this display"
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
    }

    public func hide() {
        if let shownOn { panels[shownOn]?.orderOut(nil) }
        shownOn = nil
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

    func update(area: CGRect, label: String) {
        self.area = area
        self.label = label
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !area.isEmpty else { return }
        let highContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let accent = NSColor.controlAccentColor
        let box = area.insetBy(dx: Self.inset, dy: Self.inset)
        let path = NSBezierPath(roundedRect: box, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        accent.withAlphaComponent(dark ? 0.25 : 0.18).setFill()
        path.fill()
        let border = highContrast ? 4.0 : 3.0
        let stroke = NSBezierPath(roundedRect: box.insetBy(dx: border / 2, dy: border / 2),
                                  xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        stroke.lineWidth = border
        accent.setStroke()
        stroke.stroke()
        drawLabel(in: box, color: highContrast ? .labelColor : accent)
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
