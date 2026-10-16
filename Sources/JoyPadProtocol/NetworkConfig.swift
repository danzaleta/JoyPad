import Foundation
import Network

/// Shared P2P AWDL networking configuration for JoyPad.
public enum JoyPadNetworkConfig {
    public static let bonjourUDPServiceType = "_joypad._udp"
    public static let bonjourTCPServiceType = "_joypad._tcp"
    public static let defaultPort: UInt16 = 49872

    /// Creates low-latency UDP parameters configured for Apple Wireless Direct Link (AWDL).
    public static func makeLowLatencyUDPParameters() -> NWParameters {
        let udpOptions = NWProtocolUDP.Options()
        let params = NWParameters(dtls: nil, udp: udpOptions)
        params.includePeerToPeer = true
        params.serviceClass = .interactiveVideo
        return params
    }

    /// Creates reliable, no-delay TCP parameters for discrete events (keystrokes, clicks, sync).
    public static func makeReliableEventParameters() -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.enableFastOpen = true
        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.includePeerToPeer = true
        params.serviceClass = .interactiveVoice
        return params
    }
}
