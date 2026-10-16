#if os(macOS)
import Foundation
import CoreGraphics
import JoyPadProtocol

/// Translates Gamepad & Gyroscope packets into Hybrid "Steam Deck" controls (WASD + High-Precision Mouse Look)
/// as well as tracking state for native virtual HID gamepad dispatching.
@MainActor
public final class GamepadInjectionEngine {
    private let keyboardEngine: KeyboardInjectionEngine
    private let trackpadEngine: TrackpadInjectionEngine

    private var activeKeys: Set<UInt16> = []
    private var lastTriggerL2Pressed = false
    private var lastTriggerR2Pressed = false

    /// Deadzone threshold for normalized Int16 sticks (-32768...32767)
    public var stickDeadzone: Int16 = 4500
    public var cameraLookSensitivity: Double = 14.0

    public init(keyboardEngine: KeyboardInjectionEngine, trackpadEngine: TrackpadInjectionEngine) {
        self.keyboardEngine = keyboardEngine
        self.trackpadEngine = trackpadEngine
    }

    public func handleGamepadState(_ state: GamepadStatePayload) {
        // 1. Left Stick & D-Pad -> WASD Movement
        updateKeyState(keyCode: 13, pressed: state.leftStickY < -stickDeadzone || state.buttons.contains(.dpadUp))    // W
        updateKeyState(keyCode: 1,  pressed: state.leftStickY >  stickDeadzone || state.buttons.contains(.dpadDown))  // S
        updateKeyState(keyCode: 0,  pressed: state.leftStickX < -stickDeadzone || state.buttons.contains(.dpadLeft))  // A
        updateKeyState(keyCode: 2,  pressed: state.leftStickX >  stickDeadzone || state.buttons.contains(.dpadRight)) // D

        // 2. Action Buttons -> Space (Jump), Shift (Crouch/Sprint), E (Inventory), R (Reload), Esc
        updateKeyState(keyCode: 49, pressed: state.buttons.contains(.southA))     // Space
        updateKeyState(keyCode: 56, pressed: state.buttons.contains(.eastB))      // Left Shift
        updateKeyState(keyCode: 14, pressed: state.buttons.contains(.westX))      // E
        updateKeyState(keyCode: 15, pressed: state.buttons.contains(.northY))     // R
        updateKeyState(keyCode: 53, pressed: state.buttons.contains(.start))      // Escape
        updateKeyState(keyCode: 48, pressed: state.buttons.contains(.select))     // Tab

        // 3. Right Stick -> Continuous Camera Look Delta
        let rx = abs(state.rightStickX) > stickDeadzone ? Double(state.rightStickX) / 32767.0 : 0.0
        let ry = abs(state.rightStickY) > stickDeadzone ? Double(state.rightStickY) / 32767.0 : 0.0
        if rx != 0.0 || ry != 0.0 {
            let motion = TrackpadMotionPayload(
                deltaX: rx * cameraLookSensitivity,
                deltaY: ry * cameraLookSensitivity
            )
            trackpadEngine.handleMotion(motion)
        }

        // 4. Analog Triggers L2/R2 -> Right Click (Use/Aim) & Left Click (Attack/Mine)
        let r2Pressed = state.triggerR2 > 60 || state.buttons.contains(.shoulderR1)
        if r2Pressed != lastTriggerR2Pressed {
            lastTriggerR2Pressed = r2Pressed
            trackpadEngine.handleGesture(
                TrackpadGesturePayload(buttonMask: .left, action: r2Pressed ? .press : .release)
            )
        }

        let l2Pressed = state.triggerL2 > 60 || state.buttons.contains(.shoulderL1)
        if l2Pressed != lastTriggerL2Pressed {
            lastTriggerL2Pressed = l2Pressed
            trackpadEngine.handleGesture(
                TrackpadGesturePayload(buttonMask: .right, action: l2Pressed ? .press : .release)
            )
        }
    }

    public func handleGyro(_ gyro: GyroMotionPayload) {
        let yaw = Double(gyro.yawScaled) / 1000.0
        let pitch = Double(gyro.pitchScaled) / 1000.0
        guard abs(yaw) > 0.004 || abs(pitch) > 0.004 else { return }

        let motion = TrackpadMotionPayload(
            deltaX: yaw * 18.0,
            deltaY: pitch * 18.0
        )
        trackpadEngine.handleMotion(motion)
    }

    private func updateKeyState(keyCode: UInt16, pressed: Bool) {
        let isCurrentlyPressed = activeKeys.contains(keyCode)
        guard pressed != isCurrentlyPressed else { return }
        if pressed {
            activeKeys.insert(keyCode)
        } else {
            activeKeys.remove(keyCode)
        }
        keyboardEngine.handleKey(KeyboardKeyPayload(keyCode: keyCode, isKeyDown: pressed))
    }
}
#endif
