import CoreGraphics
import simd
import XCTest
@testable import JarvisXR

/// Lot 2 — pinch gesture, cube manipulation and scene memory, without camera or ARKit.
final class JarvisPinchCubeTests: XCTestCase {
    // MARK: Helpers

    /// A hand whose fingertips are `ratio × 100` points apart, centred on `at`.
    private func hand(ratio: CGFloat, at center: CGPoint = CGPoint(x: 200, y: 400), confidence: Float = 0.9) -> JarvisHandSample {
        let half = ratio * 100 / 2
        return JarvisHandSample(
            thumbTip: CGPoint(x: center.x - half, y: center.y),
            indexTip: CGPoint(x: center.x + half, y: center.y),
            thumbConfidence: confidence,
            indexConfidence: confidence,
            handSize: 100
        )
    }

    private struct Feed {
        var detector = JarvisPinchDetector()
        var time: TimeInterval = 0
        var events: [JarvisPinchEvent] = []

        mutating func send(_ sample: JarvisHandSample?, count: Int = 1, step: TimeInterval = 1.0 / 30.0) {
            for _ in 0..<count {
                time += step
                events += detector.update(with: sample, at: time)
            }
        }
    }

    private func began(_ events: [JarvisPinchEvent]) -> Int {
        events.filter { if case .began = $0 { return true } else { return false } }.count
    }

    private func ended(_ events: [JarvisPinchEvent], _ reason: JarvisPinchEndReason) -> Int {
        events.filter { if case .ended(_, let r) = $0 { return r == reason } else { return false } }.count
    }

    // MARK: Pinch detector

    func testOpenThenPinchThenOpenProducesOneGrabAndOneRelease() {
        var feed = Feed()
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.12), count: 4)
        feed.send(hand(ratio: 0.9), count: 3)
        XCTAssertEqual(began(feed.events), 1)
        XCTAssertEqual(ended(feed.events, .released), 1)
        XCTAssertEqual(feed.detector.phase, .open)
    }

    func testHandEnteringAlreadyPinchedCannotGrabUntilItOpens() {
        var feed = Feed()
        feed.send(hand(ratio: 0.1), count: 6)
        XCTAssertEqual(began(feed.events), 0, "A hand that enters closed must not grab.")
        XCTAssertTrue(feed.detector.needsReopen)
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.1), count: 3)
        XCTAssertEqual(began(feed.events), 1)
    }

    func testTremorBetweenThresholdsNeitherDropsNorGrabsTwice() {
        var feed = Feed()
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.15), count: 3)
        for ratio: CGFloat in [0.22, 0.38, 0.27, 0.44, 0.19, 0.41, 0.25, 0.36] {
            feed.send(hand(ratio: ratio))
        }
        XCTAssertEqual(began(feed.events), 1)
        XCTAssertEqual(ended(feed.events, .released), 0, "Values between the two thresholds keep the grab.")
        XCTAssertTrue(feed.detector.isPinchActive)
    }

    func testSingleNoisyOpenFrameDoesNotRelease() {
        var feed = Feed()
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.1), count: 3)
        feed.send(hand(ratio: 0.8), count: 1)
        feed.send(hand(ratio: 0.1), count: 3)
        XCTAssertEqual(ended(feed.events, .released), 0)
        XCTAssertEqual(began(feed.events), 1)
    }

    func testBriefDetectionGapFreezesWithoutEndingTheGrab() {
        var feed = Feed()
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.1), count: 3)
        let movesBefore = feed.events.filter { if case .moved = $0 { return true } else { return false } }.count
        feed.send(nil, count: 5) // about 170 ms
        let movesDuringGap = feed.events.filter { if case .moved = $0 { return true } else { return false } }.count - movesBefore
        XCTAssertEqual(movesDuringGap, 0, "No movement while the hand is not measured.")
        XCTAssertTrue(feed.detector.isPinchActive)
        feed.send(hand(ratio: 0.1), count: 2)
        XCTAssertEqual(ended(feed.events, .handLost), 0)
    }

    func testLostHandEndsTheGrabAndRequiresReopening() {
        var feed = Feed()
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.1), count: 3)
        feed.send(nil, count: 15) // half a second
        XCTAssertEqual(ended(feed.events, .handLost), 1)
        XCTAssertEqual(feed.detector.phase, .noHand)
        feed.send(hand(ratio: 0.1), count: 4)
        XCTAssertEqual(began(feed.events), 1, "Coming back pinched does not grab again.")
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.1), count: 3)
        XCTAssertEqual(began(feed.events), 2)
    }

    func testLowConfidenceFramesAreTreatedAsMissing() {
        var feed = Feed()
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.1, confidence: 0.1), count: 6)
        XCTAssertEqual(began(feed.events), 0, "Unreliable landmarks must not trigger a grab.")
    }

    func testDisarmCancelsAndRequiresOpenFingers() {
        var feed = Feed()
        feed.send(hand(ratio: 0.9), count: 3)
        feed.send(hand(ratio: 0.1), count: 3)
        feed.detector.disarm()
        XCTAssertFalse(feed.detector.isPinchActive)
        XCTAssertTrue(feed.detector.needsReopen)
        feed.send(hand(ratio: 0.1), count: 3)
        XCTAssertEqual(began(feed.events), 1)
    }

    func testPinchRatioDoesNotDependOnHandDistance() {
        let near = JarvisHandSample(thumbTip: .zero, indexTip: CGPoint(x: 40, y: 0), thumbConfidence: 1, indexConfidence: 1, handSize: 200)
        let far = JarvisHandSample(thumbTip: .zero, indexTip: CGPoint(x: 10, y: 0), thumbConfidence: 1, indexConfidence: 1, handSize: 50)
        XCTAssertEqual(near.pinchRatio, far.pinchRatio, accuracy: 0.0001)
    }

    // MARK: Calibration

    func testCalibrationPlacesThresholdsBetweenOpenAndPinch() throws {
        let configuration = try XCTUnwrap(JarvisPinchCalibration.configuration(
            openRatios: [0.82, 0.9, 0.86, 0.95, 0.88, 0.91],
            pinchRatios: [0.08, 0.12, 0.1, 0.09, 0.11, 0.14]
        ))
        XCTAssertGreaterThan(configuration.closeRatio, 0.12)
        XCTAssertLessThan(configuration.openRatio, 0.86)
        XCTAssertLessThan(configuration.closeRatio, configuration.openRatio)
    }

    func testCalibrationRejectsIndistinctPositions() {
        XCTAssertNil(JarvisPinchCalibration.configuration(
            openRatios: [0.3, 0.32, 0.31, 0.29, 0.3, 0.33],
            pinchRatios: [0.25, 0.27, 0.26, 0.24, 0.25, 0.28]
        ))
    }

    func testCalibrationPersists() {
        let defaults = UserDefaults(suiteName: "JarvisPinchCubeTests.\(UUID().uuidString)")!
        var configuration = JarvisPinchConfiguration()
        configuration.closeRatio = 0.21
        configuration.openRatio = 0.47
        configuration.save(to: defaults)
        let loaded = JarvisPinchConfiguration.load(from: defaults)
        XCTAssertEqual(loaded.closeRatio, 0.21, accuracy: 0.0001)
        XCTAssertEqual(loaded.openRatio, 0.47, accuracy: 0.0001)
    }

    // MARK: Coordinates

    func testVisionPointsMapToTheUprightPortraitView() {
        // displayTransform of a portrait view with no crop: rotation of the landscape image.
        let portrait = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1, ty: 0)
        let size = CGSize(width: 390, height: 844)
        let point = JarvisHandCoordinateMapper.viewPoint(fromVisionPoint: CGPoint(x: 0.25, y: 0.8), displayTransform: portrait, viewportSize: size)
        XCTAssertEqual(point.x, 0.25 * 390, accuracy: 0.001)
        XCTAssertEqual(point.y, 0.2 * 844, accuracy: 0.001, "Vision's origin is bottom-left; the view's is top-left.")
        let corner = JarvisHandCoordinateMapper.viewPoint(fromVisionPoint: CGPoint(x: 0, y: 1), displayTransform: portrait, viewportSize: size)
        XCTAssertEqual(corner.x, 0, accuracy: 0.001)
        XCTAssertEqual(corner.y, 0, accuracy: 0.001)
    }

    // MARK: Spatial math

    func testRayHitsTheTablePlane() throws {
        let ray = JarvisRay(origin: SIMD3<Float>(0, 1, 0), direction: simd_normalize(SIMD3<Float>(0, -1, -1)))
        let hit = try XCTUnwrap(JarvisSpatialMath.intersectHorizontalPlane(ray, planeY: 0))
        XCTAssertEqual(hit.y, 0, accuracy: 0.0001)
        XCTAssertEqual(hit.z, -1, accuracy: 0.0001)
    }

    func testGrazingOrUpwardRaysAreRejected() {
        let flat = JarvisRay(origin: SIMD3<Float>(0, 1, 0), direction: SIMD3<Float>(0, 0, -1))
        XCTAssertNil(JarvisSpatialMath.intersectHorizontalPlane(flat, planeY: 0))
        let upward = JarvisRay(origin: SIMD3<Float>(0, 1, 0), direction: SIMD3<Float>(0, 1, 0))
        XCTAssertNil(JarvisSpatialMath.intersectHorizontalPlane(upward, planeY: 0))
        let grazing = JarvisRay(origin: SIMD3<Float>(0, 1, 0), direction: simd_normalize(SIMD3<Float>(0, -0.01, -1)))
        XCTAssertNil(JarvisSpatialMath.intersectHorizontalPlane(grazing, planeY: 0), "A far hit near the horizon would fling the cube.")
    }

    func testMoveDirectionIsDescribedRelativeToTheCamera() {
        let right = SIMD3<Float>(1, 0, 0)
        let forward = SIMD3<Float>(0, 0, -1)
        XCTAssertEqual(JarvisSpatialMath.directionDescription(delta: SIMD3(0.2, 0, 0.02), cameraRight: right, cameraForward: forward), "vers la droite")
        XCTAssertEqual(JarvisSpatialMath.directionDescription(delta: SIMD3(-0.2, 0, 0), cameraRight: right, cameraForward: forward), "vers la gauche")
        XCTAssertEqual(JarvisSpatialMath.directionDescription(delta: SIMD3(0, 0, -0.3), cameraRight: right, cameraForward: forward), "en l'éloignant de vous")
        XCTAssertNil(JarvisSpatialMath.directionDescription(delta: SIMD3(0.005, 0, 0), cameraRight: right, cameraForward: forward))
    }

    // MARK: Cube manipulator

    /// Camera at (0, 0.5, 0.5) looking down at the table (y = 0); screen = x/z plane scaled.
    private let scale: Float = 1000
    private func project(_ p: SIMD3<Float>) -> CGPoint? {
        CGPoint(x: CGFloat(200 + p.x * scale), y: CGFloat(400 + p.z * scale))
    }
    private func ray(_ point: CGPoint) -> JarvisRay? {
        let x = (Float(point.x) - 200) / scale
        let z = (Float(point.y) - 400) / scale
        return JarvisRay(origin: SIMD3<Float>(x, 0.5, z), direction: SIMD3<Float>(0, -1, 0))
    }

    private func makeCube() -> JarvisCubeManipulator {
        JarvisCubeManipulator(center: SIMD3<Float>(0, 0.03, 0), halfSize: 0.03, planeY: 0)
    }

    func testPinchInTheVoidDoesNotMoveTheCube() {
        var cube = makeCube()
        let far = CGPoint(x: 200 + 300, y: 400) // 30 cm to the right of the cube on screen
        XCTAssertEqual(cube.handle(.began(far), ray: ray, project: project), .missed)
        XCTAssertEqual(cube.handle(.moved(CGPoint(x: 520, y: 400)), ray: ray, project: project), .ignored)
        XCTAssertEqual(cube.center, SIMD3<Float>(0, 0.03, 0))
        XCTAssertFalse(cube.isGrabbed)
    }

    func testGrabKeepsItsOffsetSoTheCubeDoesNotJump() {
        var cube = makeCube()
        let start = CGPoint(x: 215, y: 405) // pinch slightly off-centre, still on the cube
        XCTAssertEqual(cube.handle(.began(start), ray: ray, project: project), .grabbed)
        guard case .moved(let same) = cube.handle(.moved(start), ray: ray, project: project) else {
            return XCTFail("Expected a move")
        }
        XCTAssertEqual(same.x, 0, accuracy: 0.0001, "Same finger position, same cube position: no jump.")
        XCTAssertEqual(same.z, 0, accuracy: 0.0001)
        guard case .moved(let moved) = cube.handle(.moved(CGPoint(x: 215 + 100, y: 405)), ray: ray, project: project) else {
            return XCTFail("Expected a move")
        }
        XCTAssertEqual(moved.x, 0.1, accuracy: 0.0001, "10 cm hand move on the table, 10 cm cube move.")
        XCTAssertEqual(moved.y, 0.03, accuracy: 0.0001, "The cube stays on the table.")
    }

    func testReleaseLeavesTheCubeWhereItWasCarried() {
        var cube = makeCube()
        _ = cube.handle(.began(CGPoint(x: 200, y: 400)), ray: ray, project: project)
        _ = cube.handle(.moved(CGPoint(x: 260, y: 400)), ray: ray, project: project)
        let outcome = cube.handle(.ended(CGPoint(x: 400, y: 400), .released), ray: ray, project: project)
        guard case .dropped(let from, let to, let reason) = outcome else { return XCTFail("Expected a drop") }
        XCTAssertEqual(reason, .released)
        XCTAssertEqual(from.x, 0, accuracy: 0.0001)
        XCTAssertEqual(to.x, 0.06, accuracy: 0.0001, "The opening fingers' final point is ignored.")
        XCTAssertEqual(cube.center.x, 0.06, accuracy: 0.0001)
        XCTAssertFalse(cube.isGrabbed)
    }

    func testFrameWithoutUsableRayOrWithImplausibleJumpFreezesTheCube() {
        var cube = makeCube()
        _ = cube.handle(.began(CGPoint(x: 200, y: 400)), ray: ray, project: project)
        XCTAssertEqual(cube.handle(.moved(CGPoint(x: 250, y: 400)), ray: { _ in nil }, project: project), .held)
        XCTAssertEqual(cube.handle(.moved(CGPoint(x: 200 + 900, y: 400)), ray: ray, project: project), .held)
        XCTAssertEqual(cube.center, SIMD3<Float>(0, 0.03, 0))
        XCTAssertTrue(cube.isGrabbed)
    }

    func testCubeCanBeGrabbedAgainAfterBeingMoved() {
        var cube = makeCube()
        _ = cube.handle(.began(CGPoint(x: 200, y: 400)), ray: ray, project: project)
        _ = cube.handle(.moved(CGPoint(x: 300, y: 400)), ray: ray, project: project)
        _ = cube.handle(.ended(CGPoint(x: 300, y: 400), .released), ray: ray, project: project)
        XCTAssertEqual(cube.handle(.began(CGPoint(x: 200, y: 400)), ray: ray, project: project), .missed, "The old place is empty now.")
        XCTAssertEqual(cube.handle(.began(CGPoint(x: 300, y: 400)), ray: ray, project: project), .grabbed)
    }

    // MARK: Scene memory and voice

    func testJarvisNamesTheObjectThatWasMoved() {
        let scene = JarvisSpatialSceneMemory()
        let defaults = UserDefaults(suiteName: "JarvisPinchCubeTests.\(UUID().uuidString)")!
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: defaults), scene: scene)

        guard case .answer(let nothing) = router.route("Qu'est-ce que je viens de déplacer ?") else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertTrue(nothing.spokenResponse.contains("rien déplacé"))

        let now = Date()
        scene.record(.init(spokenName: "Le cube", distance: 0.24, direction: "vers la droite", method: "pince", date: now.addingTimeInterval(-3)))
        guard case .answer(let answer) = router.route("Jarvis, qu’est-ce que je viens de déplacer ?") else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertEqual(answer.spokenResponse, "Le cube.")
        XCTAssertTrue(answer.displayResponse.contains("24 cm vers la droite"))
        XCTAssertTrue(answer.displayResponse.contains("avec la pince"))
    }

    func testFrenchCommandOpensTheARCube() {
        let defaults = UserDefaults(suiteName: "JarvisPinchCubeTests.\(UUID().uuidString)")!
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: defaults), scene: JarvisSpatialSceneMemory())
        for phrase in ["Ouvre le cube", "Lance la réalité augmentée", "mode cube"] {
            guard case .answer(let response) = router.route(phrase) else {
                return XCTFail("Expected a native answer for \(phrase)")
            }
            XCTAssertEqual(response.data["action"], "ar_cube", phrase)
        }
        guard case .answer(let note) = router.route("Prends une note acheter un cube de bois") else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertNil(note.data["action"], "A note mentioning a cube must stay a note.")
    }
}
