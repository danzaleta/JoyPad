#if os(macOS)
import Foundation
import Network
import AppKit
import ApplicationServices
import JoyPadProtocol

/// Central P2P Coordinator for the macOS Companion App (Menu Bar + Live Monitor Window).
@MainActor
public final class JoyPadServerEngine: ObservableObject {
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var localIPAddress: String = "127.0.0.1"
    @Published public private(set) var connectedPeerName: String? = nil
    @Published public var activeMode: PadMode = .trackpad
    @Published public var autoSwitchModeByApp: Bool = true
    @Published public private(set) var frontmostAppName: String = "macOS"
    @Published public private(set) var packetsReceived: UInt64 = 0
    @Published public private(set) var lastLatencyMs: UInt32 = 0
    @Published public private(set) var isAccessibilityTrusted: Bool = false
    @Published public private(set) var lastEventSummary: String = "Ningún evento recibido aún"

    private var udpListener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var txSequence: UInt16 = 0
    private var permissionPollTask: Task<Void, Never>?

    private let trackpadEngine = TrackpadInjectionEngine()
    private let keyboardEngine = KeyboardInjectionEngine()
    private lazy var gamepadEngine = GamepadInjectionEngine(
        keyboardEngine: keyboardEngine,
        trackpadEngine: trackpadEngine
    )

    private static let gameBundleIdentifiers: Set<String> = [
        "com.valvesoftware.steam",
        "com.mojang.minecraftlauncher",
        "net.java.openjdk.java",
        "com.apple.Arcade"
    ]

    public init() {
        self.localIPAddress = Self.detectLocalWiFiIP() ?? "192.168.68.109"
        checkAccessibilityPermissions(prompt: true)
        startAccessibilityPolling()
        setupWorkspaceObserver()
        startListening()
    }

    public func checkAccessibilityPermissions(prompt: Bool) {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: prompt] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        checkAccessibilityPermissions(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAccessibilityPolling() {
        permissionPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self else { break }
                self.isAccessibilityTrusted = AXIsProcessTrusted()
            }
        }
    }

    public func startListening() {
        guard !isListening else { return }
        do {
            let params = JoyPadNetworkConfig.makeLowLatencyUDPParameters()
            let port = NWEndpoint.Port(rawValue: JoyPadNetworkConfig.defaultPort)!
            let listener = try NWListener(using: params, on: port)

            listener.service = NWListener.Service(
                name: Host.current().localizedName ?? "Mac-JoyPad",
                type: JoyPadNetworkConfig.bonjourUDPServiceType
            )

            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isListening = true
                    case .failed, .cancelled:
                        self?.isListening = false
                    default:
                        break
                    }
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.acceptConnection(connection)
                }
            }

            listener.start(queue: .global(qos: .userInteractive))
            self.udpListener = listener
        } catch {
            self.isListening = false
        }
    }

    public func stopListening() {
        udpListener?.cancel()
        udpListener = nil
        activeConnections.forEach { $0.cancel() }
        activeConnections.removeAll()
        isListening = false
        connectedPeerName = nil
    }

    public func broadcastModeSwitch(_ mode: PadMode) {
        activeMode = mode
        let sync = ControlSyncPayload(
            command: .switchMode,
            targetMode: mode,
            timestampMs: UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))
        )
        txSequence &+= 1
        let data = JoyPadCodec.encode(payload: .controlSync(sync), sequence: txSequence)
        for conn in activeConnections {
            conn.send(content: data, completion: .idempotent)
        }
    }

    private func acceptConnection(_ connection: NWConnection) {
        activeConnections.append(connection)
        connectedPeerName = "\(connection.endpoint)"
        lastEventSummary = "iPhone conectado desde \(connection.endpoint)"
        connection.start(queue: .global(qos: .userInteractive))
        receiveNextDatagram(on: connection)
    }

    nonisolated private func receiveNextDatagram(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            if let data = content, !data.isEmpty {
                Task { @MainActor in
                    self?.processIncomingData(data, from: connection)
                }
            }
            if error == nil {
                self?.receiveNextDatagram(on: connection)
            }
        }
    }

    private func processIncomingData(_ data: Data, from connection: NWConnection) {
        guard let frame = try? JoyPadCodec.decode(data) else { return }
        packetsReceived &+= 1
        if connectedPeerName == nil {
            connectedPeerName = "\(connection.endpoint)"
        }

        switch frame.payload {
        case .trackpadMotion(let motion):
            if motion.scrollDeltaY != 0 || motion.scrollDeltaX != 0 {
                lastEventSummary = "Scroll (dX: \(motion.scrollDeltaX), dY: \(motion.scrollDeltaY))"
            } else {
                lastEventSummary = String(format: "Cursor Δ (%.1f, %.1f)", motion.deltaX, motion.deltaY)
            }
            trackpadEngine.handleMotion(motion)

        case .trackpadGesture(let gesture):
            if gesture.systemGesture != .none {
                lastEventSummary = "Gesto macOS: \(gesture.systemGesture)"
            } else {
                let btn = gesture.buttonMask.contains(.right) ? "Derecho" : "Izquierdo"
                lastEventSummary = "Clic \(btn) (\(gesture.action))"
            }
            trackpadEngine.handleGesture(gesture)

        case .keyboardKey(let key):
            lastEventSummary = "Tecla keyCode=\(key.keyCode) down=\(key.isKeyDown)"
            keyboardEngine.handleKey(key)

        case .unicodeText(let text):
            lastEventSummary = "Texto recibido: \"\(text)\""
            keyboardEngine.handleUnicodeText(text)

        case .systemMedia(let media):
            lastEventSummary = "Acción Multimedia: \(media.action)"
            keyboardEngine.handleMedia(media)

        case .gamepadState(let state):
            lastEventSummary = "Gamepad Buttons=\(state.buttons.rawValue) LX=\(state.leftStickX) LY=\(state.leftStickY)"
            gamepadEngine.handleGamepadState(state)

        case .gyroMotion(let gyro):
            lastEventSummary = "Gyro (Y:\(gyro.yawScaled) P:\(gyro.pitchScaled))"
            gamepadEngine.handleGyro(gyro)

        case .controlSync(let sync):
            handleControlSync(sync, from: connection)
        }
    }

    private func handleControlSync(_ sync: ControlSyncPayload, from connection: NWConnection) {
        switch sync.command {
        case .ping:
            let pong = ControlSyncPayload(
                command: .pong,
                targetMode: activeMode,
                timestampMs: sync.timestampMs
            )
            txSequence &+= 1
            let reply = JoyPadCodec.encode(payload: .controlSync(pong), sequence: txSequence)
            connection.send(content: reply, completion: .idempotent)
        case .pong:
            let nowMs = UInt32(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000))
            if nowMs >= sync.timestampMs {
                lastLatencyMs = nowMs - sync.timestampMs
            }
        case .switchMode:
            activeMode = sync.targetMode
        case .triggerHaptic:
            break
        }
    }

    private func setupWorkspaceObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            let appName = app.localizedName ?? "macOS"
            let bundleID = app.bundleIdentifier ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.frontmostAppName = appName
                guard self.autoSwitchModeByApp else { return }

                let isGame = Self.gameBundleIdentifiers.contains(bundleID)
                    || appName.localizedCaseInsensitiveContains("Minecraft")
                    || appName.localizedCaseInsensitiveContains("Steam")
                let recommendedMode: PadMode = isGame ? .hybridSteamDeck : .trackpad
                if self.activeMode != recommendedMode {
                    self.broadcastModeSwitch(recommendedMode)
                }
            }
        }
    }

    private static func detectLocalWiFiIP() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)
                if name == "en0" || name == "en1" {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        socklen_t(0),
                        NI_NUMERICHOST
                    )
                    let ip = String(cString: hostname)
                    if !ip.hasPrefix("169.254") {
                        address = ip
                        break
                    }
                }
            }
        }
        return address
    }
}
#endif
