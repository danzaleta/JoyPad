import Foundation

public enum JoyPadCodecError: Error, Equatable, Sendable {
    case bufferTooSmall(expected: Int, actual: Int)
    case invalidMagic(UInt8)
    case unknownPacketType(UInt8)
    case invalidPayloadValue
}

/// Zero-overhead binary encoder and decoder for JoyPad frames.
public enum JoyPadCodec {

    // MARK: - Encoding

    public static func encode(payload: JoyPadFramePayload, sequence: UInt16) -> Data {
        switch payload {
        case .gamepadState(let state):
            var bytes = Data(capacity: PacketHeader.byteSize + GamepadStatePayload.byteSize)
            appendHeader(&bytes, type: .gamepadState, sequence: sequence)
            appendUInt32(&bytes, state.buttons.rawValue)
            appendInt16(&bytes, state.leftStickX)
            appendInt16(&bytes, state.leftStickY)
            appendInt16(&bytes, state.rightStickX)
            appendInt16(&bytes, state.rightStickY)
            bytes.append(state.triggerL2)
            bytes.append(state.triggerR2)
            return bytes

        case .trackpadMotion(let motion):
            var bytes = Data(capacity: PacketHeader.byteSize + TrackpadMotionPayload.byteSize)
            appendHeader(&bytes, type: .trackpadMotion, sequence: sequence)
            appendInt16(&bytes, motion.deltaXScaled)
            appendInt16(&bytes, motion.deltaYScaled)
            appendInt16(&bytes, motion.scrollDeltaX)
            appendInt16(&bytes, motion.scrollDeltaY)
            bytes.append(motion.scrollPhase.rawValue)
            bytes.append(UInt8(bitPattern: motion.pinchScaleDelta))
            return bytes

        case .trackpadGesture(let gesture):
            var bytes = Data(capacity: PacketHeader.byteSize + TrackpadGesturePayload.byteSize)
            appendHeader(&bytes, type: .trackpadGesture, sequence: sequence)
            bytes.append(gesture.buttonMask.rawValue)
            bytes.append(gesture.action.rawValue)
            bytes.append(gesture.systemGesture.rawValue)
            bytes.append(gesture.reserved)
            return bytes

        case .keyboardKey(let key):
            var bytes = Data(capacity: PacketHeader.byteSize + KeyboardKeyPayload.byteSize)
            appendHeader(&bytes, type: .keyboardKey, sequence: sequence)
            appendUInt16(&bytes, key.keyCode)
            bytes.append(key.modifiers.rawValue)
            bytes.append(key.isKeyDown ? 1 : 0)
            bytes.append(key.isRepeat ? 1 : 0)
            return bytes

        case .unicodeText(let text):
            let utf8 = Data(text.utf8)
            let count = UInt16(min(utf8.count, Int(UInt16.max)))
            var bytes = Data(capacity: PacketHeader.byteSize + 2 + Int(count))
            appendHeader(&bytes, type: .unicodeText, sequence: sequence)
            appendUInt16(&bytes, count)
            bytes.append(utf8.prefix(Int(count)))
            return bytes

        case .systemMedia(let media):
            var bytes = Data(capacity: PacketHeader.byteSize + SystemMediaPayload.byteSize)
            appendHeader(&bytes, type: .systemMedia, sequence: sequence)
            bytes.append(media.action.rawValue)
            bytes.append(media.value)
            return bytes

        case .gyroMotion(let gyro):
            var bytes = Data(capacity: PacketHeader.byteSize + GyroMotionPayload.byteSize)
            appendHeader(&bytes, type: .gyroMotion, sequence: sequence)
            appendInt16(&bytes, gyro.pitchScaled)
            appendInt16(&bytes, gyro.yawScaled)
            appendInt16(&bytes, gyro.rollScaled)
            return bytes

        case .controlSync(let sync):
            var bytes = Data(capacity: PacketHeader.byteSize + ControlSyncPayload.byteSize)
            appendHeader(&bytes, type: .controlSync, sequence: sequence)
            bytes.append(sync.command.rawValue)
            bytes.append(sync.targetMode.rawValue)
            appendUInt32(&bytes, sync.timestampMs)
            return bytes
        }
    }

    // MARK: - Decoding

    public static func decode(_ data: Data) throws -> JoyPadFrame {
        guard data.count >= PacketHeader.byteSize else {
            throw JoyPadCodecError.bufferTooSmall(expected: PacketHeader.byteSize, actual: data.count)
        }

        let bytes = [UInt8](data)
        let magic = bytes[0]
        guard magic == PacketHeader.magicByte else {
            throw JoyPadCodecError.invalidMagic(magic)
        }

        guard let packetType = PacketType(rawValue: bytes[1]) else {
            throw JoyPadCodecError.unknownPacketType(bytes[1])
        }

        let sequence = readUInt16(bytes, offset: 2)
        let header = PacketHeader(type: packetType, sequence: sequence)
        let pOffset = PacketHeader.byteSize

        switch packetType {
        case .gamepadState:
            let expected = pOffset + GamepadStatePayload.byteSize
            guard bytes.count >= expected else {
                throw JoyPadCodecError.bufferTooSmall(expected: expected, actual: bytes.count)
            }
            let payload = GamepadStatePayload(
                buttons: GamepadButtons(rawValue: readUInt32(bytes, offset: pOffset)),
                leftStickX: readInt16(bytes, offset: pOffset + 4),
                leftStickY: readInt16(bytes, offset: pOffset + 6),
                rightStickX: readInt16(bytes, offset: pOffset + 8),
                rightStickY: readInt16(bytes, offset: pOffset + 10),
                triggerL2: bytes[pOffset + 12],
                triggerR2: bytes[pOffset + 13]
            )
            return JoyPadFrame(header: header, payload: .gamepadState(payload))

        case .trackpadMotion:
            let expected = pOffset + TrackpadMotionPayload.byteSize
            guard bytes.count >= expected else {
                throw JoyPadCodecError.bufferTooSmall(expected: expected, actual: bytes.count)
            }
            guard let phase = ScrollPhase(rawValue: bytes[pOffset + 8]) else {
                throw JoyPadCodecError.invalidPayloadValue
            }
            let payload = TrackpadMotionPayload(
                deltaXScaled: readInt16(bytes, offset: pOffset),
                deltaYScaled: readInt16(bytes, offset: pOffset + 2),
                scrollDeltaX: readInt16(bytes, offset: pOffset + 4),
                scrollDeltaY: readInt16(bytes, offset: pOffset + 6),
                scrollPhase: phase,
                pinchScaleDelta: Int8(bitPattern: bytes[pOffset + 9])
            )
            return JoyPadFrame(header: header, payload: .trackpadMotion(payload))

        case .trackpadGesture:
            let expected = pOffset + TrackpadGesturePayload.byteSize
            guard bytes.count >= expected else {
                throw JoyPadCodecError.bufferTooSmall(expected: expected, actual: bytes.count)
            }
            guard
                let action = ClickAction(rawValue: bytes[pOffset + 1]),
                let gesture = SystemGesture(rawValue: bytes[pOffset + 2])
            else {
                throw JoyPadCodecError.invalidPayloadValue
            }
            let payload = TrackpadGesturePayload(
                buttonMask: MouseButtonMask(rawValue: bytes[pOffset]),
                action: action,
                systemGesture: gesture,
                reserved: bytes[pOffset + 3]
            )
            return JoyPadFrame(header: header, payload: .trackpadGesture(payload))

        case .keyboardKey:
            let expected = pOffset + KeyboardKeyPayload.byteSize
            guard bytes.count >= expected else {
                throw JoyPadCodecError.bufferTooSmall(expected: expected, actual: bytes.count)
            }
            let payload = KeyboardKeyPayload(
                keyCode: readUInt16(bytes, offset: pOffset),
                modifiers: KeyModifiers(rawValue: bytes[pOffset + 2]),
                isKeyDown: bytes[pOffset + 3] != 0,
                isRepeat: bytes[pOffset + 4] != 0
            )
            return JoyPadFrame(header: header, payload: .keyboardKey(payload))

        case .unicodeText:
            let minExpected = pOffset + 2
            guard bytes.count >= minExpected else {
                throw JoyPadCodecError.bufferTooSmall(expected: minExpected, actual: bytes.count)
            }
            let length = Int(readUInt16(bytes, offset: pOffset))
            let totalExpected = minExpected + length
            guard bytes.count >= totalExpected else {
                throw JoyPadCodecError.bufferTooSmall(expected: totalExpected, actual: bytes.count)
            }
            let textSlice = bytes[minExpected..<totalExpected]
            let text = String(decoding: textSlice, as: UTF8.self)
            return JoyPadFrame(header: header, payload: .unicodeText(text))

        case .systemMedia:
            let expected = pOffset + SystemMediaPayload.byteSize
            guard bytes.count >= expected else {
                throw JoyPadCodecError.bufferTooSmall(expected: expected, actual: bytes.count)
            }
            guard let action = MediaAction(rawValue: bytes[pOffset]) else {
                throw JoyPadCodecError.invalidPayloadValue
            }
            let payload = SystemMediaPayload(action: action, value: bytes[pOffset + 1])
            return JoyPadFrame(header: header, payload: .systemMedia(payload))

        case .gyroMotion:
            let expected = pOffset + GyroMotionPayload.byteSize
            guard bytes.count >= expected else {
                throw JoyPadCodecError.bufferTooSmall(expected: expected, actual: bytes.count)
            }
            let payload = GyroMotionPayload(
                pitchScaled: readInt16(bytes, offset: pOffset),
                yawScaled: readInt16(bytes, offset: pOffset + 2),
                rollScaled: readInt16(bytes, offset: pOffset + 4)
            )
            return JoyPadFrame(header: header, payload: .gyroMotion(payload))

        case .controlSync:
            let expected = pOffset + ControlSyncPayload.byteSize
            guard bytes.count >= expected else {
                throw JoyPadCodecError.bufferTooSmall(expected: expected, actual: bytes.count)
            }
            guard
                let command = SyncCommand(rawValue: bytes[pOffset]),
                let mode = PadMode(rawValue: bytes[pOffset + 1])
            else {
                throw JoyPadCodecError.invalidPayloadValue
            }
            let payload = ControlSyncPayload(
                command: command,
                targetMode: mode,
                timestampMs: readUInt32(bytes, offset: pOffset + 2)
            )
            return JoyPadFrame(header: header, payload: .controlSync(payload))
        }
    }

    // MARK: - Little-Endian Helpers

    private static func appendHeader(_ data: inout Data, type: PacketType, sequence: UInt16) {
        data.append(PacketHeader.magicByte)
        data.append(type.rawValue)
        appendUInt16(&data, sequence)
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        let le = value.littleEndian
        withUnsafeBytes(of: le) { data.append(contentsOf: $0) }
    }

    private static func appendInt16(_ data: inout Data, _ value: Int16) {
        let le = value.littleEndian
        withUnsafeBytes(of: le) { data.append(contentsOf: $0) }
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        let le = value.littleEndian
        withUnsafeBytes(of: le) { data.append(contentsOf: $0) }
    }

    private static func readUInt16(_ bytes: [UInt8], offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readInt16(_ bytes: [UInt8], offset: Int) -> Int16 {
        Int16(bitPattern: readUInt16(bytes, offset: offset))
    }

    private static func readUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
