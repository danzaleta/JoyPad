#if os(macOS)
import Foundation
import CoreGraphics
import AppKit
import JoyPadProtocol

/// Injects physical key codes, shortcuts, direct Unicode text (dictation/accents), and media actions.
@MainActor
public final class KeyboardInjectionEngine {
    public init() {}

    /// Injects a physical macOS `CGKeyCode` with modifier flags (`Cmd`, `Shift`, `Option`, `Control`, `Fn`).
    public func handleKey(_ payload: KeyboardKeyPayload) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(payload.keyCode),
            keyDown: payload.isKeyDown
        ) else { return }

        var flags: CGEventFlags = []
        if payload.modifiers.contains(.command)  { flags.insert(.maskCommand) }
        if payload.modifiers.contains(.shift)    { flags.insert(.maskShift) }
        if payload.modifiers.contains(.option)   { flags.insert(.maskAlternate) }
        if payload.modifiers.contains(.control)  { flags.insert(.maskControl) }
        if payload.modifiers.contains(.function) { flags.insert(.maskSecondaryFn) }

        event.flags = flags
        if payload.isRepeat {
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }
        event.post(tap: .cghidEventTap)
    }

    /// Injects arbitrary UTF-8 / UTF-16 text (e.g., from iOS native keyboard or Voice Dictation).
    public func handleUnicodeText(_ text: String) {
        let utf16Chars = Array(text.utf16)
        guard !utf16Chars.isEmpty else { return }

        if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
            down.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            up.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    /// Injects macOS system media keys (Volume, Brightness, Play/Pause, Spotlight, Screenshot).
    public func handleMedia(_ payload: SystemMediaPayload) {
        switch payload.action {
        case .volumeUp:       postSystemDefinedKey(nxKeyType: 0)  // NX_KEYTYPE_SOUND_UP
        case .volumeDown:     postSystemDefinedKey(nxKeyType: 1)  // NX_KEYTYPE_SOUND_DOWN
        case .brightnessUp:   postSystemDefinedKey(nxKeyType: 2)  // NX_KEYTYPE_BRIGHTNESS_UP
        case .brightnessDown: postSystemDefinedKey(nxKeyType: 3)  // NX_KEYTYPE_BRIGHTNESS_DOWN
        case .mute:           postSystemDefinedKey(nxKeyType: 7)  // NX_KEYTYPE_MUTE
        case .playPause:      postSystemDefinedKey(nxKeyType: 16) // NX_KEYTYPE_PLAY
        case .nextTrack:      postSystemDefinedKey(nxKeyType: 17) // NX_KEYTYPE_NEXT
        case .previousTrack:  postSystemDefinedKey(nxKeyType: 18) // NX_KEYTYPE_PREVIOUS
        case .spotlight:
            // Cmd + Space (KeyCode 49)
            handleKey(KeyboardKeyPayload(keyCode: 49, modifiers: [.command], isKeyDown: true))
            handleKey(KeyboardKeyPayload(keyCode: 49, modifiers: [.command], isKeyDown: false))
        case .screenshot:
            // Cmd + Shift + 4 (KeyCode 21)
            handleKey(KeyboardKeyPayload(keyCode: 21, modifiers: [.command, .shift], isKeyDown: true))
            handleKey(KeyboardKeyPayload(keyCode: 21, modifiers: [.command, .shift], isKeyDown: false))
        }
    }

    private func postSystemDefinedKey(nxKeyType: Int) {
        func sendKey(down: Bool) {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = (nxKeyType << 16) | ((down ? 0xA : 0xB) << 8)
            guard let nsEvent = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: flags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1
            ) else { return }
            nsEvent.cgEvent?.post(tap: .cghidEventTap)
        }
        sendKey(down: true)
        sendKey(down: false)
    }
}
#endif
