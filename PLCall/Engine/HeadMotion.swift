import CoreMotion

enum HeadGesture: Sendable {
    case nod, shake
}

/// One axis of head movement: counts direction reversals bigger than a threshold inside a short window.
struct Swing {
    static let threshold = 0.12   // radians, about 7 degrees: smaller moves are just a head held still
    static let window = 2.0       // seconds

    private var extreme: Double?
    private var direction = 0
    private var turns: [TimeInterval] = []

    mutating func count(_ value: Double, at time: TimeInterval) -> Int {
        turns.removeAll { time - $0 > Self.window }
        guard let last = extreme else {
            extreme = value
            return 0
        }
        if direction >= 0, value < last - Self.threshold {
            direction = -1
            extreme = value
            turns.append(time)
        } else if direction <= 0, value > last + Self.threshold {
            direction = 1
            extreme = value
            turns.append(time)
        } else if (direction > 0 && value > last) || (direction < 0 && value < last) {
            extreme = value
        }
        return turns.count
    }
}

/// Reads a nod (pitch) or a shake (yaw). Two full nods or shakes are needed, so a glance down never approves anything.
/// Unchecked Sendable: fed only from HeadMotion's one-at-a-time queue.
final class GestureReader: @unchecked Sendable {
    private var pitch = Swing()
    private var yaw = Swing()
    private var quietUntil: TimeInterval = 0

    func feed(pitch pitchNow: Double, yaw yawNow: Double, at time: TimeInterval) -> HeadGesture? {
        let nods = pitch.count(pitchNow, at: time)
        let shakes = yaw.count(yawNow, at: time)
        guard time >= quietUntil else { return nil }
        let gesture: HeadGesture
        if nods >= 4, shakes <= 1 {
            gesture = .nod
        } else if shakes >= 4, nods <= 1 {
            gesture = .shake
        } else {
            return nil
        }
        quietUntil = time + 2   // one gesture, one answer
        pitch = Swing()
        yaw = Swing()
        return gesture
    }

    /// A made-up double nod must read as a nod, a double shake as a shake, and a slow drift as nothing.
    static func selfCheck() -> Bool {
        func run(_ samples: [(pitch: Double, yaw: Double)]) -> HeadGesture? {
            let reader = GestureReader()
            var found: HeadGesture?
            for (index, sample) in samples.enumerated() {
                if let gesture = reader.feed(pitch: sample.pitch, yaw: sample.yaw, at: Double(index) * 0.2) { found = found ?? gesture }
            }
            return found
        }
        let wave = [0.0, -0.3, 0.0, -0.3, 0.0, -0.3]
        let nod = run(wave.map { (pitch: $0, yaw: 0.0) })
        let shake = run(wave.map { (pitch: 0.0, yaw: $0) })
        let drift = run((0..<8).map { (pitch: Double($0) * 0.05, yaw: 0.0) })
        return nod == .nod && shake == .shake && drift == nil
    }
}

/// AirPods head motion: a nod approves and a shake denies while a permission waits. Needs NSMotionUsageDescription in Info.plist.
@MainActor final class HeadMotion {
    private let manager = CMHeadphoneMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }
    var isDenied: Bool { CMHeadphoneMotionManager.authorizationStatus() == .denied }

    func start() {
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        let reader = GestureReader()
        manager.startDeviceMotionUpdates(to: queue) { @Sendable motion, _ in
            guard let motion else { return }
            guard let gesture = reader.feed(pitch: motion.attitude.pitch, yaw: motion.attitude.yaw, at: motion.timestamp) else { return }
            Task { @MainActor in CallModel.shared.headGesture(gesture) }
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }
}
