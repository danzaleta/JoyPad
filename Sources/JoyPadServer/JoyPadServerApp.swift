#if os(macOS)
import SwiftUI
import JoyPadProtocol

@main
struct JoyPadServerApp: App {
    @StateObject private var server = JoyPadServerEngine()

    var body: some Scene {
        WindowGroup("JoyPad — Monitor en Vivo (macOS)") {
            ServerDashboardView(server: server)
                .frame(minWidth: 440, minHeight: 320)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("JoyPad", systemImage: server.activeMode.systemImage) {
            ServerDashboardView(server: server)
        }
    }
}

struct ServerDashboardView: View {
    @ObservedObject var server: JoyPadServerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: server.activeMode.systemImage)
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("JoyPad — Universal Pad Server")
                        .font(.headline)
                    Text("IP de esta Mac: \(server.localIPAddress):\(JoyPadNetworkConfig.defaultPort)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            // Connection Status
            HStack {
                Circle()
                    .fill(server.connectedPeerName != nil ? Color.green : (server.isListening ? Color.orange : Color.red))
                    .frame(width: 10, height: 10)
                Text(
                    server.connectedPeerName != nil
                        ? "iPhone Conectado (\(server.connectedPeerName!))"
                        : (server.isListening ? "Escuchando en \(server.localIPAddress):49872 (AWDL / UDP)..." : "Servidor Detenido")
                )
                .font(.subheadline.bold())
            }

            // Accessibility Status Banner
            HStack {
                Image(systemName: server.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(server.isAccessibilityTrusted ? .green : .yellow)
                Text(
                    server.isAccessibilityTrusted
                        ? "Permiso de Accesibilidad Activo (Inyección CGEvent habilitada)"
                        : "Falta Permiso de Accesibilidad para mover el cursor/teclado"
                )
                .font(.caption)
                Spacer()
                if !server.isAccessibilityTrusted {
                    Button("Autorizar...") {
                        server.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding(8)
            .background((server.isAccessibilityTrusted ? Color.green : Color.yellow).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Live Event Telemetry Box
            VStack(alignment: .leading, spacing: 4) {
                Text("MONITOR EN VIVO (Paquetes recibidos: \(server.packetsReceived))")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(server.lastEventSummary)
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Divider()

            HStack {
                Text("Forzar Modo en iPhone:")
                    .font(.caption)
                ForEach(PadMode.allCases, id: \.rawValue) { mode in
                    Button(mode.displayName) {
                        server.broadcastModeSwitch(mode)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            HStack {
                Toggle("Auto-Switch según App (\(server.frontmostAppName))", isOn: $server.autoSwitchModeByApp)
                    .font(.caption)
                Spacer()
                Button("Salir") {
                    NSApplication.shared.terminate(nil)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
    }
}
#endif
