import SwiftUI
import JoyPadProtocol

/// Tracks frame-to-frame touch deltas without using @State macro plugins.
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
    @Environment(\.scenePhase) private var scenePhase
    private let haptics = TapticEngineManager()

    public init(session: PadSessionClient) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 8) {
            headerBar
            connectionBar
            modeSelectorBar
            Divider()
            activeModeContent
        }
        .padding(10)
        .background(Color.black.opacity(0.95))
        .foregroundStyle(.white)
        .onAppear {
            session.connectToDirectIP()
            session.startDiscovery()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                session.connectToDirectIP()
                session.startDiscovery()
            }
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
                .frame(maxWidth: 145)
            Button("Conectar") {
                haptics.playTrackpadClick()
                session.connectToDirectIP()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Toggle("Giroscopio", isOn: $session.isGyroEnabled)
                .toggleStyle(.button)
                .controlSize(.small)
                .tint(.purple)
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

    // MARK: - 1. Magic Trackpad Mode

    private var trackpadSurfaceView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                // Main 1-Finger Cursor & Tap Surface
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "hand.point.up.left.fill")
                                .font(.title2)
                                .foregroundStyle(.white.opacity(0.35))
                            Text("Superficie Magic Trackpad\nDesliza para mover cursor • Toca para Clic Izq")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let last = tracker.lastCursorLocation {
                                    let dx = Double(value.location.x - last.x) * session.trackpadSensitivity
                                    let dy = Double(value.location.y - last.y) * session.trackpadSensitivity
                                    if abs(dx) > 0.01 || abs(dy) > 0.01 {
                                        session.send(.trackpadMotion(TrackpadMotionPayload(deltaX: dx, deltaY: dy)))
                                    }
                                }
                                tracker.lastCursorLocation = value.location
                            }
                            .onEnded { value in
                                let totalMove = hypot(value.translation.width, value.translation.height)
                                tracker.lastCursorLocation = nil
                                if totalMove < 6.0 {
                                    haptics.playTrackpadClick()
                                    let mask: MouseButtonMask = session.isDragLockEnabled ? [.left, .dragLock] : .left
                                    session.send(
                                        .trackpadGesture(TrackpadGesturePayload(buttonMask: mask, action: .tapClick))
                                    )
                                }
                            }
                    )

                // Dedicated Smooth Scroll Strip
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.blue.opacity(0.18))
                    .frame(width: 54)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "arrow.up.and.down.circle.fill")
                            Text("Scroll")
                                .font(.caption2.bold())
                        }
                        .foregroundStyle(.white.opacity(0.75))
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

            // Sensitivity & Drag-Lock Bar
            HStack(spacing: 8) {
                Text("Sensibilidad:")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $session.trackpadSensitivity, in: 0.6...3.5)
                Toggle("Arrastrar Fijo", isOn: $session.isDragLockEnabled)
                    .toggleStyle(.button)
                    .controlSize(.small)
                    .onChange(of: session.isDragLockEnabled) { _, locked in
                        haptics.playTrackpadClick()
                        let mask: MouseButtonMask = locked ? [.left, .dragLock] : [.left]
                        let action: ClickAction = locked ? .press : .release
                        session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: mask, action: action)))
                    }
            }

            // Bottom Click & macOS System Gestures Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button("Clic Izq") {
                        haptics.playTrackpadClick()
                        session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .tapClick)))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Doble Clic") {
                        haptics.playTrackpadClick()
                        session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .doubleClick)))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Clic Der") {
                        haptics.playTrackpadClick()
                        session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .right, action: .tapClick)))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    systemGestureButton("Mission Ctrl", gesture: .missionControl)
                    systemGestureButton("Exposé", gesture: .appExpose)
                    systemGestureButton("◀ Space", gesture: .spaceLeft)
                    systemGestureButton("Space ▶", gesture: .spaceRight)
                }
            }
        }
    }

    // MARK: - 2. Keyboard, Dictation & Media Mode

    private var keyboardAndMacrosView: some View {
        VStack(spacing: 10) {
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

            // Tactical Modifier & Shortcut Strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    tacticalKeyButton("Enter ⏎", keyCode: 36)
                    tacticalKeyButton("Borrar ⌫", keyCode: 51)
                    tacticalKeyButton("Espacio", keyCode: 49)
                    tacticalKeyButton("Esc", keyCode: 53)
                    tacticalKeyButton("Tab ⇥", keyCode: 48)
                    tacticalKeyButton("Cmd+C", keyCode: 8, modifiers: [.command])
                    tacticalKeyButton("Cmd+V", keyCode: 9, modifiers: [.command])
                    tacticalKeyButton("Cmd+Z", keyCode: 6, modifiers: [.command])
                    tacticalKeyButton("Spotlight", keyCode: 49, modifiers: [.command])
                }
            }

            // Arrow Keys & Window Navigation
            HStack(spacing: 10) {
                tacticalKeyButton("◀ Izq", keyCode: 123)
                tacticalKeyButton("▲ Arriba", keyCode: 126)
                tacticalKeyButton("▼ Abajo", keyCode: 125)
                tacticalKeyButton("▶ Der", keyCode: 124)
            }

            // Media & System Deck
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    mediaButton("🔉 Vol -", action: .volumeDown)
                    mediaButton("🔇 Mute", action: .mute)
                    mediaButton("🔊 Vol +", action: .volumeUp)
                    mediaButton("⏮ Ant", action: .previousTrack)
                    mediaButton("⏯ Play", action: .playPause)
                    mediaButton("⏭ Sig", action: .nextTrack)
                    mediaButton("🔅 Brillo -", action: .brightnessDown)
                    mediaButton("🔆 Brillo +", action: .brightnessUp)
                    mediaButton("📸 Captura", action: .screenshot)
                }
            }
            Spacer()
        }
    }

    // MARK: - 3. Native Gamepad Mode (Dual Virtual Thumbsticks + Triggers + ABXY)

    private var gamepadSurfaceView: some View {
        VStack(spacing: 10) {
            // Top Shoulder & Analog Triggers Bar (L1/L2 & R1/R2)
            HStack {
                gamepadButton("L2 (Apuntar)", button: .shoulderL1)
                gamepadButton("L1", button: .shoulderL1)
                Spacer()
                gamepadButton("Select", button: .select)
                gamepadButton("Start / Esc", button: .start)
                Spacer()
                gamepadButton("R1", button: .shoulderR1)
                gamepadButton("R2 (Atacar)", button: .shoulderR1)
            }

            HStack(spacing: 16) {
                // Left Analog Thumbstick (WASD / Movement)
                VirtualThumbstickView(label: "Stick Izq (WASD)", radius: 52) { x, y in
                    session.updateLeftStick(x: x, y: y)
                }

                // Center D-Pad
                VStack(spacing: 6) {
                    gamepadButton("▲", button: .dpadUp)
                    HStack(spacing: 8) {
                        gamepadButton("◀", button: .dpadLeft)
                        gamepadButton("▶", button: .dpadRight)
                    }
                    gamepadButton("▼", button: .dpadDown)
                }

                // Right ABXY Cluster
                VStack(spacing: 6) {
                    gamepadButton("Y (R)", button: .northY)
                    HStack(spacing: 8) {
                        gamepadButton("X (E)", button: .westX)
                        gamepadButton("B (Shift)", button: .eastB)
                    }
                    gamepadButton("A (Salto)", button: .southA)
                }

                // Right Analog Thumbstick (Camera Look)
                VirtualThumbstickView(label: "Stick Der (Cámara)", radius: 52) { x, y in
                    session.updateRightStick(x: x, y: y)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 4. Hybrid "Steam Deck" Mode (Left Stick WASD + Right Trackpad Camera + Gyro)

    private var hybridSteamDeckView: some View {
        VStack(spacing: 8) {
            // Top Triggers & Combat Actions
            HStack(spacing: 8) {
                Button("L2 Clic Der (Usar/Apuntar)") {
                    haptics.playTrackpadClick()
                    session.pulseTriggers(l2: 255)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)

                gamepadButton("Saltar (Espacio)", button: .southA)
                gamepadButton("Shift", button: .eastB)
                gamepadButton("Inv (E)", button: .westX)
                gamepadButton("Esc", button: .start)

                Button("R2 Clic Izq (Atacar/Minar)") {
                    haptics.playTrackpadClick()
                    session.pulseTriggers(r2: 255)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.small)
            }

            HStack(spacing: 12) {
                // Left Virtual Analog Stick for 360->WASD movement
                VirtualThumbstickView(label: "Stick Movimiento (WASD)", radius: 58) { x, y in
                    session.updateLeftStick(x: x, y: y)
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // Right High-Precision Camera Trackpad
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.16))
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.title2)
                                .foregroundStyle(.blue)
                            Text("Trackpad de Cámara (Alta Precisión)\nDesliza para mirar • Toca para atacar (Clic Izq)")
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                        }
                    )
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if let last = tracker.lastCameraLocation {
                                    let dx = Double(value.location.x - last.x) * session.cameraSensitivity
                                    let dy = Double(value.location.y - last.y) * session.cameraSensitivity
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
        .controlSize(.small)
    }

    private func mediaButton(_ title: String, action: MediaAction) -> some View {
        Button(title) {
            haptics.playTrackpadClick()
            session.send(.systemMedia(SystemMediaPayload(action: action)))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func gamepadButton(_ title: String, button: GamepadButtons) -> some View {
        Button(title) {
            haptics.playTrackpadClick()
            session.pulseGamepadButton(button)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
}
