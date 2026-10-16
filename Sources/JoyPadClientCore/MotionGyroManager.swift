import Foundation
import JoyPadProtocol
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
import UIKit
#endif

/// Streams 100Hz gyroscope angular velocity from iPhone's IMU, automatically mapped for Landscape grip.
@MainActor
public final class MotionGyroManager: ObservableObject {
    @Published public private(set) var isActive: Bool = false

    #if canImport(CoreMotion) && os(iOS)
    private let motionManager = CMMotionManager()
    private var smoothedYaw: Double = 0
    private var smoothedPitch: Double = 0
    #endif

    public init() {}

    public func startGyroUpdates(onSample: @escaping @MainActor (GyroMotionPayload) -> Void) {
        guard !isActive else { return }
        isActive = true

        #if canImport(CoreMotion) && os(iOS)
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, self.isActive, let rate = motion?.rotationRate else { return }

            // In Landscape grip, turning the phone left/right rotates around device X/Z axes,
            // and tilting the phone up/down rotates around device Y axis.
            let rawHorizontalYaw = -rate.x - (rate.z * 0.45)
            let rawVerticalPitch = -rate.y

            // Exponential low-pass filter to remove hand tremor while keeping zero-lag responsiveness
            self.smoothedYaw = (self.smoothedYaw * 0.35) + (rawHorizontalYaw * 0.65)
            self.smoothedPitch = (self.smoothedPitch * 0.35) + (rawVerticalPitch * 0.65)

            let yawScaled   = Int16(clamping: Int((self.smoothedYaw * 1000.0).rounded()))
            let pitchScaled = Int16(clamping: Int((self.smoothedPitch * 1000.0).rounded()))
            let rollScaled  = Int16(clamping: Int((rate.z * 1000.0).rounded()))

            if abs(yawScaled) > 4 || abs(pitchScaled) > 4 {
                onSample(GyroMotionPayload(pitchScaled: pitchScaled, yawScaled: yawScaled, rollScaled: rollScaled))
            }
        }
        #endif
    }

    public func stopGyroUpdates() {
        isActive = false
        #if canImport(CoreMotion) && os(iOS)
        motionManager.stopDeviceMotionUpdates()
        smoothedYaw = 0
        smoothedPitch = 0
        #endif
    }
}
