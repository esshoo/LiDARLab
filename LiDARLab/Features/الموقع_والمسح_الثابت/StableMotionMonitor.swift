import CoreMotion
import Foundation

struct StableMotionSnapshot: Sendable {
    let userAccelerationMagnitude: Double
    let rotationRateMagnitude: Double
    let timestamp: TimeInterval

    static let unavailable = StableMotionSnapshot(
        userAccelerationMagnitude: .infinity,
        rotationRateMagnitude: .infinity,
        timestamp: 0
    )

    var indicatesNearStillness: Bool {
        userAccelerationMagnitude < 0.08 && rotationRateMagnitude < 0.16
    }
}

/// A diagnostic-only IMU monitor. It never replaces ARKit Pose and never
/// modifies raw transforms; it only helps label preview breaks that are not
/// supported by physical motion.
final class StableMotionMonitor: @unchecked Sendable {
    private let manager = CMMotionManager()
    private let operationQueue: OperationQueue
    private let lock = NSLock()
    private var latestSnapshot = StableMotionSnapshot.unavailable

    init() {
        let queue = OperationQueue()
        queue.name = "com.essam.3elidar.stable-motion"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 1
        operationQueue = queue

        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let acceleration = motion.userAcceleration
            let rotation = motion.rotationRate
            let accelerationMagnitude = sqrt(
                acceleration.x * acceleration.x
                + acceleration.y * acceleration.y
                + acceleration.z * acceleration.z
            )
            let rotationMagnitude = sqrt(
                rotation.x * rotation.x
                + rotation.y * rotation.y
                + rotation.z * rotation.z
            )
            let snapshot = StableMotionSnapshot(
                userAccelerationMagnitude: accelerationMagnitude,
                rotationRateMagnitude: rotationMagnitude,
                timestamp: motion.timestamp
            )
            self.lock.lock()
            self.latestSnapshot = snapshot
            self.lock.unlock()
        }
    }

    deinit {
        manager.stopDeviceMotionUpdates()
        operationQueue.cancelAllOperations()
    }

    func snapshot() -> StableMotionSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return latestSnapshot
    }
}
