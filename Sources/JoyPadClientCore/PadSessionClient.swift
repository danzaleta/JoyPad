import Foundation
import Network
import JoyPadProtocol

/// Client-side AWDL P2P session manager for iOS/iPadOS.
@MainActor
public final class PadSessionClient: ObservableObject {
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var discoveredServerName: String? = nil
    @Published public var activeMode: PadMode = .trackpad
    @Published public var dictationText: String = ""
    @Published public private(set) var rttMilliseconds: UInt32 = 0

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var sequence: UInt16 = 0

    public init() {}

    public func startDiscovery() {
        let params = JoyPadNetworkConfig.makeLowLatencyUDPParameters()
        let descriptor = NWBrowser.Descriptor.bonjour(
            type: JoyPadNetworkConfig.bonjourUDPServiceType,
            domain: nil
        )
        let browser = NWBrowser(for: descriptor, using: params)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let first = results.first else { return }
            Task { @MainActor in
                self?.connect(to: first.endpoint)
            }
        }

        browser.start(queue: .global(qos: .userInteractive))
        self.browser = browser
    }

    public func connect(to endpoint: NWEndpoint) {
        connection?.cancel()
        let params = JoyPadNetworkConfig.makeLowLatencyUDPParameters()
        let conn = NWConnection(to: endpoint, using: params)

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.discoveredServerName = "\(endpoint)"
                case .failed, .cancelled:
                    self?.isConnected = false
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
        guard let connection, isConnected else { return }
        sequence &+= 1
        let data = JoyPadCodec.encode(payload: payload, sequence: sequence)
        connection.send(content: data, completion: .idempotent)
    }

    public func sendPing() {
        let nowMs = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))
        send(.controlSync(ControlSyncPayload(command: .ping, targetMode: activeMode, timestampMs: nowMs)))
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
