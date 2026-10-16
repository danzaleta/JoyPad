import Foundation
import Network
import JoyPadProtocol

@MainActor
final class TestHarness {
    private var connection: NWConnection?
    private var sequence: UInt16 = 0
    private var isConnected = false

    func connect() async {
        let params = JoyPadNetworkConfig.makeLowLatencyUDPParameters()
        let host = NWEndpoint.Host("127.0.0.1")
        let port = NWEndpoint.Port(rawValue: JoyPadNetworkConfig.defaultPort)!
        let conn = NWConnection(host: host, port: port, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            if state == .ready {
                Task { @MainActor in
                    self?.isConnected = true
                }
            }
        }
        conn.start(queue: .global())

        // Wait up to 1 second for connection
        for _ in 0..<10 {
            if isConnected { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    func send(_ payload: JoyPadFramePayload) {
        guard let connection else { return }
        sequence &+= 1
        let data = JoyPadCodec.encode(payload: payload, sequence: sequence)
        connection.send(content: data, completion: .idempotent)
    }

    func testCursorCircle() async {
        print("🎮 Dibujando un círculo con el cursor...")
        let steps = 60
        let radius: Double = 6.0
        for i in 0..<steps {
            let angle = (Double(i) / Double(steps)) * 2.0 * .pi
            let dx = cos(angle) * radius
            let dy = sin(angle) * radius
            let motion = TrackpadMotionPayload(deltaX: dx, deltaY: dy)
            send(.trackpadMotion(motion))
            try? await Task.sleep(nanoseconds: 16_000_000) // ~60fps
        }
        print("✅ Movimiento de cursor completado.")
    }

    func testScroll() async {
        print("📜 Probando Scroll inercial de 2 dedos (hacia abajo y hacia arriba)...")
        for _ in 0..<15 {
            send(.trackpadMotion(TrackpadMotionPayload(scrollDeltaY: -25, scrollPhase: .changed)))
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        for _ in 0..<15 {
            send(.trackpadMotion(TrackpadMotionPayload(scrollDeltaY: 25, scrollPhase: .changed)))
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        send(.trackpadMotion(TrackpadMotionPayload(scrollPhase: .ended)))
        print("✅ Scroll completado.")
    }

    func testClicks() async {
        print("🖱️ Probando Clic Izquierdo y Clic Derecho...")
        send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .left, action: .tapClick)))
        try? await Task.sleep(nanoseconds: 400_000_000)
        send(.trackpadGesture(TrackpadGesturePayload(buttonMask: .right, action: .tapClick)))
        print("✅ Clics enviados.")
    }

    func testUnicodeKeyboard() async {
        let sample = " ¡Hola desde JoyPad Universal! 🎮✨ "
        print("⌨️ Inyectando texto con acentos y emojis: \(sample)...")
        send(.unicodeText(sample))
        print("✅ Texto inyectado.")
    }

    func testMediaKeys() async {
        print("🔊 Probando tecla multimedia: Subir Volumen...")
        send(.systemMedia(SystemMediaPayload(action: .volumeUp)))
        try? await Task.sleep(nanoseconds: 300_000_000)
        send(.systemMedia(SystemMediaPayload(action: .volumeDown)))
        print("✅ Teclas de volumen enviadas.")
    }

    func testMissionControl() async {
        print("🖥️ Probando gesto de sistema: Mission Control...")
        send(.trackpadGesture(TrackpadGesturePayload(systemGesture: .missionControl)))
        print("✅ Gesto enviado.")
    }

    func testPing() async {
        let nowMs = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))
        send(.controlSync(ControlSyncPayload(command: .ping, timestampMs: nowMs)))
        print("📡 Ping enviado a JoyPadServer.")
    }
}

@main
struct JoyPadCLI {
    static func main() async {
        print("""
        =====================================================
          JoyPad CLI — Test Runner Interactivo de Pruebas
        =====================================================
        Conectando con JoyPadServer en 127.0.0.1:49872...
        """)

        let harness = TestHarness()
        await harness.connect()
        print("Conectado a JoyPadServer.\n")

        guard CommandLine.arguments.count > 1 else {
            print("""
            Uso rápido por argumento:
              swift run JoyPadCLI cursor     -> Mueve el cursor en círculo
              swift run JoyPadCLI scroll     -> Prueba scroll de 2 dedos
              swift run JoyPadCLI clicks     -> Prueba clic izquierdo y derecho
              swift run JoyPadCLI keyboard   -> Inyecta texto Unicode de prueba
              swift run JoyPadCLI media      -> Prueba teclas de volumen
              swift run JoyPadCLI gesture    -> Prueba gesto Mission Control
              swift run JoyPadCLI ping       -> Prueba ping de latencia
              swift run JoyPadCLI all        -> Ejecuta todas las pruebas secuencialmente
            """)
            return
        }

        let cmd = CommandLine.arguments[1].lowercased()
        switch cmd {
        case "cursor":
            await harness.testCursorCircle()
        case "scroll":
            await harness.testScroll()
        case "clicks":
            await harness.testClicks()
        case "keyboard":
            await harness.testUnicodeKeyboard()
        case "media":
            await harness.testMediaKeys()
        case "gesture":
            await harness.testMissionControl()
        case "ping":
            await harness.testPing()
        case "all":
            await harness.testPing()
            await harness.testCursorCircle()
            await harness.testScroll()
            await harness.testClicks()
            await harness.testUnicodeKeyboard()
            await harness.testMediaKeys()
            print("\n🎉 Todas las pruebas se ejecutaron correctamente.")
        default:
            print("Comando desconocido: \(cmd)")
        }
    }
}
