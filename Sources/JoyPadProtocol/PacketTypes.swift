import Foundation

/// Active operation mode of the Universal Pad.
public enum PadMode: UInt8, Sendable, CaseIterable, Codable {
    case trackpad        = 0x01
    case keyboard        = 0x02
    case gamepad         = 0x03
    case hybridSteamDeck = 0x04

    public var displayName: String {
        switch self {
        case .trackpad:        return "Magic Trackpad"
        case .keyboard:        return "Teclado & Macros"
        case .gamepad:         return "Gamepad Nativo"
        case .hybridSteamDeck: return "Híbrido (Steam Deck)"
        }
    }

    public var systemImage: String {
        switch self {
        case .trackpad:        return "rectangle.and.hand.point.up.left.filled"
        case .keyboard:        return "keyboard.fill"
        case .gamepad:         return "gamecontroller.fill"
        case .hybridSteamDeck: return "dpad.fill"
        }
    }
}

/// Discriminator for multiplexed binary frames over AWDL P2P.
public enum PacketType: UInt8, Sendable {
    case gamepadState    = 0x01 // 12-byte continuous gamepad state (UDP stream)
    case trackpadMotion  = 0x02 // 10-byte cursor delta + 2-finger scroll (UDP stream)
    case trackpadGesture = 0x03 // 4-byte discrete clicks & 3-finger gestures (Reliable event)
    case keyboardKey     = 0x04 // 5-byte physical keyCode + modifiers (Reliable event)
    case unicodeText     = 0x05 // Variable-length UTF-8 string for dictation/text (Reliable event)
    case systemMedia     = 0x06 // 2-byte media/brightness/system shortcut (Reliable event)
    case gyroMotion      = 0x07 // 6-byte pitch/yaw/roll angular velocity (UDP stream)
    case controlSync     = 0xFF // 6-byte bidirectional mode sync, ping & haptic trigger

    /// Whether this packet requires guaranteed delivery vs. low-latency fire-and-forget UDP.
    public var requiresReliableDelivery: Bool {
        switch self {
        case .gamepadState, .trackpadMotion, .gyroMotion:
            return false
        case .trackpadGesture, .keyboardKey, .unicodeText, .systemMedia, .controlSync:
            return true
        }
    }
}

/// Fixed 4-byte frame header preceding every JoyPad binary packet.
public struct PacketHeader: Equatable, Sendable {
    public static let magicByte: UInt8 = 0x4A // ASCII 'J'
    public static let byteSize: Int = 4

    public var magic: UInt8
    public var type: PacketType
    public var sequence: UInt16

    public init(type: PacketType, sequence: UInt16) {
        self.magic = Self.magicByte
        self.type = type
        self.sequence = sequence
    }
}
