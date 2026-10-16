#if os(macOS)
import Foundation
import CoreGraphics
import AppKit
import JoyPadProtocol

/// High-precision macOS Trackpad & Gesture synthesis engine built on CoreGraphics (`CGEvent`).
@MainActor
public final class TrackpadInjectionEngine {
    public var sensitivity: Double = 1.35

    /// Continuous floating-point cursor position to prevent `NSEvent.mouseLocation` stale-read stutter at 120Hz.
    private var virtualCursorLocation: CGPoint? = nil
    private var lastMotionTimestamp: TimeInterval = 0
    private var isDragLocked: Bool = false

    public init() {}

    /// Applies a smooth ballistic curve and injects sub-pixel cursor movement, 2-finger scroll, and pinch zoom.
    public func handleMotion(_ motion: TrackpadMotionPayload) {
        let now = ProcessInfo.processInfo.systemUptime

        // 1. Sub-pixel Cursor Movement (Zero-Stutter Floating-Point Accumulator)
        if motion.deltaXScaled != 0 || motion.deltaYScaled != 0 {
            let rawDX = motion.deltaX
            let rawDY = motion.deltaY
            let speed = hypot(rawDX, rawDY)
            let accelMultiplier = sensitivity * (1.0 + min(speed * 0.045, 1.8))

            let dx = rawDX * accelMultiplier
            let dy = rawDY * accelMultiplier

            // Resync with physical cursor only if idle for > 120ms
            if virtualCursorLocation == nil || (now - lastMotionTimestamp) > 0.12 {
                virtualCursorLocation = currentQuartzCursorLocation()
            }
            lastMotionTimestamp = now

            if var pos = virtualCursorLocation {
                let bounds = combinedScreenBounds()
                pos.x = min(max(pos.x + dx, bounds.minX), bounds.maxX - 1)
                pos.y = min(max(pos.y + dy, bounds.minY), bounds.maxY - 1)
                virtualCursorLocation = pos

                let eventType: CGEventType = isDragLocked ? .leftMouseDragged : .mouseMoved
                if let event = CGEvent(
                    mouseEventSource: nil,
                    mouseType: eventType,
                    mouseCursorPosition: pos,
                    mouseButton: .left
                ) {
                    event.setDoubleValueField(.mouseEventDeltaX, value: dx)
                    event.setDoubleValueField(.mouseEventDeltaY, value: dy)
                    event.post(tap: .cghidEventTap)
                }
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

        // 3. Two-Finger Pinch Zoom (Cmd + Plus / Cmd + Minus)
        if motion.pinchScaleDelta != 0 {
            let zoomKeyCode: CGKeyCode = motion.pinchScaleDelta > 0 ? 24 : 27 // 24 = '+', 27 = '-'
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: zoomKeyCode, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: zoomKeyCode, keyDown: false) {
                down.flags = .maskCommand
                up.flags = .maskCommand
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
        }
    }

    /// Injects discrete trackpad clicks, drag-lock, and 3/4-finger macOS system gestures.
    public func handleGesture(_ gesture: TrackpadGesturePayload) {
        if gesture.systemGesture != .none {
            triggerSystemGesture(gesture.systemGesture)
            return
        }

        let currentPos = virtualCursorLocation ?? currentQuartzCursorLocation()
        let isRight = gesture.buttonMask.contains(.right)
        let mouseButton: CGMouseButton = isRight ? .right : .left
        let downType: CGEventType = isRight ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = isRight ? .rightMouseUp : .leftMouseUp

        isDragLocked = gesture.buttonMask.contains(.dragLock) && gesture.action == .press

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
        if let cgLoc = CGEvent(source: nil)?.location {
            return cgLoc
        }
        let pos = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 1080.0
        return CGPoint(x: pos.x, y: primaryHeight - pos.y)
    }

    private func combinedScreenBounds() -> CGRect {
        let screens = NSScreen.screens
        guard let first = screens.first else {
            return CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        return screens.dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }
}
#endif
