import CoreGraphics
import Foundation

/// One hand measured in the coordinates of the AR view (points, origin top-left).
/// Produced by `JarvisHandPoseTracker` from Vision landmarks; kept free of Vision types
/// so the gesture logic can be tested without a camera.
struct JarvisHandSample: Equatable {
    var thumbTip: CGPoint
    var indexTip: CGPoint
    var thumbConfidence: Float
    var indexConfidence: Float
    /// Visible size of the hand in points (wrist to middle-finger knuckle). Dividing the
    /// fingertip distance by it makes the pinch independent of the hand's distance to
    /// the camera.
    var handSize: CGFloat

    var pinchMidpoint: CGPoint {
        CGPoint(x: (thumbTip.x + indexTip.x) / 2, y: (thumbTip.y + indexTip.y) / 2)
    }

    var pinchRatio: CGFloat {
        guard handSize > 0 else { return .greatestFiniteMagnitude }
        return hypot(thumbTip.x - indexTip.x, thumbTip.y - indexTip.y) / handSize
    }

    var minimumConfidence: Float { min(thumbConfidence, indexConfidence) }
}

/// Thresholds of the pinch state machine. Two distinct ratios (hysteresis) keep a
/// trembling hand from toggling between "pinched" and "open".
struct JarvisPinchConfiguration: Equatable {
    var closeRatio: CGFloat = 0.30
    var openRatio: CGFloat = 0.50
    var minimumConfidence: Float = 0.40
    /// Consecutive analysed frames needed to confirm a change of phase.
    var framesToConfirm = 2
    /// A hand missing for less than this keeps the gesture frozen; longer ends it.
    var lostTimeout: TimeInterval = 0.35
    /// Weight of the newest sample in the smoothed aim point (0...1).
    var smoothing: CGFloat = 0.55

    private static let closeKey = "JarvisXR.pinch.closeRatio"
    private static let openKey = "JarvisXR.pinch.openRatio"

    static func load(from defaults: UserDefaults = .standard) -> JarvisPinchConfiguration {
        var configuration = JarvisPinchConfiguration()
        let close = defaults.double(forKey: closeKey)
        let open = defaults.double(forKey: openKey)
        if close > 0, open > close {
            configuration.closeRatio = CGFloat(close)
            configuration.openRatio = CGFloat(open)
        }
        return configuration
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(Double(closeRatio), forKey: Self.closeKey)
        defaults.set(Double(openRatio), forKey: Self.openKey)
    }

    static func resetSaved(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: closeKey)
        defaults.removeObject(forKey: openKey)
    }
}

enum JarvisPinchEndReason: Equatable {
    /// The fingers opened.
    case released
    /// The hand left the image or could not be measured for too long.
    case handLost
}

enum JarvisPinchEvent: Equatable {
    case began(CGPoint)
    case moved(CGPoint)
    case ended(CGPoint, JarvisPinchEndReason)
}

/// Turns a stream of hand samples into pinch events.
///
/// Rules, matching the field checklist:
/// - a hand that enters the frame already pinched never grabs; the fingers must open
///   first (`isArmed`);
/// - small tremors between the two thresholds change nothing;
/// - a brief detection gap freezes the gesture (no movement) instead of ending it;
/// - a longer gap ends it with `.handLost`, and a new grab needs open fingers again.
struct JarvisPinchDetector {
    enum Phase: Equatable {
        case noHand
        case open
        case pinched
    }

    var configuration: JarvisPinchConfiguration
    private(set) var phase: Phase = .noHand
    private(set) var isArmed = false
    private(set) var isPinchActive = false
    private(set) var aimPoint: CGPoint?
    private(set) var lastRatio: CGFloat?
    private var lastValidTime: TimeInterval?
    private var closedStreak = 0
    private var openStreak = 0

    init(configuration: JarvisPinchConfiguration = JarvisPinchConfiguration()) {
        self.configuration = configuration
    }

    /// True when the fingers are closed but cannot grab yet (entered pinched, or the
    /// last grab was cancelled): the interface asks the user to open the fingers.
    var needsReopen: Bool { phase == .pinched && !isPinchActive && !isArmed }

    mutating func update(with sample: JarvisHandSample?, at time: TimeInterval) -> [JarvisPinchEvent] {
        guard let sample,
              sample.minimumConfidence >= configuration.minimumConfidence,
              sample.handSize > 1 else {
            return handleMissingHand(at: time)
        }
        lastValidTime = time
        let ratio = sample.pinchRatio
        lastRatio = ratio

        let raw = sample.pinchMidpoint
        let aim: CGPoint
        if let previous = aimPoint, phase != .noHand {
            let weight = min(max(configuration.smoothing, 0), 1)
            aim = CGPoint(x: previous.x + (raw.x - previous.x) * weight, y: previous.y + (raw.y - previous.y) * weight)
        } else {
            aim = raw
        }
        aimPoint = aim

        if ratio < configuration.closeRatio {
            closedStreak += 1
            openStreak = 0
        } else if ratio > configuration.openRatio {
            openStreak += 1
            closedStreak = 0
        } else {
            closedStreak = 0
            openStreak = 0
        }

        switch phase {
        case .noHand:
            // First sight of the hand: never grab on entry.
            let midpoint = (configuration.closeRatio + configuration.openRatio) / 2
            phase = ratio < midpoint ? .pinched : .open
            isArmed = phase == .open
            return []
        case .open:
            guard closedStreak >= configuration.framesToConfirm else { return [] }
            phase = .pinched
            guard isArmed else { return [] }
            isArmed = false
            isPinchActive = true
            return [.began(aim)]
        case .pinched:
            if openStreak >= configuration.framesToConfirm {
                phase = .open
                isArmed = true
                if isPinchActive {
                    isPinchActive = false
                    return [.ended(aim, .released)]
                }
                return []
            }
            return isPinchActive ? [.moved(aim)] : []
        }
    }

    /// Cancels an active pinch without an event (for example when world tracking is
    /// lost). Closed fingers must open again before the next grab.
    mutating func disarm() {
        isPinchActive = false
        if phase == .pinched {
            isArmed = false
        }
        closedStreak = 0
        openStreak = 0
    }

    mutating func reset() {
        phase = .noHand
        isArmed = false
        isPinchActive = false
        aimPoint = nil
        lastRatio = nil
        lastValidTime = nil
        closedStreak = 0
        openStreak = 0
    }

    private mutating func handleMissingHand(at time: TimeInterval) -> [JarvisPinchEvent] {
        closedStreak = 0
        openStreak = 0
        guard phase != .noHand else { return [] }
        let last = lastValidTime ?? time
        // A short gap freezes the gesture: no movement, no state change.
        guard time - last > configuration.lostTimeout else { return [] }
        let point = aimPoint
        let wasActive = isPinchActive
        reset()
        if wasActive, let point {
            return [.ended(point, .handLost)]
        }
        return []
    }
}

/// Guided calibration: the median ratio of an open hand and of a pinch set the two
/// thresholds between them.
enum JarvisPinchCalibration {
    static let minimumSamples = 6
    static let minimumSeparation: CGFloat = 0.20

    static func configuration(
        openRatios: [CGFloat],
        pinchRatios: [CGFloat],
        base: JarvisPinchConfiguration = JarvisPinchConfiguration()
    ) -> JarvisPinchConfiguration? {
        guard openRatios.count >= minimumSamples, pinchRatios.count >= minimumSamples else { return nil }
        let open = median(openRatios)
        let pinch = median(pinchRatios)
        guard open - pinch >= minimumSeparation else { return nil }
        var configuration = base
        configuration.closeRatio = pinch + (open - pinch) * 0.35
        configuration.openRatio = pinch + (open - pinch) * 0.60
        return configuration
    }

    static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Maps Vision landmarks to AR view points.
///
/// ARKit's `capturedImage` is in the sensor's landscape orientation. Vision runs on it
/// with orientation `.right`, so its normalized results (origin bottom-left) describe the
/// upright portrait image. They are converted back to normalized `capturedImage`
/// coordinates (origin top-left), then through `ARFrame.displayTransform`, which applies
/// the rotation and aspect-fill crop used to draw the camera feed. The back camera is
/// not mirrored.
enum JarvisHandCoordinateMapper {
    static func capturedImagePoint(fromVisionPoint point: CGPoint) -> CGPoint {
        CGPoint(x: 1 - point.y, y: 1 - point.x)
    }

    static func viewPoint(
        fromVisionPoint point: CGPoint,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> CGPoint {
        let normalized = capturedImagePoint(fromVisionPoint: point).applying(displayTransform)
        return CGPoint(x: normalized.x * viewportSize.width, y: normalized.y * viewportSize.height)
    }
}
