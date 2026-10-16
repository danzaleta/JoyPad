#if os(macOS)
import Foundation
import Network
import AppKit
import ApplicationServices
import JoyPadProtocol

/// Central P2P Coordinator for the macOS Menu Bar Companion App.
@MainActor
public final class JoyPadServerEngine: ObservableObject {
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var connectedPeerName: String? = nil
    @Published public var activeMode: PadMode = .trackpad
    @Published public var autoSwitchModeByApp: Bool = true
    @Published public private(set) var frontmostAppName: String = "macOS"
    @Published public private(set) var packetsReceived: UInt64 = 0
    @Published public private(set) var lastLatencyMs: UInt32 = 0
    @Published public private(set) var isAccessibilityTrusted: Bool = false

    private var udpListener: NWListener?
    private var activeConnections: [NWConnection] = []
    private var txSequence: UInt16 = 0

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
        checkAccessibilityPermissions(prompt: false)
        setupWorkspaceObserver()
        startListening()
    }

    public func checkAccessibilityPermissions(prompt: Bool) {
        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: prompt] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)
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

        switch frame.payload {
        case .trackpadMotion(let motion):
            trackpadEngine.handleMotion(motion)
        case .trackpadGesture(let gesture):
            trackpadEngine.handleGesture(gesture)
        case .keyboardKey(let key):
            keyboardEngine.handleKey(key)
        case .unicodeText(let text):
            keyboardEngine.handleUnicodeText(text)
        case .systemMedia(let media):
            keyboardEngine.handleMedia(media)
        case .gamepadState(let state):
            gamepadEngine.handleGamepadState(state)
        case .gyroMotion(let gyro):
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
}
#endif
