import CoreMotion
import Foundation

/// Reads the phone's own rotation and shakes (gyroscope and accelerometer fusion) during
/// Live Guide, so that turning the phone is not reported as « la tasse s'est déplacée ».
/// Device motion needs no permission; samples stay in memory and are never stored.
final class VisionCameraMotionMonitor: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "jarvis.vision.camera-motion"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()
    private let lock = NSLock()
    private var latestAttitude: CMQuaternion?
    private var peakAcceleration: Double = 0

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let acceleration = motion.userAcceleration
            let magnitude = (
                acceleration.x * acceleration.x +
                    acceleration.y * acceleration.y +
                    acceleration.z * acceleration.z
            ).squareRoot()
            self.lock.lock()
            self.latestAttitude = motion.attitude.quaternion
            self.peakAcceleration = max(self.peakAcceleration, magnitude)
            self.lock.unlock()
        }
    }

    func stop() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        lock.lock()
        latestAttitude = nil
        peakAcceleration = 0
        lock.unlock()
    }

    /// The current attitude and the strongest shake since the previous call (which resets it).
    /// Nil when the sensors are unavailable (Simulator) or not started.
    func sample() -> VisionCameraPose? {
        lock.lock()
        defer { lock.unlock() }
        guard let attitude = latestAttitude else { return nil }
        let pose = VisionCameraPose(
            x: attitude.x,
            y: attitude.y,
            z: attitude.z,
            w: attitude.w,
            peakAcceleration: peakAcceleration
        )
        peakAcceleration = 0
        return pose
    }
}
