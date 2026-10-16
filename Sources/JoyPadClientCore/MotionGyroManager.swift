import Foundation
import JoyPadProtocol
#if canImport(CoreMotion) && os(iOS)
import CoreMotion
#endif

/// Streams 60-100Hz gyroscope angular velocity from iPhone's IMU for Gyro Aiming and Air Mouse control.
@MainActor
public final class MotionGyroManager: ObservableObject {
    @Published public private(set) var isActive: Bool = false

    #if canImport(CoreMotion) && os(iOS)
    private let motionManager = CMMotionManager()
    #endif

    public init() {}

    public func startGyroUpdates(onSample: @escaping @MainActor (GyroMotionPayload) -> Void) {
        guard !isActive else { return }
        isActive = true

        #if canImport(CoreMotion) && os(iOS)
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, self.isActive, let rate = motion?.rotationRate else { return }
            let pitch = Int16(clamping: Int((rate.x * 1000.0).rounded()))
            let yaw   = Int16(clamping: Int((rate.y * 1000.0).rounded()))
            let roll  = Int16(clamping: Int((rate.z * 1000.0).rounded()))
            if abs(pitch) > 15 || abs(yaw) > 15 {
                onSample(GyroMotionPayload(pitchScaled: pitch, yawScaled: yaw, rollScaled: roll))
            }
        }
        #endif
    }

    public func stopGyroUpdates() {
        isActive = false
        #if canImport(CoreMotion) && os(iOS)
        motionManager.stopDeviceMotionUpdates()
        #endif
    }
}
