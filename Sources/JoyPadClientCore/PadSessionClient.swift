import Foundation
import Network
import JoyPadProtocol

/// Client-side AWDL P2P & Direct UDP session manager for iOS/iPadOS.
@MainActor
public final class PadSessionClient: ObservableObject {
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var statusMessage: String = "Buscando Mac (Bonjour / P2P)..."
    @Published public var manualHostIP: String = "192.168.68.109"
    @Published public var activeMode: PadMode = .trackpad
    @Published public var dictationText: String = ""
    @Published public private(set) var rttMilliseconds: UInt32 = 0
    @Published public private(set) var packetsSent: UInt64 = 0

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var sequence: UInt16 = 0
    private var heartbeatTask: Task<Void, Never>?

    public init() {}

    public func startDiscovery() {
        browser?.cancel()
        let params = JoyPadNetworkConfig.makeLowLatencyUDPParameters()
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: JoyPadNetworkConfig.bonjourUDPServiceType,
            domain: nil
        )
        let newBrowser = NWBrowser(for: descriptor, using: params)

        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .failed(let error):
                    self?.statusMessage = "Bonjour error: \(error.localizedDescription)"
                case .waiting(let error):
                    self?.statusMessage = "Permiso Red Local pendiente: \(error.localizedDescription)"
                default:
                    break
                }
            }
        }

        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let first = results.first else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Only auto-connect via Bonjour if we don't already have an active connection
                if !self.isConnected {
                    self.connect(to: first.endpoint, label: "\(first.endpoint)")
                }
            }
        }

        newBrowser.start(queue: .global(qos: .userInteractive))
        self.browser = newBrowser
    }

    /// Connects directly to the Mac's IP address and UDP port (49872).
    public func connectToDirectIP(_ ip: String? = nil) {
        let targetIP = (ip ?? manualHostIP).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !targetIP.isEmpty else { return }
        let host = NWEndpoint.Host(targetIP)
        let port = NWEndpoint.Port(rawValue: JoyPadNetworkConfig.defaultPort)!
        connect(to: .hostPort(host: host, port: port), label: "\(targetIP):\(JoyPadNetworkConfig.defaultPort)")
    }

    public func connect(to endpoint: NWEndpoint, label: String) {
        connection?.cancel()
        heartbeatTask?.cancel()

        statusMessage = "Conectando a \(label)..."
        let params = JoyPadNetworkConfig.makeLowLatencyUDPParameters()
        let conn = NWConnection(to: endpoint, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.statusMessage = "Conectado a \(label)"
                    // Immediately send an initial UDP ping datagram so macOS NWListener registers our peer
                    self.sendPing()
                    self.startHeartbeat()
                case .failed(let err):
                    self.isConnected = false
                    self.statusMessage = "Error: \(err.localizedDescription)"
                case .cancelled:
                    self.isConnected = false
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .userInteractive))
        self.connection = conn
        receiveServerMessages(on: conn)
    }

    public func send(_ payload: JoyPadFramePayload) {
        guard let connection else { return }
        sequence &+= 1
        packetsSent &+= 1
        let data = JoyPadCodec.encode(payload: payload, sequence: sequence)
        connection.send(content: data, completion: .idempotent)
    }

    public func sendPing() {
        let nowMs = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))
        send(.controlSync(ControlSyncPayload(command: .ping, targetMode: activeMode, timestampMs: nowMs)))
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                guard let self, self.isConnected else { break }
                self.sendPing()
            }
        }
    }

    nonisolated private func receiveServerMessages(on conn: NWConnection) {
        conn.receiveMessage { [weak self] content, _, _, error in
            if let data = content, let frame = try? JoyPadCodec.decode(data) {
                Task { @MainActor in
                    self?.handleIncomingFrame(frame)
                }
            }
            if error == nil {
                self?.receiveServerMessages(on: conn)
            }
        }
    }

    private func handleIncomingFrame(_ frame: JoyPadFrame) {
        if case .controlSync(let sync) = frame.payload {
            switch sync.command {
            case .switchMode:
                activeMode = sync.targetMode
            case .pong:
                let nowMs = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))
                if nowMs >= sync.timestampMs {
                    rttMilliseconds = nowMs - sync.timestampMs
                }
            default:
                break
            }
        }
    }
}
