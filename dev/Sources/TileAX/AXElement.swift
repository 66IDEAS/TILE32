// Accessibility element access (architecture TA-9, TA-13).
import ApplicationServices
import CoreGraphics
import Foundation

/// A Sendable wrapper for an Accessibility element. `AXUIElement` is not Sendable; the box
/// is only used on the owning app's queue (TA-13). Equality and hashing follow `CFEqual`
/// and `CFHash`, which identify the same window across different references (TA-20).
public struct AXElementBox: @unchecked Sendable, Hashable {
    public let element: AXUIElement

    public init(_ element: AXUIElement) {
        self.element = element
    }

    public static func == (lhs: AXElementBox, rhs: AXElementBox) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(CFHash(element))
    }
}

/// Typed attribute reads. All of these block until the app answers or the messaging
/// timeout ends, so they run on the app's queue, never on the main thread.
enum AXRead {
    static func raw(_ element: AXUIElement, _ attribute: String) -> (AXError, CFTypeRef?) {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return (error, value)
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        raw(element, attribute).1 as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (raw(element, attribute).1 as? NSNumber)?.boolValue
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> (AXError, [AXUIElement]) {
        let (error, value) = raw(element, attribute)
        return (error, value as? [AXUIElement] ?? [])
    }

    static func point(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = axValue(element, attribute, type: .cgPoint) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    static func size(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = axValue(element, attribute, type: .cgSize) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success && settable.boolValue
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String, type: AXValueType) -> AXValue? {
        guard let value = raw(element, attribute).1, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        return AXValueGetType(axValue) == type ? axValue : nil
    }
}
