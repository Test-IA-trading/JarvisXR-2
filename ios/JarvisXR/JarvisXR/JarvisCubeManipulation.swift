import CoreGraphics
import Foundation
import simd

/// A camera ray in world space (ARKit metres).
struct JarvisRay: Equatable {
    var origin: SIMD3<Float>
    var direction: SIMD3<Float>
}

enum JarvisSpatialMath {
    /// Intersects a ray with the horizontal plane `y = planeY`. Returns nil when the ray
    /// is parallel to the plane, points away from it, or meets it farther than
    /// `maximumDistance` (a grazing ray would otherwise fling the object away).
    static func intersectHorizontalPlane(_ ray: JarvisRay, planeY: Float, maximumDistance: Float = 4) -> SIMD3<Float>? {
        let dy = ray.direction.y
        guard abs(dy) > 1e-4 else { return nil }
        let t = (planeY - ray.origin.y) / dy
        guard t > 0 else { return nil }
        let hit = ray.origin + ray.direction * t
        guard simd_distance(hit, ray.origin) <= maximumDistance else { return nil }
        return hit
    }

    /// Describes a horizontal move relative to the camera, in French. Nil under 2 cm.
    static func directionDescription(
        delta: SIMD3<Float>,
        cameraRight: SIMD3<Float>,
        cameraForward: SIMD3<Float>
    ) -> String? {
        let flat = SIMD3<Float>(delta.x, 0, delta.z)
        guard simd_length(flat) >= 0.02 else { return nil }
        func horizontal(_ v: SIMD3<Float>) -> SIMD3<Float> {
            let h = SIMD3<Float>(v.x, 0, v.z)
            let length = simd_length(h)
            return length > 1e-5 ? h / length : .zero
        }
        let right = simd_dot(flat, horizontal(cameraRight))
        let forward = simd_dot(flat, horizontal(cameraForward))
        if abs(right) >= abs(forward) {
            return right > 0 ? "vers la droite" : "vers la gauche"
        }
        return forward > 0 ? "en l'éloignant de vous" : "en le rapprochant de vous"
    }
}

/// Moves a cube resting on a horizontal plane from pinch (or touch) events.
///
/// - A grab only starts when the pinch begins over the cube as seen on screen; a pinch
///   in the void moves nothing.
/// - The offset between the projected pinch point and the cube is kept for the whole
///   grab, so the cube never jumps under the fingers.
/// - A frame without a usable ray, or an implausible jump, leaves the cube where it is.
struct JarvisCubeManipulator {
    enum Outcome: Equatable {
        case ignored
        case missed
        case grabbed
        case moved(SIMD3<Float>)
        case held
        case dropped(from: SIMD3<Float>, to: SIMD3<Float>, reason: JarvisPinchEndReason)
    }

    /// Half width, height and depth of the object (the cube: 3 cm on every axis).
    let halfExtents: SIMD3<Float>
    /// Height of the object centre above the table.
    var halfSize: Float { halfExtents.y }
    var planeY: Float
    /// Extra screen distance, in points, accepted around the cube's projected size.
    var targetMargin: CGFloat = 22
    /// Largest believable move between two analysed frames (35 cm).
    var maximumStep: Float = 0.35
    private(set) var center: SIMD3<Float>
    private(set) var isGrabbed = false
    private var grabOffset = SIMD2<Float>(0, 0)
    private var grabStart: SIMD3<Float>?

    init(center: SIMD3<Float>, halfSize: Float, planeY: Float) {
        self.init(center: center, halfExtents: SIMD3<Float>(repeating: halfSize), planeY: planeY)
    }

    init(center: SIMD3<Float>, halfExtents: SIMD3<Float>, planeY: Float) {
        self.center = center
        self.halfExtents = halfExtents
        self.planeY = planeY
    }

    /// Follows the rendered entity (ARKit may refine its world position) while free.
    mutating func syncCenter(_ newCenter: SIMD3<Float>) {
        guard !isGrabbed else { return }
        center = newCenter
    }

    func targetRadius(project: (SIMD3<Float>) -> CGPoint?) -> CGFloat? {
        guard let projectedCenter = project(center) else { return nil }
        let radial = max(halfExtents.x, halfExtents.z)
        let height = halfExtents.y
        var radius: CGFloat = 0
        let corners: [SIMD3<Float>] = [
            // The object may be turned around the vertical axis: use its widest side.
            SIMD3(radial, height, radial), SIMD3(-radial, height, -radial),
            SIMD3(radial, -height, -radial), SIMD3(-radial, -height, radial)
        ]
        for corner in corners {
            if let projected = project(center + corner) {
                radius = max(radius, hypot(projected.x - projectedCenter.x, projected.y - projectedCenter.y))
            }
        }
        return max(radius, 30) + targetMargin
    }

    func isTargeted(aim: CGPoint, project: (SIMD3<Float>) -> CGPoint?) -> Bool {
        guard let projectedCenter = project(center), let radius = targetRadius(project: project) else { return false }
        return hypot(aim.x - projectedCenter.x, aim.y - projectedCenter.y) <= radius
    }

    mutating func handle(
        _ event: JarvisPinchEvent,
        ray: (CGPoint) -> JarvisRay?,
        project: (SIMD3<Float>) -> CGPoint?
    ) -> Outcome {
        switch event {
        case .began(let point):
            guard !isGrabbed,
                  isTargeted(aim: point, project: project),
                  let pointRay = ray(point),
                  let hit = JarvisSpatialMath.intersectHorizontalPlane(pointRay, planeY: planeY) else {
                return .missed
            }
            isGrabbed = true
            grabOffset = SIMD2(center.x - hit.x, center.z - hit.z)
            grabStart = center
            return .grabbed
        case .moved(let point):
            guard isGrabbed else { return .ignored }
            guard let pointRay = ray(point),
                  let hit = JarvisSpatialMath.intersectHorizontalPlane(pointRay, planeY: planeY) else {
                return .held
            }
            let target = SIMD3<Float>(hit.x + grabOffset.x, planeY + halfSize, hit.z + grabOffset.y)
            guard simd_distance(target, center) <= maximumStep else { return .held }
            center = target
            return .moved(target)
        case .ended(_, let reason):
            return release(reason: reason)
        }
    }

    /// Ends a grab where the cube currently is (the final finger position is ignored:
    /// opening the fingers shifts their midpoint).
    mutating func release(reason: JarvisPinchEndReason) -> Outcome {
        guard isGrabbed else { return .ignored }
        isGrabbed = false
        let start = grabStart ?? center
        grabStart = nil
        return .dropped(from: start, to: center, reason: reason)
    }
}

/// What the user did to virtual objects during this app session, for questions such as
/// « Qu'est-ce que je viens de déplacer ? ». The scene engine knows which entity moved,
/// so the answer never relies on guessing from the camera image. Kept in memory only.
final class JarvisSpatialSceneMemory {
    static let shared = JarvisSpatialSceneMemory()

    struct Manipulation: Equatable {
        /// Spoken name with its article, for example "Le cube".
        let spokenName: String
        let distance: Float
        let direction: String?
        /// "pince" or "toucher".
        let method: String
        let date: Date
    }

    private(set) var lastManipulation: Manipulation?
    private(set) var manipulationCount = 0

    func record(_ manipulation: Manipulation) {
        lastManipulation = manipulation
        manipulationCount += 1
    }

    func reset() {
        lastManipulation = nil
        manipulationCount = 0
    }

    func answerWhatWasMoved(now: Date = Date()) -> (spoken: String, display: String) {
        guard let last = lastManipulation else {
            let text = "Vous n'avez encore rien déplacé pendant cette session."
            return (text, text)
        }
        let centimetres = Int((last.distance * 100).rounded())
        var detail = "Déplacé d'environ \(centimetres) cm"
        if let direction = last.direction {
            detail += " \(direction)"
        }
        detail += last.method == "toucher" ? " au toucher" : " avec la pince"
        detail += ", \(Self.elapsedDescription(from: last.date, to: now))."
        return ("\(last.spokenName).", "\(last.spokenName). \(detail)")
    }

    static func elapsedDescription(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        switch seconds {
        case ..<10: return "à l'instant"
        case ..<60: return "il y a \(seconds) secondes"
        case ..<120: return "il y a une minute"
        default: return "il y a \(seconds / 60) minutes"
        }
    }
}
