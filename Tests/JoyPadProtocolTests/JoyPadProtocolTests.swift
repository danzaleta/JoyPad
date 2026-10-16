import Testing
@testable import JoyPadProtocol

@Suite("JoyPad Binary Protocol v2 Tests")
struct JoyPadProtocolTests {

    @Test("Gamepad packet round-trip and exact byte size")
    func gamepadPacketRoundTripAndByteSize() throws {
        let original = GamepadStatePayload(
            buttons: [.southA, .shoulderR1, .dpadUp],
            leftStickX: -16384,
            leftStickY: 32767,
            rightStickX: 8192,
            rightStickY: -4096,
            triggerL2: 128,
            triggerR2: 255
        )
        let data = JoyPadCodec.encode(payload: .gamepadState(original), sequence: 42)
        #expect(data.count == PacketHeader.byteSize + GamepadStatePayload.byteSize)

        let decoded = try JoyPadCodec.decode(data)
        #expect(decoded.header.sequence == 42)
        #expect(decoded.header.type == .gamepadState)
        #expect(decoded.payload == .gamepadState(original))
    }

    @Test("Trackpad motion packet round-trip and exact byte size")
    func trackpadMotionPacketRoundTripAndByteSize() throws {
        let original = TrackpadMotionPayload(
            deltaX: 12.45,
            deltaY: -6.75,
            scrollDeltaX: 0,
            scrollDeltaY: 24,
            scrollPhase: .changed,
            pinchScaleDelta: -5
        )
        let data = JoyPadCodec.encode(payload: .trackpadMotion(original), sequence: 1001)
        #expect(data.count == PacketHeader.byteSize + TrackpadMotionPayload.byteSize)

        let decoded = try JoyPadCodec.decode(data)
        #expect(decoded.header.sequence == 1001)
        #expect(decoded.payload == .trackpadMotion(original))
    }

    @Test("Trackpad gesture packet round-trip")
    func trackpadGestureRoundTrip() throws {
        let original = TrackpadGesturePayload(
            buttonMask: [.left, .dragLock],
            action: .forceClick,
            systemGesture: .missionControl
        )
        let data = JoyPadCodec.encode(payload: .trackpadGesture(original), sequence: 7)
        #expect(data.count == PacketHeader.byteSize + TrackpadGesturePayload.byteSize)

        let decoded = try JoyPadCodec.decode(data)
        #expect(decoded.payload == .trackpadGesture(original))
    }

    @Test("Keyboard keycode and UTF-8 Unicode dictation round-trip")
    func keyboardKeyAndUnicodeTextRoundTrip() throws {
        let key = KeyboardKeyPayload(
            keyCode: 8,
            modifiers: [.command, .shift],
            isKeyDown: true,
            isRepeat: false
        )
        let keyData = JoyPadCodec.encode(payload: .keyboardKey(key), sequence: 88)
        #expect(keyData.count == PacketHeader.byteSize + KeyboardKeyPayload.byteSize)
        let decodedKey = try JoyPadCodec.decode(keyData)
        #expect(decodedKey.payload == .keyboardKey(key))

        let unicodeString = "¡Hola Mundo desde Dictado iOS! 🎮✨ ñáéíóú"
        let textData = JoyPadCodec.encode(payload: .unicodeText(unicodeString), sequence: 89)
        let decodedText = try JoyPadCodec.decode(textData)
        #expect(decodedText.payload == .unicodeText(unicodeString))
    }

    @Test("ControlSync and GyroMotion round-trip")
    func controlSyncAndGyroRoundTrip() throws {
        let sync = ControlSyncPayload(
            command: .switchMode,
            targetMode: .hybridSteamDeck,
            timestampMs: 987654321
        )
        let syncData = JoyPadCodec.encode(payload: .controlSync(sync), sequence: 500)
        #expect(syncData.count == PacketHeader.byteSize + ControlSyncPayload.byteSize)
        let decodedSync = try JoyPadCodec.decode(syncData)
        #expect(decodedSync.payload == .controlSync(sync))

        let gyro = GyroMotionPayload(pitchScaled: -250, yawScaled: 1140, rollScaled: 15)
        let gyroData = JoyPadCodec.encode(payload: .gyroMotion(gyro), sequence: 501)
        #expect(gyroData.count == PacketHeader.byteSize + GyroMotionPayload.byteSize)
        let decodedGyro = try JoyPadCodec.decode(gyroData)
        #expect(decodedGyro.payload == .gyroMotion(gyro))
    }
}
