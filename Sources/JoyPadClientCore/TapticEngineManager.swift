import Foundation
import CoreHaptics

/// Emulates MacBook Magic Trackpad Force Touch clicks and Gamepad rumble via `CoreHaptics`.
@MainActor
public final class TapticEngineManager {
    private var engine: CHHapticEngine?

    public init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            engine = nil
        }
    }

    /// Simulates the crisp physical click of a MacBook Force Touch trackpad.
    public func playTrackpadClick(isRelease: Bool = false) {
        guard let engine else { return }
        let intensity = CHHapticEventParameter(
            parameterID: .hapticIntensity,
            value: isRelease ? 0.55 : 0.95
        )
        let sharpness = CHHapticEventParameter(
            parameterID: .hapticSharpness,
            value: isRelease ? 0.70 : 0.95
        )
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [intensity, sharpness],
            relativeTime: 0
        )
        if let pattern = try? CHHapticPattern(events: [event], parameters: []),
           let player = try? engine.makePlayer(with: pattern) {
            try? player.start(atTime: 0)
        }
    }
}
