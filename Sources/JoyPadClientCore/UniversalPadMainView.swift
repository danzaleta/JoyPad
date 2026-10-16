import SwiftUI
import JoyPadProtocol

/// Press-and-hold button state without using @State macro plugins.
@MainActor
final class HoldButtonState: ObservableObject {
    @Published var isPressed: Bool = false
}

/// Interactive button that triggers `onPress` immediately on touch-down and `onRelease` on lift.
struct HoldablePadButton: View {
    let title: String
    let systemImage: String?
    let color: Color
    let minWidth: CGFloat
    let height: CGFloat
    let isCircular: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @StateObject private var state = HoldButtonState()

    init(
        _ title: String,
        systemImage: String? = nil,
        color: Color = .blue,
        minWidth: CGFloat = 52,
        height: CGFloat = 42,
        isCircular: Bool = false,
        onPress: @escaping () -> Void,
        onRelease: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
        self.minWidth = minWidth
        self.height = height
        self.isCircular = isCircular
        self.onPress = onPress
        self.onRelease = onRelease
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.bold())
            }
            if !title.isEmpty {
                Text(title)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
        }
        .frame(minWidth: isCircular ? height : minWidth, minHeight: height)
        .padding(.horizontal, isCircular ? 0 : 10)
        .background(state.isPressed ? color.opacity(0.95) : color.opacity(0.28))
        .overlay(
            Group {
                if isCircular {
                    Circle().stroke(color.opacity(0.85), lineWidth: state.isPressed ? 2.5 : 1.5)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.85), lineWidth: state.isPressed ? 2.5 : 1.5)
                }
            }
        )
        .clipShape(isCircular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
        .scaleEffect(state.isPressed ? 0.94 : 1.0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !state.isPressed {
                        state.isPressed = true
                        onPress()
                    }
                }
                .onEnded { _ in
                    if state.isPressed {
                        state.isPressed = false
                        onRelease()
                    }
                }
        )
    }
}

/// Tracks frame-to-frame touch deltas for fallback platforms.
@MainActor
final class TouchDeltaTracker: ObservableObject {
    var lastCursorLocation: CGPoint? = nil
    var lastPreviousText: String = ""
}

/// Edge-to-edge multi-mode UI for the JoyPad Universal Client (Trackpad, Keyboard, Gamepad, Hybrid).
public struct UniversalPadMainView: View {
    @ObservedObject private var session: PadSessionClient
    @StateObject private var tracker = TouchDeltaTracker()
    @Environment(\.scenePhase) private var scenePhase
    private let haptics = TapticEngineManager()

    public init(session: PadSessionClient) {
        self.session = session
    }

    public var body: some View {
        VStack(spacing: 6) {
            compactTopHUD
            activeModeContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black)
        .foregroundStyle(.white)
        .sheet(isPresented: $session.isSettingsPresented) {
            settingsSheetView
        }
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

    // MARK: - Single-Line Compact HUD Bar (Maximizes Active Area)

    private var compactTopHUD: some View {
        HStack(spacing: 6) {
            // Connection Pill (Tap to open Settings / IP)
            Button {
                haptics.playTrackpadClick()
                session.isSettingsPresented = true
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(session.isConnected ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("\(session.rttMilliseconds)ms")
                        .font(.caption2.monospaced().bold())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Compact Mode Tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(PadMode.allCases, id: \.rawValue) { mode in
                        Button {
                            haptics.playTrackpadClick()
                            session.activeMode = mode
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: mode.systemImage)
                                    .font(.caption)
                                Text(shortName(for: mode))
                                    .font(.caption.bold())
                            }
                            .padding(.vertical, 5)
                            .padding(.horizontal, 10)
                            .background(session.activeMode == mode ? Color.blue : Color.white.opacity(0.09))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 4)

            // Gyro Aim / Air Mouse Quick Toggle
            Button {
                haptics.playTrackpadClick()
                session.isGyroEnabled.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "gyroscope")
                    Text("Gyro")
                        .font(.caption2.bold())
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 9)
                .background(session.isGyroEnabled ? Color.purple : Color.white.opacity(0.1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            // Settings Button
            Button {
                haptics.playTrackpadClick()
                session.isSettingsPresented = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.bold())
                    .padding(6)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    private func shortName(for mode: PadMode) -> String {
        switch mode {
        case .trackpad:        return "Trackpad"
        case .keyboard:        return "Teclado"
        case .gamepad:         return "Gamepad"
        case .hybridSteamDeck: return "Híbrido"
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

    // MARK: - 1. Full-Screen Multitouch Magic Trackpad Mode

    private var trackpadSurfaceView: some View {
        ZStack(alignment: .bottom) {
            // Edge-to-Edge Multitouch Trackpad Surface
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .overlay(
                    VStack(spacing: 6) {
                        Image(systemName: "hand.draw.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.22))
                        Text("1 dedo: Cursor y Clic • Doble-Tap: Arrastrar • 2 dedos: Scroll, Clic Der y Zoom • 3 dedos: Mission Control y Spaces • 4 dedos: Escritorio")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.32))
                            .padding(.horizontal, 24)
                    }
                    .allowsHitTesting(false)
                )
                .overlay(multitouchTrackpadOverlay(sensitivity: session.trackpadSensitivity))

            // Minimal Bottom Thumb Bar for Physical Hold-Click & Drag
            HStack(spacing: 10) {
                HoldablePadButton("Clic Izq", color: .blue, minWidth: 90, height: 34) {
                    haptics.playTrackpadClick()
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: [.left, .dragLock], action: .press)))
                } onRelease: {
                    haptics.playTrackpadClick(isRelease: true)
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .release)))
                }

                Spacer()

                HoldablePadButton("Clic Der", color: .indigo, minWidth: 90, height: 34) {
                    haptics.playTrackpadClick()
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .right, action: .press)))
                } onRelease: {
                    haptics.playTrackpadClick(isRelease: true)
                    session.send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .right, action: .release)))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func multitouchTrackpadOverlay(sensitivity: Double) -> some View {
        #if canImport(UIKit)
        NativeMultitouchTrackpadView(
            sensitivity: sensitivity,
            onMotion: { motion in
                session.send(.trackpadMotion(motion))
            },
            onGesture: { gesture in
                session.send(.trackpadGesture(gesture))
            },
            onHaptic: { isRelease in
                haptics.playTrackpadClick(isRelease: isRelease)
            }
        )
        #else
        Color.clear
        #endif
    }

    // MARK: - 2. Live Keyboard, Dictation & StreamDeck Macropad Mode

    private var keyboardAndMacrosView: some View {
        VStack(spacing: 8) {
            // Live Real-Time Input & Voice Dictation Bar
            HStack(spacing: 8) {
                Image(systemName: "mic.and.signal.meter.fill")
                    .foregroundStyle(.blue)
                TextField("Escribe en vivo o dicta por voz aquí...", text: $session.dictationText)
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(.black)
                    .onChange(of: session.dictationText) { oldVal, newVal in
                        if newVal.count > oldVal.count, newVal.hasPrefix(oldVal) {
                            let added = String(newVal.dropFirst(oldVal.count))
                            session.send(.unicodeText(added))
                        } else if newVal.count < oldVal.count, oldVal.hasPrefix(newVal) {
                            let deletedCount = oldVal.count - newVal.count
                            for _ in 0..<deletedCount {
                                session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 51, isKeyDown: true)))
                                session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 51, isKeyDown: false)))
                            }
                        }
                    }
                    .onSubmit {
                        session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 36, isKeyDown: true)))
                        session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 36, isKeyDown: false)))
                        session.dictationText = ""
                    }

                Button("Limpiar") {
                    haptics.playTrackpadClick()
                    session.dictationText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 10) {
                // Left & Center: StreamDeck Tactical Macro Grid (2 Rows x 5 Columns)
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        macroDeckCard("Esc", icon: "escape", color: .red) {
                            sendKeyTap(53)
                        }
                        macroDeckCard("Tab", icon: "arrow.right.to.line", color: .gray) {
                            sendKeyTap(48)
                        }
                        macroDeckCard("Copiar", icon: "doc.on.doc", color: .blue) {
                            sendKeyTap(8, modifiers: [.command])
                        }
                        macroDeckCard("Pegar", icon: "doc.on.clipboard", color: .blue) {
                            sendKeyTap(9, modifiers: [.command])
                        }
                        macroDeckCard("Deshacer", icon: "arrow.uturn.backward", color: .orange) {
                            sendKeyTap(6, modifiers: [.command])
                        }
                    }

                    HStack(spacing: 8) {
                        macroDeckCard("Spotlight", icon: "magnifyingglass", color: .purple) {
                            session.send(.systemMedia(SystemMediaPayload(action: .spotlight)))
                        }
                        macroDeckCard("Captura", icon: "camera.viewfinder", color: .mint) {
                            session.send(.systemMedia(SystemMediaPayload(action: .screenshot)))
                        }
                        macroDeckCard("Vol -", icon: "speaker.wave.1.fill", color: .teal) {
                            session.send(.systemMedia(SystemMediaPayload(action: .volumeDown)))
                        }
                        macroDeckCard("Play/Pause", icon: "playpause.fill", color: .green) {
                            session.send(.systemMedia(SystemMediaPayload(action: .playPause)))
                        }
                        macroDeckCard("Vol +", icon: "speaker.wave.3.fill", color: .teal) {
                            session.send(.systemMedia(SystemMediaPayload(action: .volumeUp)))
                        }
                    }

                    HStack(spacing: 8) {
                        macroDeckCard("Brillo -", icon: "sun.min.fill", color: .yellow) {
                            session.send(.systemMedia(SystemMediaPayload(action: .brightnessDown)))
                        }
                        macroDeckCard("Brillo +", icon: "sun.max.fill", color: .yellow) {
                            session.send(.systemMedia(SystemMediaPayload(action: .brightnessUp)))
                        }
                        macroDeckCard("Espacio", icon: "space", color: .gray) {
                            sendKeyTap(49)
                        }
                        macroDeckCard("Borrar", icon: "delete.left.fill", color: .orange) {
                            sendKeyTap(51)
                        }
                        macroDeckCard("Enter", icon: "return", color: .blue) {
                            sendKeyTap(36)
                        }
                    }
                }

                // Right: Ergonomic Arrow Key Cluster (Holdable!)
                VStack(spacing: 6) {
                    HoldablePadButton("▲", color: .white, minWidth: 48, height: 42) {
                        haptics.playTrackpadClick()
                        session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 126, isKeyDown: true)))
                    } onRelease: {
                        session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 126, isKeyDown: false)))
                    }

                    HStack(spacing: 6) {
                        HoldablePadButton("◀", color: .white, minWidth: 48, height: 42) {
                            haptics.playTrackpadClick()
                            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 123, isKeyDown: true)))
                        } onRelease: {
                            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 123, isKeyDown: false)))
                        }

                        HoldablePadButton("▼", color: .white, minWidth: 48, height: 42) {
                            haptics.playTrackpadClick()
                            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 125, isKeyDown: true)))
                        } onRelease: {
                            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 125, isKeyDown: false)))
                        }

                        HoldablePadButton("▶", color: .white, minWidth: 48, height: 42) {
                            haptics.playTrackpadClick()
                            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 124, isKeyDown: true)))
                        } onRelease: {
                            session.send(.keyboardKey(KeyboardKeyPayload(keyCode: 124, isKeyDown: false)))
                        }
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - 3. Ergonomic Console Gamepad Mode (Holdable Buttons + Dual Analog Sticks)

    private var gamepadSurfaceView: some View {
        VStack(spacing: 8) {
            // Top Shoulder & Analog Triggers Row (Holdable!)
            HStack(spacing: 12) {
                HoldablePadButton("L2 Apuntar", color: .orange, minWidth: 105, height: 38) {
                    haptics.playTrackpadClick()
                    session.setTriggers(l2: 255)
                } onRelease: {
                    session.setTriggers(l2: 0)
                }

                HoldablePadButton("L1", color: .blue, minWidth: 64, height: 38) {
                    haptics.playTrackpadClick()
                    session.setGamepadButton(.shoulderL1, isPressed: true)
                } onRelease: {
                    session.setGamepadButton(.shoulderL1, isPressed: false)
                }

                Spacer()

                HoldablePadButton("Tab / Mapa", color: .gray, minWidth: 80, height: 32) {
                    haptics.playTrackpadClick()
                    session.setGamepadButton(.select, isPressed: true)
                } onRelease: {
                    session.setGamepadButton(.select, isPressed: false)
                }

                HoldablePadButton("Esc / Pausa", color: .gray, minWidth: 84, height: 32) {
                    haptics.playTrackpadClick()
                    session.setGamepadButton(.start, isPressed: true)
                } onRelease: {
                    session.setGamepadButton(.start, isPressed: false)
                }

                Spacer()

                HoldablePadButton("R1", color: .blue, minWidth: 64, height: 38) {
                    haptics.playTrackpadClick()
                    session.setGamepadButton(.shoulderR1, isPressed: true)
                } onRelease: {
                    session.setGamepadButton(.shoulderR1, isPressed: false)
                }

                HoldablePadButton("R2 Atacar", color: .red, minWidth: 105, height: 38) {
                    haptics.playTrackpadClick()
                    session.setTriggers(r2: 255)
                } onRelease: {
                    session.setTriggers(r2: 0)
                }
            }

            Spacer(minLength: 2)

            // Main Ergonomic Dual-Stick + D-Pad + Diamond ABXY Cluster
            HStack(spacing: 18) {
                // Left Analog Stick
                VirtualThumbstickView(label: "Movimiento (WASD)", radius: 64) { x, y in
                    session.updateLeftStick(x: x, y: y)
                }

                // Holdable D-Pad Cross
                VStack(spacing: 4) {
                    holdableGamepadButton("▲", button: .dpadUp, color: .gray, size: 42)
                    HStack(spacing: 28) {
                        holdableGamepadButton("◀", button: .dpadLeft, color: .gray, size: 42)
                        holdableGamepadButton("▶", button: .dpadRight, color: .gray, size: 42)
                    }
                    holdableGamepadButton("▼", button: .dpadDown, color: .gray, size: 42)
                }

                Spacer()

                // Diamond ABXY Cluster (Color-Coded & Holdable!)
                VStack(spacing: 4) {
                    holdableGamepadButton("Y", button: .northY, color: .yellow, size: 46, isCircular: true)
                    HStack(spacing: 30) {
                        holdableGamepadButton("X", button: .westX, color: .blue, size: 46, isCircular: true)
                        holdableGamepadButton("B", button: .eastB, color: .red, size: 46, isCircular: true)
                    }
                    holdableGamepadButton("A", button: .southA, color: .green, size: 46, isCircular: true)
                }

                // Right Analog Stick
                VirtualThumbstickView(label: "Cámara 360°", radius: 64) { x, y in
                    session.updateRightStick(x: x, y: y)
                }
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 2)
        }
    }

    // MARK: - 4. Hybrid "Steam Deck" Mode (Left Analog Stick + Right Multitouch Camera Pad)

    private var hybridSteamDeckView: some View {
        HStack(spacing: 10) {
            // Left Zone (36% width): Analog WASD Stick + Holdable Combat Actions
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    HoldablePadButton("L2 Usar (Clic Der)", color: .orange, minWidth: 110, height: 36) {
                        haptics.playTrackpadClick()
                        session.setTriggers(l2: 255)
                    } onRelease: {
                        session.setTriggers(l2: 0)
                    }

                    HoldablePadButton("Esc", color: .gray, minWidth: 44, height: 36) {
                        haptics.playTrackpadClick()
                        session.setGamepadButton(.start, isPressed: true)
                    } onRelease: {
                        session.setGamepadButton(.start, isPressed: false)
                    }
                }

                VirtualThumbstickView(label: "Stick WASD", radius: 58) { x, y in
                    session.updateLeftStick(x: x, y: y)
                }

                HStack(spacing: 6) {
                    holdableGamepadButton("Saltar", button: .southA, color: .green, size: 36)
                    holdableGamepadButton("Shift", button: .eastB, color: .red, size: 36)
                    holdableGamepadButton("Inv (E)", button: .westX, color: .blue, size: 36)
                    holdableGamepadButton("Rec (R)", button: .northY, color: .yellow, size: 36)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            // Right Zone (64% width): Holdable R2 Attack Trigger + Huge Multitouch Camera Trackpad
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("CÁMARA DE ALTA PRECISIÓN")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    HoldablePadButton("R2 Atacar / Minar (Mantener)", color: .red, minWidth: 165, height: 36) {
                        haptics.playTrackpadClick()
                        session.setTriggers(r2: 255)
                    } onRelease: {
                        session.setTriggers(r2: 0)
                    }
                }

                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.18), Color.indigo.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.blue.opacity(0.35), lineWidth: 1)
                    )
                    .overlay(
                        VStack(spacing: 4) {
                            Image(systemName: "scope")
                                .font(.title2)
                                .foregroundStyle(.blue.opacity(0.45))
                            Text("1 dedo: Mirar y Tap Atacar • 2 dedos: Clic Der (Colocar bloque) y Scroll Hotbar")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, 16)
                        }
                        .allowsHitTesting(false)
                    )
                    .overlay(multitouchTrackpadOverlay(sensitivity: session.cameraSensitivity))
            }
        }
    }

    // MARK: - Settings Popover Sheet (Frees Screen Real Estate)

    private var settingsSheetView: some View {
        NavigationStack {
            Form {
                Section("Conexión con tu Mac") {
                    HStack {
                        Text("IP de la Mac")
                        Spacer()
                        TextField("192.168.68.109", text: $session.manualHostIP)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospaced())
                    }
                    Button("Conectar Ahora") {
                        haptics.playTrackpadClick()
                        session.connectToDirectIP()
                        session.isSettingsPresented = false
                    }
                }

                Section("Sensibilidad y Respuesta") {
                    VStack(alignment: .leading) {
                        Text(String(format: "Sensibilidad Trackpad: %.2fx", session.trackpadSensitivity))
                        Slider(value: $session.trackpadSensitivity, in: 0.5...4.0)
                    }
                    VStack(alignment: .leading) {
                        Text(String(format: "Sensibilidad Cámara (Híbrido): %.2fx", session.cameraSensitivity))
                        Slider(value: $session.cameraSensitivity, in: 0.5...4.5)
                    }
                    Toggle("Giroscopio (Air Mouse / Gyro Aim)", isOn: $session.isGyroEnabled)
                }
            }
            .navigationTitle("Ajustes de JoyPad")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        session.isSettingsPresented = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Helpers

    private func holdableGamepadButton(
        _ title: String,
        button: GamepadButtons,
        color: Color,
        size: CGFloat,
        isCircular: Bool = false
    ) -> some View {
        HoldablePadButton(
            title,
            color: color,
            minWidth: size,
            height: size,
            isCircular: isCircular
        ) {
            haptics.playTrackpadClick()
            session.setGamepadButton(button, isPressed: true)
        } onRelease: {
            session.setGamepadButton(button, isPressed: false)
        }
    }

    private func macroDeckCard(
        _ title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            haptics.playTrackpadClick()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline.bold())
                Text(title)
                    .font(.caption2.bold())
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 6)
            .background(color.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.55), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func sendKeyTap(_ keyCode: UInt16, modifiers: KeyModifiers = []) {
        session.send(.keyboardKey(KeyboardKeyPayload(keyCode: keyCode, modifiers: modifiers, isKeyDown: true)))
        session.send(.keyboardKey(KeyboardKeyPayload(keyCode: keyCode, modifiers: modifiers, isKeyDown: false)))
    }
}
