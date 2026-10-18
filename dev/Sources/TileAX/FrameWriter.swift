// Writing window frames (architecture TA-11). Blocking; runs on the app's queue.
import ApplicationServices
import CoreGraphics
import Foundation
import TileLog

public struct FrameWriteResult: Sendable {
    public let requested: CGRect
    /// The frame read back after writing, or nil if it could not be read.
    public let actual: CGRect?
    public let positionError: AXError
    public let sizeError: AXError
    public let duration: Duration

    /// The window stayed larger than requested: it has a minimum size (US-10). 2 point tolerance.
    public var doesNotFit: Bool {
        guard let actual else { return false }
        return actual.width > requested.width + 2 || actual.height > requested.height + 2
    }

    /// Position and size match within 2 points.
    public var matches: Bool {
        guard let actual else { return false }
        return abs(actual.minX - requested.minX) <= 2 && abs(actual.minY - requested.minY) <= 2
            && abs(actual.width - requested.width) <= 2 && abs(actual.height - requested.height) <= 2
    }
}

public enum FrameWriter {
    /// Writes size, position, size, then reads the frame back. The second size write makes
    /// windows grow correctly at display edges and when moving between displays (TA-11).
    /// With `disableEnhancedUI`, the app's `AXEnhancedUserInterface` is switched off for the
    /// write and restored afterwards, a known workaround for apps that animate (spike S2).
    public static func write(_ frame: CGRect, to window: AXElementBox, pid: pid_t, disableEnhancedUI: Bool = false) -> FrameWriteResult {
        let clock = ContinuousClock()
        let start = clock.now
        let element = window.element
        AXUIElementSetMessagingTimeout(element, AXWorker.messagingTimeout)

        let app = AXUIElementCreateApplication(pid)
        var restoreEnhancedUI = false
        if disableEnhancedUI, AXRead.bool(app, "AXEnhancedUserInterface") == true {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse)
            restoreEnhancedUI = true
        }

        var size = frame.size
        var origin = frame.origin
        var sizeError = setValue(element, kAXSizeAttribute, AXValueCreate(.cgSize, &size))
        let positionError = setValue(element, kAXPositionAttribute, AXValueCreate(.cgPoint, &origin))
        let secondSizeError = setValue(element, kAXSizeAttribute, AXValueCreate(.cgSize, &size))
        if sizeError == .success { sizeError = secondSizeError }

        if restoreEnhancedUI {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }

        let actual = AXRead.point(element, kAXPositionAttribute).flatMap { point in
            AXRead.size(element, kAXSizeAttribute).map { CGRect(origin: point, size: $0) }
        }
        return FrameWriteResult(requested: frame, actual: actual, positionError: positionError,
                                sizeError: sizeError, duration: clock.now - start)
    }

    private static func setValue(_ element: AXUIElement, _ attribute: String, _ value: AXValue?) -> AXError {
        guard let value else { return .illegalArgument }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value)
    }
}
