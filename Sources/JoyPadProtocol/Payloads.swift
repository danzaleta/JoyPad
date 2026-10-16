import Foundation

// MARK: - 0x01 Gamepad State Payload (12 Bytes)

public struct GamepadButtons: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let southA     = GamepadButtons(rawValue: 1 << 0)
    public static let eastB      = GamepadButtons(rawValue: 1 << 1)
    public static let westX      = GamepadButtons(rawValue: 1 << 2)
    public static let northY     = GamepadButtons(rawValue: 1 << 3)
    public static let dpadUp     = GamepadButtons(rawValue: 1 << 4)
    public static let dpadDown   = GamepadButtons(rawValue: 1 << 5)
    public static let dpadLeft   = GamepadButtons(rawValue: 1 << 6)
    public static let dpadRight  = GamepadButtons(rawValue: 1 << 7)
    public static let shoulderL1 = GamepadButtons(rawValue: 1 << 8)
    public static let shoulderR1 = GamepadButtons(rawValue: 1 << 9)
    public static let thumbL3    = GamepadButtons(rawValue: 1 << 10)
    public static let thumbR3    = GamepadButtons(rawValue: 1 << 11)
    public static let start      = GamepadButtons(rawValue: 1 << 12)
    public static let select     = GamepadButtons(rawValue: 1 << 13)
    public static let home       = GamepadButtons(rawValue: 1 << 14)
}

public struct GamepadStatePayload: Equatable, Sendable {
    public static let byteSize = 14

    public var buttons: GamepadButtons
    public var leftStickX: Int16
    public var leftStickY: Int16
    public var rightStickX: Int16
    public var rightStickY: Int16
    public var triggerL2: UInt8
    public var triggerR2: UInt8

    public init(
        buttons: GamepadButtons = [],
        leftStickX: Int16 = 0,
        leftStickY: Int16 = 0,
        rightStickX: Int16 = 0,
        rightStickY: Int16 = 0,
        triggerL2: UInt8 = 0,
        triggerR2: UInt8 = 0
    ) {
        self.buttons = buttons
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.rightStickX = rightStickX
        self.rightStickY = rightStickY
        self.triggerL2 = triggerL2
        self.triggerR2 = triggerR2
    }
}

// MARK: - 0x02 Trackpad Motion & Scroll Payload (10 Bytes)

public enum ScrollPhase: UInt8, Sendable, Equatable {
    case none     = 0
    case began    = 1
    case changed  = 2
    case ended    = 3
    case momentum = 4
}

public struct TrackpadMotionPayload: Equatable, Sendable {
    public static let byteSize = 10

    /// Cursor X delta scaled by 100 for sub-pixel precision (e.g., 150 = 1.50 pt)
    public var deltaXScaled: Int16
    /// Cursor Y delta scaled by 100 for sub-pixel precision
    public var deltaYScaled: Int16
    /// Horizontal 2-finger scroll delta
    public var scrollDeltaX: Int16
    /// Vertical 2-finger scroll delta
    public var scrollDeltaY: Int16
    /// macOS native inertial scroll phase
    public var scrollPhase: ScrollPhase
    /// Pinch-to-zoom delta (-128 to 127)
    public var pinchScaleDelta: Int8

    public var deltaX: Double { Double(deltaXScaled) / 100.0 }
    public var deltaY: Double { Double(deltaYScaled) / 100.0 }

    public init(
        deltaX: Double = 0,
        deltaY: Double = 0,
        scrollDeltaX: Int16 = 0,
        scrollDeltaY: Int16 = 0,
        scrollPhase: ScrollPhase = .none,
        pinchScaleDelta: Int8 = 0
    ) {
        self.deltaXScaled = Int16(clamping: Int((deltaX * 100.0).rounded()))
        self.deltaYScaled = Int16(clamping: Int((deltaY * 100.0).rounded()))
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.scrollPhase = scrollPhase
        self.pinchScaleDelta = pinchScaleDelta
    }

    public init(
        deltaXScaled: Int16,
        deltaYScaled: Int16,
        scrollDeltaX: Int16,
        scrollDeltaY: Int16,
        scrollPhase: ScrollPhase,
        pinchScaleDelta: Int8
    ) {
        self.deltaXScaled = deltaXScaled
        self.deltaYScaled = deltaYScaled
        self.scrollDeltaX = scrollDeltaX
        self.scrollDeltaY = scrollDeltaY
        self.scrollPhase = scrollPhase
        self.pinchScaleDelta = pinchScaleDelta
    }
}

// MARK: - 0x03 Trackpad Discrete Click & Gesture Payload (4 Bytes)

public struct MouseButtonMask: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let left     = MouseButtonMask(rawValue: 1 << 0)
    public static let right    = MouseButtonMask(rawValue: 1 << 1)
    public static let middle   = MouseButtonMask(rawValue: 1 << 2)
    public static let dragLock = MouseButtonMask(rawValue: 1 << 3)
}

public enum ClickAction: UInt8, Sendable, Equatable {
    case release     = 0
    case press       = 1
    case tapClick    = 2
    case doubleClick = 3
    case forceClick  = 4
}

public enum SystemGesture: UInt8, Sendable, Equatable {
    case none           = 0
    case missionControl = 1 // 3-finger swipe up
    case appExpose      = 2 // 3-finger swipe down
    case spaceLeft      = 3 // 3-finger swipe left
    case spaceRight     = 4 // 3-finger swipe right
    case showDesktop    = 5 // 4-finger spread
}

public struct TrackpadGesturePayload: Equatable, Sendable {
    public static let byteSize = 4

    public var buttonMask: MouseButtonMask
    public var action: ClickAction
    public var systemGesture: SystemGesture
    public var reserved: UInt8

    public init(
        buttonMask: MouseButtonMask = [],
        action: ClickAction = .release,
        systemGesture: SystemGesture = .none,
        reserved: UInt8 = 0
    ) {
        self.buttonMask = buttonMask
        self.action = action
        self.systemGesture = systemGesture
        self.reserved = reserved
    }
}

// MARK: - 0x04 Keyboard Key & Shortcut Payload (5 Bytes)

public struct KeyModifiers: OptionSet, Sendable, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let command  = KeyModifiers(rawValue: 1 << 0)
    public static let shift    = KeyModifiers(rawValue: 1 << 1)
    public static let option   = KeyModifiers(rawValue: 1 << 2)
    public static let control  = KeyModifiers(rawValue: 1 << 3)
    public static let function = KeyModifiers(rawValue: 1 << 4)
}

public struct KeyboardKeyPayload: Equatable, Sendable {
    public static let byteSize = 5

    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public var isKeyDown: Bool
    public var isRepeat: Bool

    public init(
        keyCode: UInt16,
        modifiers: KeyModifiers = [],
        isKeyDown: Bool,
        isRepeat: Bool = false
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isKeyDown = isKeyDown
        self.isRepeat = isRepeat
    }
}

// MARK: - 0x06 System & Media Action Payload (2 Bytes)

public enum MediaAction: UInt8, Sendable, Equatable {
    case volumeUp       = 1
    case volumeDown     = 2
    case mute           = 3
    case playPause      = 4
    case nextTrack      = 5
    case previousTrack  = 6
    case brightnessUp   = 7
    case brightnessDown = 8
    case spotlight      = 9
    case screenshot     = 10
}

public struct SystemMediaPayload: Equatable, Sendable {
    public static let byteSize = 2

    public var action: MediaAction
    public var value: UInt8

    public init(action: MediaAction, value: UInt8 = 0) {
        self.action = action
        self.value = value
    }
}

// MARK: - 0x07 Gyroscope Motion Payload (6 Bytes)

public struct GyroMotionPayload: Equatable, Sendable {
    public static let byteSize = 6

    /// Angular velocity scaled by 1000 rad/s
    public var pitchScaled: Int16
    public var yawScaled: Int16
    public var rollScaled: Int16

    public init(pitchScaled: Int16, yawScaled: Int16, rollScaled: Int16) {
        self.pitchScaled = pitchScaled
        self.yawScaled = yawScaled
        self.rollScaled = rollScaled
    }
}

// MARK: - 0xFF Bidirectional Control & Sync Payload (6 Bytes)

public enum SyncCommand: UInt8, Sendable, Equatable {
    case ping          = 1
    case pong          = 2
    case switchMode    = 3 // macOS notifies iOS to auto-switch PadMode
    case triggerHaptic = 4 // Trigger Taptic feedback on iPhone
}

public struct ControlSyncPayload: Equatable, Sendable {
    public static let byteSize = 6

    public var command: SyncCommand
    public var targetMode: PadMode
    public var timestampMs: UInt32

    public init(command: SyncCommand, targetMode: PadMode = .trackpad, timestampMs: UInt32 = 0) {
        self.command = command
        self.targetMode = targetMode
        self.timestampMs = timestampMs
    }
}

// MARK: - Unified Decoded Frame

public enum JoyPadFramePayload: Equatable, Sendable {
    case gamepadState(GamepadStatePayload)
    case trackpadMotion(TrackpadMotionPayload)
    case trackpadGesture(TrackpadGesturePayload)
    case keyboardKey(KeyboardKeyPayload)
    case unicodeText(String)
    case systemMedia(SystemMediaPayload)
    case gyroMotion(GyroMotionPayload)
    case controlSync(ControlSyncPayload)
}

public struct JoyPadFrame: Equatable, Sendable {
    public var header: PacketHeader
    public var payload: JoyPadFramePayload

    public init(header: PacketHeader, payload: JoyPadFramePayload) {
        self.header = header
        self.payload = payload
    }
}
