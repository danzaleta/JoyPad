import SwiftUI
import JoyPadProtocol

/// Adaptive multi-mode UI for the JoyPad Universal Client (Trackpad, Keyboard, Gamepad, Hybrid).
public struct UniversalPadMainView: View {
    @ObservedObject private var session: PadSessionClient
    private let haptics = TapticEngineManager()

    public init(session: PadSessionClient) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 10) {
            headerBar
            modeSelectorBar
            Divider()
            activeModeContent
        }
        .padding(12)
        .background(Color.black.opacity(0.92))
        .foregroundStyle(.white)
    }

    private var headerBar: some View {
        HStack {
            Circle()
                .fill(session.isConnected ? Color.green : Color.orange)
                .frame(width: 9, height: 9)
            Text(session.discoveredServerName ?? "Buscando Mac (AWDL P2P)...")
                .font(.caption.monospaced())
            Spacer()
            Text("RTT: \(session.rttMilliseconds) ms")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var modeSelectorBar: some View {
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
                    .background(session.activeMode == mode ? Color.blue : Color.white.opacity(0.1))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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

    // MARK: - 1. Magic Trackpad Mode

    private var trackpadSurfaceView: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    Text("Superficie Magic Trackpad\n1 dedo: Cursor / Clic • 2 dedos: Scroll / Clic Der • 3 dedos: Mission Control")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let motion = TrackpadMotionPayload(
                                deltaX: value.translation.width * 0.25,
                                deltaY: value.translation.height * 0.25
                            )
                            session.send(.trackpadMotion(motion))
                        }
                )
                .onTapGesture {
                    haptics.playTrackpadClick()
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .tapClick)))
                }

            HStack(spacing: 10) {
                systemGestureButton("Mission Control", gesture: .missionControl)
                systemGestureButton("Espacio Izq", gesture: .spaceLeft)
                systemGestureButton("Espacio Der", gesture: .spaceRight)
                Button("Clic Derecho") {
                    haptics.playTrackpadClick()
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .right, action: .tapClick)))
                }
                .buttonStyle(.bordered)
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
                Button("Enviar") {
                    guard !session.dictationText.isEmpty else { return }
                    session.send(.unicodeText(session.dictationText))
                    session.dictationText = ""
                }
                .buttonStyle(.borderedProminent)
            }

            // Tactical Modifier & Function Strip
            HStack(spacing: 8) {
                tacticalKeyButton("Esc", keyCode: 53)
                tacticalKeyButton("Tab", keyCode: 48)
                tacticalKeyButton("Cmd+C", keyCode: 8, modifiers: [.command])
                tacticalKeyButton("Cmd+V", keyCode: 9, modifiers: [.command])
                tacticalKeyButton("Cmd+Z", keyCode: 6, modifiers: [.command])
                tacticalKeyButton("Cmd+Space", keyCode: 49, modifiers: [.command])
            }

            // Media & System Deck
            HStack(spacing: 8) {
                mediaButton("Vol -", action: .volumeDown)
                mediaButton("Play/Pause", action: .playPause)
                mediaButton("Vol +", action: .volumeUp)
                mediaButton("Brillo -", action: .brightnessDown)
                mediaButton("Brillo +", action: .brightnessUp)
                mediaButton("Captura", action: .screenshot)
            }
        }
    }

    // MARK: - 3. Native Gamepad Mode

    private var gamepadSurfaceView: some View {
        HStack {
            VStack {
                Text("Stick Izquierdo (Movimiento)")
                    .font(.caption)
                HStack {
                    gamepadButton("A (Salto)", button: .southA)
                    gamepadButton("B (Agacharse)", button: .eastB)
                }
            }
            Spacer()
            VStack {
                Text("Botones ABXY & Gatillos")
                    .font(.caption)
                HStack {
                    gamepadButton("X (Acción)", button: .westX)
                    gamepadButton("Y (Recargar)", button: .northY)
                }
            }
        }
        .padding()
    }

    // MARK: - 4. Hybrid "Steam Deck" Mode

    private var hybridSteamDeckView: some View {
        HStack(spacing: 12) {
            VStack {
                Text("WASD Stick + Acciones")
                    .font(.caption.bold())
                HStack {
                    gamepadButton("Espacio", button: .southA)
                    gamepadButton("Shift", button: .eastB)
                    gamepadButton("Inventario (E)", button: .westX)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            RoundedRectangle(cornerRadius: 14)
                .fill(Color.blue.opacity(0.12))
                .overlay(
                    Text("Trackpad de Cámara (Alta Precisión + Giroscopio)")
                        .font(.caption.bold())
                )
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            session.send(
                                .trackpadMotion(
                                    TrackpadMotionPayload(
                                        deltaX: value.translation.width * 0.35,
                                        deltaY: value.translation.height * 0.35
                                    )
                                )
                            )
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
