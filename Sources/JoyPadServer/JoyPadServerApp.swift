#if os(macOS)
import SwiftUI
import JoyPadProtocol

@main
struct JoyPadServerApp: App {
    @StateObject private var server = JoyPadServerEngine()

    var body: some Scene {
        MenuBarExtra("JoyPad", systemImage: server.activeMode.systemImage) {
            VStack(alignment: .leading, spacing: 8) {
                Text("JoyPad — Universal Pad Server")
                    .font(.headline)

                HStack {
                    Circle()
                        .fill(server.isListening ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(
                        server.connectedPeerName != nil
                            ? "Conectado: \(server.connectedPeerName!)"
                            : (server.isListening ? "Esperando iPhone (AWDL P2P)..." : "Detenido")
                    )
                    .font(.caption)
                }

                Divider()

                Text("Modo Activo: \(server.activeMode.displayName)")
                    .font(.subheadline)

                ForEach(PadMode.allCases, id: \.rawValue) { mode in
                    Button {
                        server.broadcastModeSwitch(mode)
                    } label: {
                        HStack {
                            Image(systemName: mode.systemImage)
                            Text(mode.displayName)
                            if server.activeMode == mode {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                Divider()

                Toggle("Auto-Switch según App (\(server.frontmostAppName))", isOn: $server.autoSwitchModeByApp)

                Text("Paquetes recibidos: \(server.packetsReceived) • RTT: \(server.lastLatencyMs) ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if !server.isAccessibilityTrusted {
                    Button("Autorizar Accesibilidad (CGEvent)...") {
                        server.checkAccessibilityPermissions(prompt: true)
                    }
                }

                Divider()

                Button("Salir de JoyPad Server") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(8)
        }
    }
}
#endif
