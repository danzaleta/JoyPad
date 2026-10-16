#if os(macOS)
import Foundation
import CoreGraphics
import AppKit
import JoyPadProtocol

/// High-precision macOS Trackpad & Gesture synthesis engine built on CoreGraphics (`CGEvent`).
@MainActor
public final class TrackpadInjectionEngine {
    public var sensitivity: Double = 1.35
    private var subPixelRemainderX: Double = 0.0
    private var subPixelRemainderY: Double = 0.0
    private var isDragLocked: Bool = false

    public init() {}

    /// Applies a macOS-like ballistic acceleration curve and injects cursor delta + 2-finger scroll.
    public func handleMotion(_ motion: TrackpadMotionPayload) {
        // 1. Cursor Movement
        if motion.deltaXScaled != 0 || motion.deltaYScaled != 0 {
            let rawDX = motion.deltaX
            let rawDY = motion.deltaY
            let speed = hypot(rawDX, rawDY)
            let accelMultiplier = sensitivity * (1.0 + min(speed * 0.08, 2.2))

            let totalDX = rawDX * accelMultiplier + subPixelRemainderX
            let totalDY = rawDY * accelMultiplier + subPixelRemainderY

            let moveX = totalDX.rounded(.towardZero)
            let moveY = totalDY.rounded(.towardZero)
            subPixelRemainderX = totalDX - moveX
            subPixelRemainderY = totalDY - moveY

            let currentPos = NSEvent.mouseLocation
            // Convert AppKit bottom-left origin to Quartz top-left screen coordinates
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
            let quartzX = currentPos.x + moveX
            let quartzY = (primaryHeight - currentPos.y) + moveY
            let newPoint = CGPoint(x: quartzX, y: quartzY)

            let eventType: CGEventType = isDragLocked ? .leftMouseDragged : .mouseMoved
            if let event = CGEvent(
                mouseEventSource: nil,
                mouseType: eventType,
                mouseCursorPosition: newPoint,
                mouseButton: .left
            ) {
                event.setIntegerValueField(.mouseEventDeltaX, value: Int64(moveX))
                event.setIntegerValueField(.mouseEventDeltaY, value: Int64(moveY))
                event.post(tap: .cghidEventTap)
            }
        }

        // 2. Two-Finger Smooth Pixel Scroll
        if motion.scrollDeltaX != 0 || motion.scrollDeltaY != 0 {
            if let scrollEvent = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(motion.scrollDeltaY),
                wheel2: Int32(motion.scrollDeltaX),
                wheel3: 0
            ) {
                scrollEvent.post(tap: .cghidEventTap)
            }
        }
    }

    /// Injects discrete trackpad clicks, drag-lock, and 3-finger macOS system gestures.
    public func handleGesture(_ gesture: TrackpadGesturePayload) {
        if gesture.systemGesture != .none {
            triggerSystemGesture(gesture.systemGesture)
            return
        }

        let currentPos = currentQuartzCursorLocation()
        let isRight = gesture.buttonMask.contains(.right)
        let mouseButton: CGMouseButton = isRight ? .right : .left
        let downType: CGEventType = isRight ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = isRight ? .rightMouseUp : .leftMouseUp

        isDragLocked = gesture.buttonMask.contains(.dragLock)

        switch gesture.action {
        case .press:
            postMouseButton(type: downType, button: mouseButton, at: currentPos, clickCount: 1)
        case .release:
            postMouseButton(type: upType, button: mouseButton, at: currentPos, clickCount: 1)
        case .tapClick, .forceClick:
            postMouseButton(type: downType, button: mouseButton, at: currentPos, clickCount: 1)
            postMouseButton(type: upType, button: mouseButton, at: currentPos, clickCount: 1)
        case .doubleClick:
            postMouseButton(type: downType, button: mouseButton, at: currentPos, clickCount: 1)
            postMouseButton(type: upType, button: mouseButton, at: currentPos, clickCount: 1)
            postMouseButton(type: downType, button: mouseButton, at: currentPos, clickCount: 2)
            postMouseButton(type: upType, button: mouseButton, at: currentPos, clickCount: 2)
        }
    }

    private func postMouseButton(
        type: CGEventType,
        button: CGMouseButton,
        at point: CGPoint,
        clickCount: Int64
    ) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        ) else { return }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.post(tap: .cghidEventTap)
    }

    private func triggerSystemGesture(_ gesture: SystemGesture) {
        // Standard macOS symbolic shortcuts: Ctrl + Arrow keys for Mission Control / Spaces
        let keyCode: CGKeyCode
        switch gesture {
        case .none: return
        case .missionControl: keyCode = 126 // Control + Up Arrow
        case .appExpose:      keyCode = 125 // Control + Down Arrow
        case .spaceLeft:      keyCode = 123 // Control + Left Arrow
        case .spaceRight:     keyCode = 124 // Control + Right Arrow
        case .showDesktop:    keyCode = 103 // F11 Show Desktop
        }

        let flags: CGEventFlags = (gesture == .showDesktop) ? [] : .maskControl
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    private func currentQuartzCursorLocation() -> CGPoint {
        let pos = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        return CGPoint(x: pos.x, y: primaryHeight - pos.y)
    }
}
#endif
