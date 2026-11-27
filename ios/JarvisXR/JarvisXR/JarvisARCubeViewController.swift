import ARKit
import RealityKit
import UIKit
import Vision

/// Runs Vision hand-pose detection on ARKit frames. Not tied to the main actor: it is
/// called on a private serial queue, one frame at a time.
final class JarvisHandPoseTracker {
    private let request: VNDetectHumanHandPoseRequest

    init() {
        request = VNDetectHumanHandPoseRequest()
        // The hand holding the phone can appear at the edge; keep both and choose.
        request.maximumHandCount = 2
    }

    func detect(
        in pixelBuffer: CVPixelBuffer,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize,
        preferNear previousAim: CGPoint?
    ) -> JarvisHandSample? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observations = request.results, !observations.isEmpty else { return nil }
        let samples = observations.compactMap { sample(from: $0, displayTransform: displayTransform, viewportSize: viewportSize) }
        guard !samples.isEmpty else { return nil }
        if let previousAim, samples.count > 1 {
            // Keep following the hand already in use instead of jumping to the other one.
            return samples.min { lhs, rhs in
                Self.distance(lhs.pinchMidpoint, previousAim) < Self.distance(rhs.pinchMidpoint, previousAim)
            }
        }
        return samples.max { $0.minimumConfidence < $1.minimumConfidence }
    }

    private func sample(
        from observation: VNHumanHandPoseObservation,
        displayTransform: CGAffineTransform,
        viewportSize: CGSize
    ) -> JarvisHandSample? {
        guard let thumb = try? observation.recognizedPoint(.thumbTip),
              let index = try? observation.recognizedPoint(.indexTip) else { return nil }
        func map(_ point: VNRecognizedPoint) -> CGPoint {
            JarvisHandCoordinateMapper.viewPoint(fromVisionPoint: point.location, displayTransform: displayTransform, viewportSize: viewportSize)
        }
        var handSize: CGFloat = 0
        if let wrist = try? observation.recognizedPoint(.wrist),
           let middle = try? observation.recognizedPoint(.middleMCP),
           wrist.confidence > 0.3, middle.confidence > 0.3 {
            handSize = Self.distance(map(wrist), map(middle))
        } else if let indexKnuckle = try? observation.recognizedPoint(.indexMCP),
                  let littleKnuckle = try? observation.recognizedPoint(.littleMCP),
                  indexKnuckle.confidence > 0.3, littleKnuckle.confidence > 0.3 {
            handSize = Self.distance(map(indexKnuckle), map(littleKnuckle)) * 1.35
        }
        guard handSize > 0 else { return nil }
        return JarvisHandSample(
            thumbTip: map(thumb),
            indexTip: map(index),
            thumbConfidence: thumb.confidence,
            indexConfidence: index.confidence,
            handSize: handSize
        )
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

/// Forwards ARSession callbacks (delivered on the main queue) to closures, so the view
/// controller does not have to satisfy the delegate protocol itself.
final class JarvisARSessionRelay: NSObject, ARSessionDelegate {
    var onFrame: ((ARFrame) -> Void)?
    var onTrackingChange: ((ARCamera.TrackingState) -> Void)?
    var onFailure: ((Error) -> Void)?
    var onInterruption: ((Bool) -> Void)?

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        onFrame?(frame)
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        onTrackingChange?(camera.trackingState)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        onFailure?(error)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        onInterruption?(true)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        onInterruption?(false)
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        true
    }
}

private final class JarvisInsetLabel: UILabel {
    var insets = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}

/// Lot 2 — a virtual cube resting on a real table, grabbed in the air with a
/// thumb–index pinch, carried, and released where it stays.
///
/// Camera ownership: the ARSession is the only camera client while this screen is open;
/// hand landmarks come from Vision run on `ARFrame.capturedImage`, never from a second
/// capture session. Placement and persistence come from ARKit world tracking; the pinch
/// only provides a screen point, projected onto the detected table plane.
final class JarvisARCubeViewController: UIViewController {
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private enum Feedback: Equatable {
        case searching
        case ready
        case targeted
        case grabbed
        case dropped
        case missed
        case reopenToGrab
        case handLost
        case trackingLimited(String)
        case interrupted
        case failed(String)

        var text: String {
            switch self {
            case .searching: return "Cadrez une table et bougez doucement le téléphone."
            case .ready: return "Approchez le pouce et l'index du cube, puis pincez dans l'air."
            case .targeted: return "Visé — pincez pour saisir."
            case .grabbed: return "Saisi — déplacez la main, ouvrez les doigts pour lâcher."
            case .dropped: return "Déposé."
            case .missed: return "Pince à côté du cube : rien n'est saisi."
            case .reopenToGrab: return "Ouvrez les doigts, puis pincez le cube."
            case .handLost: return "Main perdue : le cube reste en place. Rouvrez les doigts pour le reprendre."
            case .trackingLimited(let reason): return "Suivi limité (\(reason)) : le cube est figé."
            case .interrupted: return "Réalité augmentée interrompue."
            case .failed(let message): return message
            }
        }
    }

    private enum GrabSource: String {
        case pinch = "pince"
        case touch = "toucher"
    }

    private struct Metrics {
        var windowStart: CFTimeInterval = 0
        var framesInWindow = 0
        var handsInWindow = 0
        var handRate: Double = 0
        var handVisibleShare: Double = 0
        var lastLatencyMilliseconds: Double?
        var grabs = 0
        var drops = 0
        var misses = 0
        var losses = 0

        mutating func registerHandFrame(at time: CFTimeInterval, detected: Bool) {
            if windowStart == 0 { windowStart = time }
            framesInWindow += 1
            if detected { handsInWindow += 1 }
            let elapsed = time - windowStart
            if elapsed >= 1 {
                handRate = Double(framesInWindow) / elapsed
                handVisibleShare = Double(handsInWindow) / Double(max(framesInWindow, 1))
                framesInWindow = 0
                handsInWindow = 0
                windowStart = time
            }
        }
    }

    private struct CalibrationRun {
        enum Step { case open, pinch }
        var step: Step = .open
        var collectFrom: CFTimeInterval
        var openRatios: [CGFloat] = []
        var pinchRatios: [CGFloat] = []
    }

    private static let cubeHalfSize: Float = 0.03
    private static let calibrationPrepareDelay: CFTimeInterval = 1.2
    private static let calibrationCollectDuration: CFTimeInterval = 1.6

    private var arView: ARView!
    private let relay = JarvisARSessionRelay()
    private let coachingOverlay = ARCoachingOverlayView()
    private let fingertipOverlay = UIView()
    private let thumbLayer = CAShapeLayer()
    private let indexLayer = CAShapeLayer()
    private let aimLayer = CAShapeLayer()
    private let statusLabel = JarvisInsetLabel()
    private let answerLabel = JarvisInsetLabel()
    private let metricsLabel = JarvisInsetLabel()
    private let closeButton = UIButton(type: .system)
    private let calibrateButton = UIButton(type: .system)
    private let metricsButton = UIButton(type: .system)
    private let talkButton = UIButton(type: .system)
    private let replaceButton = UIButton(type: .system)

    private let handTracker = JarvisHandPoseTracker()
    private let handQueue = DispatchQueue(label: "jarvis.cube.hand", qos: .userInteractive)
    private var handRequestInFlight = false
    private var lastHandRequestTime: TimeInterval = 0
    private var detector = JarvisPinchDetector(configuration: .load())
    private var manipulator: JarvisCubeManipulator?
    private var cubeEntity: ModelEntity?
    private var cubeAnchor: AnchorEntity?
    private var activeGrabSource: GrabSource?
    private var wasTargeted = false
    private var trackingIsNormal = false
    private var trackingDescription = "initialisation"
    private var searchingSince: CFTimeInterval = CACurrentMediaTime()
    private var lastPlacementAttempt: TimeInterval = 0
    private var feedback: Feedback = .searching
    private var transientFeedbackUntil: CFTimeInterval = 0
    private var metrics = Metrics()
    private var showsMetrics = false
    private var calibration: CalibrationRun?
    private var didStartSession = false

    private let selectionHaptic = UISelectionFeedbackGenerator()
    private let grabHaptic = UIImpactFeedbackGenerator(style: .medium)
    private let dropHaptic = UINotificationFeedbackGenerator()

    private let voiceInput = JarvisVoiceInputService.shared
    private let speech = JarvisSpeechService.shared
    private let assistant = JarvisAssistantCore()

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = "Cube AR"
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.session.delegate = relay
        buildInterface()
        wireSession()
        render(feedback: .searching)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        wireVoice()
        UIApplication.shared.isIdleTimerDisabled = true
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        freezeGrab()
        voiceInput.cancel()
        arView.session.pause()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        fingertipOverlay.frame = arView.frame
    }

    // MARK: - Interface

    private func buildInterface() {
        arView.translatesAutoresizingMaskIntoConstraints = false
        arView.accessibilityLabel = "Vue caméra avec le cube virtuel"
        view.addSubview(arView)

        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(coachingOverlay)

        fingertipOverlay.isUserInteractionEnabled = false
        fingertipOverlay.backgroundColor = .clear
        view.addSubview(fingertipOverlay)
        configureDot(thumbLayer, radius: 7, color: UIColor.systemTeal)
        configureDot(indexLayer, radius: 7, color: UIColor.systemTeal)
        aimLayer.path = UIBezierPath(ovalIn: CGRect(x: -16, y: -16, width: 32, height: 32)).cgPath
        aimLayer.fillColor = UIColor.clear.cgColor
        aimLayer.strokeColor = UIColor.white.withAlphaComponent(0.85).cgColor
        aimLayer.lineWidth = 2
        aimLayer.isHidden = true
        fingertipOverlay.layer.addSublayer(aimLayer)

        styleLabel(statusLabel, font: .preferredFont(forTextStyle: .headline))
        statusLabel.accessibilityIdentifier = "jarvis.cube.status"
        statusLabel.accessibilityTraits.insert(.updatesFrequently)
        styleLabel(answerLabel, font: .preferredFont(forTextStyle: .body))
        answerLabel.accessibilityIdentifier = "jarvis.cube.answer"
        answerLabel.isHidden = true
        styleLabel(metricsLabel, font: .monospacedSystemFont(ofSize: 11, weight: .regular))
        metricsLabel.textAlignment = .left
        metricsLabel.accessibilityIdentifier = "jarvis.cube.metrics"
        metricsLabel.isHidden = true

        styleButton(closeButton, title: "Fermer", accessibility: "Fermer le cube AR", action: #selector(closeTapped))
        styleButton(calibrateButton, title: "Calibrer", accessibility: "Calibrer la pince main ouverte puis pincée", action: #selector(calibrateTapped))
        styleButton(metricsButton, title: "Mesures", accessibility: "Afficher les mesures de suivi", action: #selector(metricsTapped))
        styleButton(talkButton, title: "Parler", accessibility: "Parler à JARVIS", action: #selector(talkTapped))
        styleButton(replaceButton, title: "Replacer", accessibility: "Replacer le cube au centre de la table", action: #selector(replaceTapped))
        talkButton.backgroundColor = JarvisTheme.accentHot
        talkButton.setTitleColor(JarvisTheme.background, for: .normal)

        let topRow = UIStackView(arrangedSubviews: [closeButton, UIView(), calibrateButton, metricsButton])
        topRow.axis = .horizontal
        topRow.spacing = 8
        let bottomRow = UIStackView(arrangedSubviews: [replaceButton, talkButton])
        bottomRow.axis = .horizontal
        bottomRow.spacing = 12
        bottomRow.distribution = .fillEqually

        [topRow, statusLabel, metricsLabel, answerLabel, bottomRow].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            coachingOverlay.topAnchor.constraint(equalTo: view.topAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            topRow.topAnchor.constraint(equalTo: guide.topAnchor, constant: 8),
            topRow.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 10),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -12),

            metricsLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            metricsLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 12),
            metricsLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -12),

            answerLabel.bottomAnchor.constraint(equalTo: bottomRow.topAnchor, constant: -10),
            answerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            answerLabel.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 12),
            answerLabel.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -12),

            bottomRow.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            bottomRow.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            bottomRow.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -12),
            bottomRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
        ])

        // Accessible fallback: drag the cube with one finger on the screen.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        arView.addGestureRecognizer(pan)

        view.accessibilityElements = [closeButton, calibrateButton, metricsButton, statusLabel, metricsLabel, arView!, answerLabel, replaceButton, talkButton]
    }

    private func configureDot(_ layer: CAShapeLayer, radius: CGFloat, color: UIColor) {
        layer.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
        layer.fillColor = color.withAlphaComponent(0.85).cgColor
        layer.strokeColor = UIColor.white.cgColor
        layer.lineWidth = 1.5
        layer.isHidden = true
        fingertipOverlay.layer.addSublayer(layer)
    }

    private func styleLabel(_ label: JarvisInsetLabel, font: UIFont) {
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.numberOfLines = 0
        label.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        label.layer.cornerRadius = 12
        label.clipsToBounds = true
    }

    private func styleButton(_ button: UIButton, title: String, accessibility: String, action: Selector) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        button.layer.cornerRadius = 12
        button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        button.accessibilityLabel = accessibility
        button.addTarget(self, action: action, for: .touchUpInside)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    // MARK: - Session

    private func wireSession() {
        relay.onFrame = { [weak self] frame in
            self?.handle(frame: frame)
        }
        relay.onTrackingChange = { [weak self] state in
            self?.handleTracking(state)
        }
        relay.onFailure = { [weak self] error in
            self?.handleFailure(error)
        }
        relay.onInterruption = { [weak self] began in
            guard let self else { return }
            if began {
                self.freezeGrab()
                self.render(feedback: .interrupted)
            } else {
                self.render(feedback: self.cubeEntity == nil ? .searching : .ready)
            }
        }
    }

    private func startSession() {
        guard Self.isSupported else {
            render(feedback: .failed("La réalité augmentée n'est pas disponible sur cet appareil."))
            return
        }
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        configuration.environmentTexturing = .automatic
        if didStartSession {
            arView.session.run(configuration)
        } else {
            didStartSession = true
            searchingSince = CACurrentMediaTime()
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    private func handle(frame: ARFrame) {
        if cubeEntity == nil, trackingIsNormal, frame.timestamp - lastPlacementAttempt > 0.3 {
            lastPlacementAttempt = frame.timestamp
            placeCubeIfPossible()
        }
        scheduleHandDetection(on: frame)
        if transientFeedbackUntil > 0, CACurrentMediaTime() > transientFeedbackUntil {
            transientFeedbackUntil = 0
            refreshRestingFeedback()
        }
    }

    private func handleTracking(_ state: ARCamera.TrackingState) {
        switch state {
        case .normal:
            trackingIsNormal = true
            trackingDescription = "normal"
        case .notAvailable:
            trackingIsNormal = false
            trackingDescription = "indisponible"
        case .limited(let reason):
            trackingIsNormal = false
            switch reason {
            case .initializing: trackingDescription = "initialisation"
            case .excessiveMotion: trackingDescription = "mouvement trop rapide"
            case .insufficientFeatures: trackingDescription = "surface trop uniforme ou trop sombre"
            case .relocalizing: trackingDescription = "relocalisation"
            @unknown default: trackingDescription = "limité"
            }
        }
        if trackingIsNormal {
            refreshRestingFeedback()
        } else {
            freezeGrab()
            if cubeEntity != nil {
                render(feedback: .trackingLimited(trackingDescription))
            }
        }
        renderMetrics()
    }

    private func handleFailure(_ error: Error) {
        freezeGrab()
        if let arError = error as? ARError, arError.code == .cameraUnauthorized {
            render(feedback: .failed("Accès à la caméra refusé. Activez-le dans Réglages > JarvisXR > Caméra."))
        } else {
            render(feedback: .failed("La réalité augmentée s'est arrêtée. Fermez puis rouvrez le cube."))
        }
    }

    // MARK: - Cube

    private func placeCubeIfPossible() {
        let target = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY + arView.bounds.height * 0.08)
        var result = arView.raycast(from: target, allowing: .existingPlaneGeometry, alignment: .horizontal).first
        if result == nil, CACurrentMediaTime() - searchingSince > 4 {
            result = arView.raycast(from: target, allowing: .estimatedPlane, alignment: .horizontal).first
        }
        guard let result else { return }
        let position = result.worldTransform.columns.3
        placeCube(atBase: SIMD3<Float>(position.x, position.y, position.z))
    }

    private func placeCube(atBase base: SIMD3<Float>) {
        let half = Self.cubeHalfSize
        let cube = ModelEntity(
            mesh: .generateBox(size: half * 2, cornerRadius: half * 0.18),
            materials: [cubeMaterial(targeted: false, grabbed: false)]
        )
        cube.name = "jarvis.cube"
        var shadowMaterial = UnlitMaterial(color: .black)
        shadowMaterial.blending = .transparent(opacity: 0.28)
        let shadow = ModelEntity(mesh: .generatePlane(width: half * 2.6, depth: half * 2.6, cornerRadius: half * 1.2), materials: [shadowMaterial])
        shadow.position = SIMD3<Float>(0, -half + 0.0015, 0)
        cube.addChild(shadow)

        cubeEntity = cube
        anchorCube(atBase: base)
        manipulator = JarvisCubeManipulator(center: SIMD3<Float>(base.x, base.y + half, base.z), halfSize: half, planeY: base.y)
        wasTargeted = false
        selectionHaptic.prepare()
        grabHaptic.prepare()
        render(feedback: .ready)
        postAnnouncement("Cube posé sur la table.")
    }

    /// Re-anchors the cube at its resting place on the table, in world coordinates.
    private func anchorCube(atBase base: SIMD3<Float>) {
        guard let cube = cubeEntity else { return }
        let anchor = AnchorEntity(world: base)
        arView.scene.addAnchor(anchor)
        cube.setParent(anchor, preservingWorldTransform: false)
        cube.position = SIMD3<Float>(0, Self.cubeHalfSize, 0)
        if let previous = cubeAnchor, previous !== anchor {
            arView.scene.removeAnchor(previous)
        }
        cubeAnchor = anchor
    }

    private func cubeMaterial(targeted: Bool, grabbed: Bool) -> SimpleMaterial {
        let color: UIColor
        if grabbed {
            color = UIColor.systemGreen
        } else if targeted {
            color = UIColor.systemYellow
        } else {
            color = UIColor.systemTeal
        }
        return SimpleMaterial(color: color, roughness: 0.35, isMetallic: false)
    }

    private func updateCubeAppearance() {
        guard let cube = cubeEntity else { return }
        let grabbed = manipulator?.isGrabbed == true
        cube.model?.materials = [cubeMaterial(targeted: wasTargeted, grabbed: grabbed)]
        cube.scale = SIMD3<Float>(repeating: grabbed ? 1.12 : (wasTargeted ? 1.05 : 1))
    }

    private func syncManipulatorWithEntity() {
        guard let cube = cubeEntity else { return }
        manipulator?.syncCenter(cube.position(relativeTo: nil))
    }

    private func ray(through point: CGPoint) -> JarvisRay? {
        guard let result = arView.ray(through: point) else { return nil }
        return JarvisRay(origin: result.origin, direction: result.direction)
    }

    private func project(_ point: SIMD3<Float>) -> CGPoint? {
        arView.project(point)
    }

    // MARK: - Hands

    private func scheduleHandDetection(on frame: ARFrame) {
        guard !handRequestInFlight, cubeEntity != nil || calibration != nil else { return }
        let hot = ProcessInfo.processInfo.thermalState == .serious || ProcessInfo.processInfo.thermalState == .critical
        let interval: TimeInterval = hot ? 1.0 / 12.0 : 1.0 / 30.0
        guard frame.timestamp - lastHandRequestTime >= interval else { return }
        lastHandRequestTime = frame.timestamp
        handRequestInFlight = true

        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp
        let viewportSize = arView.bounds.size
        let displayTransform = frame.displayTransform(for: .portrait, viewportSize: viewportSize)
        let previousAim = detector.aimPoint
        let tracker = handTracker
        handQueue.async { [weak self] in
            let sample = tracker.detect(in: pixelBuffer, displayTransform: displayTransform, viewportSize: viewportSize, preferNear: previousAim)
            DispatchQueue.main.async {
                self?.handleHandSample(sample, frameTimestamp: timestamp)
            }
        }
    }

    private func handleHandSample(_ sample: JarvisHandSample?, frameTimestamp: TimeInterval) {
        handRequestInFlight = false
        metrics.registerHandFrame(at: CACurrentMediaTime(), detected: sample != nil)
        renderFingertips(sample)
        defer { renderMetrics() }

        if calibration != nil {
            feedCalibration(sample)
            return
        }
        guard trackingIsNormal, manipulator != nil else { return }

        let events = detector.update(with: sample, at: frameTimestamp)
        for event in events {
            process(event, source: .pinch, frameTimestamp: frameTimestamp)
        }
        updateTargeting()
    }

    private func process(_ event: JarvisPinchEvent, source: GrabSource, frameTimestamp: TimeInterval) {
        if let activeGrabSource, activeGrabSource != source { return }
        syncManipulatorWithEntity()
        guard let outcome = manipulator?.handle(event, ray: { self.ray(through: $0) }, project: { self.project($0) }) else { return }
        switch outcome {
        case .ignored, .held:
            break
        case .missed:
            metrics.misses += 1
            render(feedback: .missed, transientFor: 1.4)
        case .grabbed:
            activeGrabSource = source
            metrics.grabs += 1
            grabHaptic.impactOccurred()
            updateCubeAppearance()
            render(feedback: .grabbed)
            postAnnouncement("Cube saisi.")
        case .moved(let center):
            cubeEntity?.setPosition(center, relativeTo: nil)
            metrics.lastLatencyMilliseconds = max(0, (CACurrentMediaTime() - frameTimestamp) * 1000)
        case .dropped:
            finishGrab(outcome, source: source)
        }
    }

    private func finishGrab(_ outcome: JarvisCubeManipulator.Outcome, source: GrabSource) {
        guard case let .dropped(from, to, reason) = outcome else { return }
        activeGrabSource = nil
        let base = SIMD3<Float>(to.x, to.y - Self.cubeHalfSize, to.z)
        anchorCube(atBase: base)
        updateCubeAppearance()

        let distance = simd_distance(SIMD3<Float>(from.x, 0, from.z), SIMD3<Float>(to.x, 0, to.z))
        if distance >= 0.01 {
            var direction: String?
            if let camera = arView.session.currentFrame?.camera.transform {
                let right = SIMD3<Float>(camera.columns.0.x, camera.columns.0.y, camera.columns.0.z)
                let forward = -SIMD3<Float>(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z)
                direction = JarvisSpatialMath.directionDescription(delta: to - from, cameraRight: right, cameraForward: forward)
            }
            JarvisSpatialSceneMemory.shared.record(.init(
                spokenName: "Le cube",
                distance: distance,
                direction: direction,
                method: source.rawValue,
                date: Date()
            ))
        }

        if reason == .handLost {
            metrics.losses += 1
            render(feedback: .handLost, transientFor: 2.5)
        } else {
            metrics.drops += 1
            dropHaptic.notificationOccurred(.success)
            render(feedback: .dropped, transientFor: 1.4)
            postAnnouncement("Cube déposé.")
        }
    }

    /// Stops a grab in place (tracking loss, interruption): the cube stays where it was,
    /// and closed fingers must open before the next grab.
    private func freezeGrab() {
        detector.disarm()
        guard let source = activeGrabSource, let outcome = manipulator?.release(reason: .handLost) else { return }
        finishGrab(outcome, source: source)
    }

    private func updateTargeting() {
        guard let manipulator else { return }
        let targeted: Bool
        if manipulator.isGrabbed {
            targeted = true
        } else if let aim = detector.aimPoint, detector.phase != .noHand {
            targeted = manipulator.isTargeted(aim: aim, project: { self.project($0) })
        } else {
            targeted = false
        }
        if targeted != wasTargeted {
            wasTargeted = targeted
            if targeted && !manipulator.isGrabbed {
                selectionHaptic.selectionChanged()
            }
            updateCubeAppearance()
        }
        refreshRestingFeedback()
    }

    private func refreshRestingFeedback() {
        guard transientFeedbackUntil == 0 else { return }
        if cubeEntity == nil {
            render(feedback: .searching)
            return
        }
        guard trackingIsNormal else {
            render(feedback: .trackingLimited(trackingDescription))
            return
        }
        if manipulator?.isGrabbed == true {
            render(feedback: .grabbed)
        } else if detector.needsReopen {
            render(feedback: .reopenToGrab)
        } else if wasTargeted {
            render(feedback: .targeted)
        } else {
            render(feedback: .ready)
        }
    }

    private func renderFingertips(_ sample: JarvisHandSample?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let sample {
            thumbLayer.position = sample.thumbTip
            indexLayer.position = sample.indexTip
            thumbLayer.isHidden = false
            indexLayer.isHidden = false
            let aim = detector.aimPoint ?? sample.pinchMidpoint
            aimLayer.position = aim
            aimLayer.isHidden = false
            let active = manipulator?.isGrabbed == true
            aimLayer.strokeColor = (active ? UIColor.systemGreen : (wasTargeted ? UIColor.systemYellow : UIColor.white)).withAlphaComponent(0.9).cgColor
        } else {
            thumbLayer.isHidden = true
            indexLayer.isHidden = true
            aimLayer.isHidden = true
        }
        CATransaction.commit()
    }

    // MARK: - Touch fallback

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard manipulator != nil, calibration == nil, trackingIsNormal else { return }
        let point = gesture.location(in: arView)
        let event: JarvisPinchEvent
        switch gesture.state {
        case .began: event = .began(point)
        case .changed: event = .moved(point)
        case .ended: event = .ended(point, .released)
        case .cancelled, .failed: event = .ended(point, .handLost)
        default: return
        }
        process(event, source: .touch, frameTimestamp: CACurrentMediaTime())
    }

    // MARK: - Calibration

    @objc private func calibrateTapped() {
        if calibration != nil {
            calibration = nil
            render(feedback: cubeEntity == nil ? .searching : .ready)
            calibrateButton.setTitle("Calibrer", for: .normal)
            return
        }
        freezeGrab()
        calibration = CalibrationRun(collectFrom: CACurrentMediaTime() + Self.calibrationPrepareDelay)
        calibrateButton.setTitle("Annuler", for: .normal)
        statusLabel.text = "Calibrage 1/2 : montrez la main ouverte, doigts écartés, face à la caméra."
    }

    private func feedCalibration(_ sample: JarvisHandSample?) {
        guard var run = calibration else { return }
        let now = CACurrentMediaTime()
        let ratio = sample.flatMap { $0.minimumConfidence >= detector.configuration.minimumConfidence ? $0.pinchRatio : nil }
        let recognized: String
        if let ratio {
            if ratio < detector.configuration.closeRatio {
                recognized = "pince reconnue"
            } else if ratio > detector.configuration.openRatio {
                recognized = "main ouverte reconnue"
            } else {
                recognized = "entre les deux"
            }
        } else {
            recognized = "main non détectée"
        }
        let ratioText = ratio.map { String(format: "%.2f", Double($0)) } ?? "—"
        let instruction = run.step == .open
            ? "Calibrage 1/2 : main ouverte, doigts écartés."
            : "Calibrage 2/2 : pincez le pouce et l'index."
        statusLabel.text = "\(instruction)\nActuellement : \(recognized) (rapport \(ratioText))."

        if now >= run.collectFrom, let ratio {
            if run.step == .open { run.openRatios.append(ratio) } else { run.pinchRatios.append(ratio) }
        }
        if now >= run.collectFrom + Self.calibrationCollectDuration {
            if run.step == .open {
                run.step = .pinch
                run.collectFrom = now + Self.calibrationPrepareDelay
                selectionHaptic.selectionChanged()
            } else {
                calibration = nil
                calibrateButton.setTitle("Calibrer", for: .normal)
                if let configuration = JarvisPinchCalibration.configuration(openRatios: run.openRatios, pinchRatios: run.pinchRatios, base: detector.configuration) {
                    configuration.save()
                    detector = JarvisPinchDetector(configuration: configuration)
                    dropHaptic.notificationOccurred(.success)
                    statusLabel.text = String(format: "Calibrage enregistré : pince sous %.2f, main ouverte au-dessus de %.2f.", Double(configuration.closeRatio), Double(configuration.openRatio))
                } else {
                    dropHaptic.notificationOccurred(.error)
                    statusLabel.text = "Calibrage impossible : main ouverte et pince trop proches ou main mal vue. Recommencez avec la main bien visible."
                }
                transientFeedbackUntil = now + 3.5
                return
            }
        }
        calibration = run
    }

    // MARK: - Voice

    private func wireVoice() {
        voiceInput.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .standby:
                self.talkButton.setTitle("Parler", for: .normal)
            case .listening:
                self.talkButton.setTitle("Terminer", for: .normal)
                self.showAnswer("Micro actif. Parlez maintenant.")
            case .hearingSound:
                if self.voiceInput.currentTranscript.isEmpty { self.showAnswer("Son reçu…") }
            case .heardYou(let transcript):
                self.showAnswer("« \(transcript) »")
            case .processing:
                self.talkButton.setTitle("Parler", for: .normal)
            case .noSpeech:
                self.talkButton.setTitle("Parler", for: .normal)
                self.showAnswer("Aucune parole détectée. Touchez « Parler » et réessayez.")
            case .unavailable(let failure):
                self.talkButton.setTitle("Parler", for: .normal)
                self.showAnswer(failure.message)
            }
        }
        voiceInput.onPartialTranscript = { [weak self] text in
            guard let self, !text.isEmpty else { return }
            self.showAnswer(text)
        }
        voiceInput.onInputLevel = nil
        voiceInput.onFinalTranscript = { [weak self] text in
            guard let self else { return }
            let response = self.assistant.decide(text).response
            self.showAnswer(response.displayResponse)
            if response.shouldSpeak, self.speech.isEnabled, response.status == .ok || response.status == .confirmationRequired {
                self.speech.speak(response.spokenResponse)
            }
        }
    }

    private func showAnswer(_ text: String) {
        answerLabel.text = text
        answerLabel.isHidden = text.isEmpty
    }

    @objc private func talkTapped() {
        if voiceInput.isListening {
            voiceInput.stopListening(process: true)
            return
        }
        speech.stop()
        voiceInput.startListening()
    }

    // MARK: - Buttons

    @objc private func closeTapped() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func metricsTapped() {
        showsMetrics.toggle()
        metricsLabel.isHidden = !showsMetrics
        metricsButton.setTitle(showsMetrics ? "Masquer" : "Mesures", for: .normal)
        renderMetrics()
    }

    @objc private func replaceTapped() {
        freezeGrab()
        if let anchor = cubeAnchor {
            arView.scene.removeAnchor(anchor)
        }
        cubeAnchor = nil
        cubeEntity = nil
        manipulator = nil
        wasTargeted = false
        detector.reset()
        searchingSince = CACurrentMediaTime()
        lastPlacementAttempt = 0
        render(feedback: .searching)
    }

    // MARK: - Rendering

    private func render(feedback newFeedback: Feedback, transientFor duration: CFTimeInterval = 0) {
        if duration > 0 {
            transientFeedbackUntil = CACurrentMediaTime() + duration
        } else if transientFeedbackUntil > 0 && CACurrentMediaTime() < transientFeedbackUntil {
            // Keep a short-lived message (Déposé, Pince à côté…) readable.
            if case .trackingLimited = newFeedback {} else if case .failed = newFeedback {} else { return }
        }
        guard calibration == nil else { return }
        if newFeedback != feedback || statusLabel.text != newFeedback.text {
            feedback = newFeedback
            statusLabel.text = newFeedback.text
        }
    }

    private func renderMetrics() {
        guard showsMetrics else { return }
        let ratio = detector.lastRatio.map { String(format: "%.2f", Double($0)) } ?? "—"
        let latency = metrics.lastLatencyMilliseconds.map { String(format: "%.0f ms", $0) } ?? "—"
        let phase: String
        switch detector.phase {
        case .noHand: phase = "aucune main"
        case .open: phase = "ouverte"
        case .pinched: phase = detector.isPinchActive ? "pince active" : "pince (inactive)"
        }
        metricsLabel.text = """
        Analyse main : \(String(format: "%.0f", metrics.handRate)) i/s · main vue \(String(format: "%.0f", metrics.handVisibleShare * 100)) %
        Rapport pince : \(ratio) (seuils \(String(format: "%.2f", Double(detector.configuration.closeRatio))) / \(String(format: "%.2f", Double(detector.configuration.openRatio)))) · \(phase)
        Pince → mouvement : \(latency)
        Saisies \(metrics.grabs) · lâchers \(metrics.drops) · ratées \(metrics.misses) · pertes \(metrics.losses)
        Suivi : \(trackingDescription)
        """
    }

    private func postAnnouncement(_ text: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .announcement, argument: text)
    }
}
