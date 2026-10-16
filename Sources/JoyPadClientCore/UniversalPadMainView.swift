import SwiftUI
import JoyPadProtocol

/// Tracks frame-to-frame touch deltas without using @State macros.
@MainActor
final class TouchDeltaTracker: ObservableObject {
    var lastCursorLocation: CGPoint? = nil
    var lastScrollLocation: CGPoint? = nil
    var lastCameraLocation: CGPoint? = nil
}

/// Adaptive multi-mode UI for the JoyPad Universal Client (Trackpad, Keyboard, Gamepad, Hybrid).
public struct UniversalPadMainView: View {
    @ObservedObject private var session: PadSessionClient
    @StateObject private var tracker = TouchDeltaTracker()
    private let haptics = TapticEngineManager()

    public init(session: PadSessionClient) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 10) {
            headerBar
            connectionBar
            modeSelectorBar
            Divider()
            activeModeContent
        }
        .padding(12)
        .background(Color.black.opacity(0.94))
        .foregroundStyle(.white)
        .onAppear {
            // Connect immediately to the Mac's local IP and start Bonjour discovery
            session.connectToDirectIP()
            session.startDiscovery()
        }
    }

    private var headerBar: some View {
        HStack {
            Circle()
                .fill(session.isConnected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text(session.statusMessage)
                .font(.caption.monospaced())
                .lineLimit(1)
            Spacer()
            Text("TX: \(session.packetsSent) • RTT: \(session.rttMilliseconds) ms")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var connectionBar: some View {
        HStack(spacing: 8) {
            Text("IP Mac:")
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("192.168.68.109", text: $session.manualHostIP)
                .textFieldStyle(.roundedBorder)
                .font(.caption.monospaced())
                .foregroundStyle(.black)
                .frame(maxWidth: 150)
            Button("Conectar IP") {
                haptics.playTrackpadClick()
                session.connectToDirectIP()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button("Ping") {
                haptics.playTrackpadClick()
                session.sendPing()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var modeSelectorBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PadMode.allCases, id: \.rawValue) { mode in
                    Button {
                        haptics.playTrackpadClick()
                        session.activeMode = mode
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.systemImage)
                            Text(mode.displayName)
                                .font(.caption.bold())
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(session.activeMode == mode ? Color.blue : Color.white.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var activeModeContent: some View {
        switch session.activeMode {
        case .trackpad:
            trackpadSurfaceView
        case .keyboard:
            keyboardAndMacrosView
        case .gamepad:
            gamepadSurfaceView
        case .hybridSteamDeck:
            hybridSteamDeckView
        }
    }

    // MARK: - 1. Magic Trackpad Mode (Incremental Delta + Dedicated Scroll Strip)

    private var trackpadSurfaceView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                // Main 1-Finger Cursor & Tap Surface
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("Superficie Magic Trackpad\nDesliza para mover el cursor • Toca para Clic Izquierdo")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let last = tracker.lastCursorLocation {
                                    let dx = Double(value.location.x - last.x) * 1.6
                                    let dy = Double(value.location.y - last.y) * 1.6
                                    if abs(dx) > 0.01 || abs(dy) > 0.01 {
                                        session.send(.trackpadMotion(TrackpadMotionPayload(deltaX: dx, deltaY: dy)))
                                    }
                                }
                                tracker.lastCursorLocation = value.location
                            }
                            .onEnded { value in
                                let totalMove = hypot(value.translation.width, value.translation.height)
                                tracker.lastCursorLocation = nil
                                // Treat a short tap (< 6pt movement) as a Left Click!
                                if totalMove < 6.0 {
                                    haptics.playTrackpadClick()
                                    session.send(
                                        .trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .tapClick))
                                    )
                                }
                            }
                    )

                // Dedicated Smooth Scroll Strip on the right edge
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 54)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.up.and.down.circle.fill")
                            Text("Scroll")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let last = tracker.lastScrollLocation {
                                    let dy = Int16(clamping: Int((last.y - value.location.y) * 2.5))
                                    let dx = Int16(clamping: Int((last.x - value.location.x) * 2.5))
                                    if dy != 0 || dx != 0 {
                                        session.send(
                                            .trackpadMotion(
                                                TrackpadMotionPayload(
                                                    scrollDeltaX: dx,
                                                    scrollDeltaY: dy,
                                                    scrollPhase: .changed
                                                )
                                            )
                                        )
                                    }
                                } else {
                                    session.send(.trackpadMotion(TrackpadMotionPayload(scrollPhase: .began)))
                                }
                                tracker.lastScrollLocation = value.location
                            }
                            .onEnded { _ in
                                tracker.lastScrollLocation = nil
                                session.send(.trackpadMotion(TrackpadMotionPayload(scrollPhase: .ended)))
                            }
                    )
            }

            // Bottom Physical Click & Gesture Bar
            HStack(spacing: 8) {
                Button("Clic Izq") {
                    haptics.playTrackpadClick()
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .tapClick)))
                }
                .buttonStyle(.borderedProminent)

                Button("Clic Der") {
                    haptics.playTrackpadClick()
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .right, action: .tapClick)))
                }
                .buttonStyle(.borderedProminent)

                systemGestureButton("Mission Ctrl", gesture: .missionControl)
                systemGestureButton(" ◀ Space", gesture: .spaceLeft)
                systemGestureButton("Space ▶", gesture: .spaceRight)
            }
        }
    }

    // MARK: - 2. Keyboard, Dictation & Media Mode

    private var keyboardAndMacrosView: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Escribe o usa Dictado por Voz de iOS...", text: $session.dictationText)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.black)
                    .onSubmit {
                        guard !session.dictationText.isEmpty else { return }
                        session.send(.unicodeText(session.dictationText))
                        session.dictationText = ""
                    }
                Button("Enviar a Mac") {
                    guard !session.dictationText.isEmpty else { return }
                    haptics.playTrackpadClick()
                    session.send(.unicodeText(session.dictationText))
                    session.dictationText = ""
                }
                .buttonStyle(.borderedProminent)
            }

            // Tactical Modifier & Function Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tacticalKeyButton("Enter", keyCode: 36)
                    tacticalKeyButton("Borrar ⌫", keyCode: 51)
                    tacticalKeyButton("Esc", keyCode: 53)
                    tacticalKeyButton("Tab", keyCode: 48)
                    tacticalKeyButton("Cmd+C", keyCode: 8, modifiers: [.command])
                    tacticalKeyButton("Cmd+V", keyCode: 9, modifiers: [.command])
                    tacticalKeyButton("Cmd+Z", keyCode: 6, modifiers: [.command])
                    tacticalKeyButton("Spotlight", keyCode: 49, modifiers: [.command])
                }
            }

            // Media & System Deck
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    mediaButton("🔉 Vol -", action: .volumeDown)
                    mediaButton("⏯ Play", action: .playPause)
                    mediaButton("🔊 Vol +", action: .volumeUp)
                    mediaButton("🔅 Brillo -", action: .brightnessDown)
                    mediaButton("🔆 Brillo +", action: .brightnessUp)
                    mediaButton("📸 Captura", action: .screenshot)
                }
            }
            Spacer()
        }
    }

    // MARK: - 3. Native Gamepad Mode

    private var gamepadSurfaceView: some View {
        HStack(spacing: 16) {
            VStack(spacing: 10) {
                Text("D-Pad / Movimiento")
                    .font(.caption.bold())
                gamepadButton("▲ Arriba (W)", button: .dpadUp)
                HStack(spacing: 12) {
                    gamepadButton("◀ Izq (A)", button: .dpadLeft)
                    gamepadButton("▶ Der (D)", button: .dpadRight)
                }
                gamepadButton("▼ Abajo (S)", button: .dpadDown)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 10) {
                Text("Acciones ABXY")
                    .font(.caption.bold())
                gamepadButton("Y (Recargar)", button: .northY)
                HStack(spacing: 12) {
                    gamepadButton("X (Usar/E)", button: .westX)
                    gamepadButton("B (Shift)", button: .eastB)
                }
                gamepadButton("A (Saltar)", button: .southA)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    // MARK: - 4. Hybrid "Steam Deck" Mode

    private var hybridSteamDeckView: some View {
        HStack(spacing: 12) {
            VStack(spacing: 10) {
                Text("WASD + Acciones")
                    .font(.caption.bold())
                HStack {
                    gamepadButton("Saltar", button: .southA)
                    gamepadButton("Shift", button: .eastB)
                }
                HStack {
                    gamepadButton("Inv (E)", button: .westX)
                    gamepadButton("Esc", button: .start)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(0.16))
                .overlay(
                    Text("Trackpad de Cámara\n(Desliza para mirar • Toca para atacar)")
                        .font(.caption.bold())
                        .multilineTextAlignment(.center)
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if let last = tracker.lastCameraLocation {
                                let dx = Double(value.location.x - last.x) * 2.0
                                let dy = Double(value.location.y - last.y) * 2.0
                                session.send(.trackpadMotion(TrackpadMotionPayload(deltaX: dx, deltaY: dy)))
                            }
                            tracker.lastCameraLocation = value.location
                        }
                        .onEnded { value in
                            let totalMove = hypot(value.translation.width, value.translation.height)
                            tracker.lastCameraLocation = nil
                            if totalMove < 6.0 {
                                haptics.playTrackpadClick()
                                session.send(
                                    .trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .tapClick))
                                )
                            }
                        }
                )
        }
    }

    // MARK: - Helper Buttons

    private func systemGestureButton(_ title: String, gesture: SystemGesture) -> some View {
        Button(title) {
            haptics.playTrackpadClick()
            session.send(.trackpadGesture(TrackpadGesturePayload(systemGesture: gesture)))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func tacticalKeyButton(_ title: String, keyCode: UInt16, modifiers: KeyModifiers = []) -> some View {
        Button(title) {
            haptics.playTrackpadClick()
            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: keyCode, modifiers: modifiers, isKeyDown: true)))
            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: keyCode, modifiers: modifiers, isKeyDown: false)))
        }
        .buttonStyle(.bordered)
    }

    private func mediaButton(_ title: String, action: MediaAction) -> some View {
        Button(title) {
            haptics.playTrackpadClick()
            session.send(.systemMedia(SystemMediaPayload(action: action)))
        }
        .buttonStyle(.bordered)
    }

    private func gamepadButton(_ title: String, button: GamepadButtons) -> some View {
        Button(title) {
            haptics.playTrackpadClick()
            session.send(.gamepadState(GamepadStatePayload(buttons: button)))
            session.send(.gamepadState(GamepadStatePayload(buttons: [])))
        }
        .buttonStyle(.borderedProminent)
    }
}
