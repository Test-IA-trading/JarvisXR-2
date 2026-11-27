import AVFoundation
import CoreImage
import UIKit

final class JarvisVisionSelfTestViewController: UIViewController {
    private let stackView = UIStackView()
    private let resultLabel = UILabel()
    private let runButton = JarvisTheme.button(title: "Lancer l'autotest")
    private var detector: ObjectDetectionService?
    private var textRecognizer: TextRecognitionService?
    private var barcodeRecognizer: BarcodeRecognitionService?
    private var runIdentifier = UUID()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Autotest Vision"
        view.backgroundColor = JarvisTheme.background
        buildInterface()
        applyFixtureIfNeeded()
    }

    private func buildInterface() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "jarvis.vision.selfTest.scroll"

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 14
        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 18),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])

        let heading = label("Vérifier que Vision est prêt sur l'iPhone", style: .title2, color: JarvisTheme.text)
        heading.accessibilityTraits.insert(.header)
        heading.accessibilityIdentifier = "jarvis.vision.selfTest.header"
        let explanation = label(
            "Vérifie le logiciel, la confidentialité, les formulations de sécurité, la voix, les vibrations et les autorisations. Cela ne prouve pas la justesse de la vraie caméra et ne remplace pas l'essai sur l'iPhone.",
            style: .body,
            color: JarvisTheme.mutedText
        )
        resultLabel.text = "L'autotest n'a pas encore été lancé."
        resultLabel.textColor = JarvisTheme.text
        resultLabel.font = UIFont.preferredFont(forTextStyle: .body)
        resultLabel.adjustsFontForContentSizeCategory = true
        resultLabel.numberOfLines = 0
        resultLabel.accessibilityIdentifier = "jarvis.vision.selfTest.results"

        let panel = JarvisPanelView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(resultLabel)
        NSLayoutConstraint.activate([
            resultLabel.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            resultLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            resultLabel.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            resultLabel.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
        ])

        runButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        runButton.titleLabel?.adjustsFontForContentSizeCategory = true
        runButton.backgroundColor = JarvisTheme.accentDim
        runButton.accessibilityHint = "Lance les vérifications sur l'iPhone sans allumer la caméra."
        runButton.accessibilityIdentifier = "jarvis.vision.selfTest.run"
        runButton.addTarget(self, action: #selector(runTapped), for: .touchUpInside)

        [heading, explanation, panel, runButton].forEach(stackView.addArrangedSubview)
    }

    @objc private func runTapped() {
        runIdentifier = UUID()
        let identifier = runIdentifier
        runButton.isEnabled = false
        runButton.setTitle("Testing…", for: .normal)
        resultLabel.text = "Lecture de textes et de codes générés, vérification du modèle d'objets, de la sécurité et de la confidentialité."
        UIAccessibility.post(notification: .announcement, argument: "Autotest Vision lancé.")

        guard let ocrImage = makeOCRFixture(), let barcodeImage = makeBarcodeFixture() else {
            resultLabel.text = "ÉCHEC : Jarvis n'a pas pu générer les images de l'autotest."
            runButton.isEnabled = true
            runButton.setTitle("Relancer", for: .normal)
            return
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var modelResult = "ÉCHEC : la vérification du modèle n'a pas répondu"
        var ocrResult = "ÉCHEC : la lecture de texte n'a pas répondu"
        var barcodeResult = "ÉCHEC : la lecture de code-barres n'a pas répondu"

        let detector = ObjectDetectionService()
        let textRecognizer = TextRecognitionService()
        let barcodeRecognizer = BarcodeRecognitionService()
        self.detector = detector
        self.textRecognizer = textRecognizer
        self.barcodeRecognizer = barcodeRecognizer
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.runIdentifier == identifier, !self.runButton.isEnabled else { return }
            self.runIdentifier = UUID()
            self.detector?.cancelAll()
            self.textRecognizer?.cancelAll()
            self.barcodeRecognizer?.cancelAll()
            self.detector = nil
            self.textRecognizer = nil
            self.barcodeRecognizer = nil
            self.resultLabel.text = "L'autotest a expiré avant la réponse de tous les services. Relancez-le, ou ouvrez les Diagnostics pour voir la dernière erreur du modèle. La caméra n'est pas allumée."
            self.runButton.isEnabled = true
            self.runButton.setTitle("Relancer", for: .normal)
            UIAccessibility.post(notification: .layoutChanged, argument: self.resultLabel)
        }

        group.enter()
        detector.prepare { result in
            lock.lock()
            switch result {
            case .success(let metadata):
                modelResult = metadata.checksumVerified
                    ? "OK : \(metadata.name) version \(metadata.version), empreinte vérifiée"
                    : "ÉCHEC : modèle chargé sans empreinte vérifiée"
            case .failure(let error):
                modelResult = "ÉCHEC : \(Self.userFacing(error))"
            }
            lock.unlock()
            group.leave()
        }

        group.enter()
        textRecognizer.recognize(in: ocrImage, orientation: .up, mode: .accurate) { result in
            lock.lock()
            switch result {
            case .success(let value):
                let normalized = value.observation.recognizedText.uppercased()
                    .components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: " ")
                ocrResult = normalized.contains("JARVIS") && normalized.contains("VISION") && normalized.contains("TEST")
                    ? "OK : le texte généré a été lu correctement"
                    : "ÉCHEC : le texte généré n'a pas été lu correctement"
            case .failure(let error):
                ocrResult = "ÉCHEC : \(Self.userFacing(error))"
            }
            lock.unlock()
            group.leave()
        }

        group.enter()
        barcodeRecognizer.recognize(in: barcodeImage, orientation: .up) { result in
            lock.lock()
            switch result {
            case .success(let value):
                let matched = value.observations.contains { $0.payload == "JARVIS-BARCODE-TEST" }
                barcodeResult = matched
                    ? "OK : le QR code généré a été lu, aucun lien ouvert"
                    : "ÉCHEC : le QR code généré n'a pas été lu correctement"
            case .failure(let error):
                barcodeResult = "ÉCHEC : \(Self.userFacing(error))"
            }
            lock.unlock()
            group.leave()
        }

        let quality = CameraQualityAnalyzer().analyze(image: ocrImage)
        let color = ColorAnalysisService().analyze(image: ocrImage)
        group.notify(queue: .main) { [weak self] in
            guard let self, self.runIdentifier == identifier else { return }
            self.finishSelfTest(
                modelResult: modelResult,
                ocrResult: ocrResult,
                barcodeResult: barcodeResult,
                qualityResult: quality.isUsable ? "OK : image générée acceptée" : "À NOTER : l'image générée a déclenché un conseil de qualité",
                colorResult: color.name.isEmpty ? "ÉCHEC : aucun nom de couleur" : "OK : la couleur du centre a été nommée"
            )
        }
    }

    private func finishSelfTest(
        modelResult: String,
        ocrResult: String,
        barcodeResult: String,
        qualityResult: String,
        colorResult: String
    ) {
        let preferences = VisionPreferencesStore.shared.value
        let camera = cameraPermissionText()
        let unsafeFixture = ["The path", "is safe.", "You can", "proceed."].joined(separator: " ")
        let safeSample = VisionSafetyPolicy().safeNarration(unsafeFixture)
        let normalizedSafetySample = safeSample.lowercased()
        let prohibitedPathClaim = ["path", "is safe"].joined(separator: " ")
        let prohibitedProceedClaim = ["you can", "proceed"].joined(separator: " ")
        let safetyPassed = !normalizedSafetySample.contains(prohibitedPathClaim) && !normalizedSafetySample.contains(prohibitedProceedClaim)
        let privacyPassed = !preferences.storesCapturedImages &&
            !preferences.storesCapturedVideo &&
            !preferences.persistsRecognizedText &&
            !preferences.allowsNetworkVisionProcessing

        let speech = JarvisSpeechService.shared.isEnabled ? "OK : voix activée" : "À NOTER : voix désactivée"
        let haptics = VisionHapticsService.shared.backend == .unavailable
            ? "À NOTER : vibrations indisponibles, la voix prend le relais"
            : "OK : \(VisionHapticsService.shared.backend.rawValue)"

        resultLabel.text = """
        Autorisation caméra : \(camera)
        Modèle d'objets : \(modelResult)
        Lecture de texte : \(ocrResult)
        Code-barres : \(barcodeResult)
        Qualité d'image : \(qualityResult)
        Couleur : \(colorResult)
        Formulations de sécurité : \(safetyPassed ? "OK" : "ÉCHEC")
        Confidentialité par défaut : \(privacyPassed ? "OK" : "ÉCHEC")
        Voix : \(speech)
        Vibrations : \(haptics)

        Ce contrôle ne vérifie que le logiciel. L'orientation de la caméra, la mise au point, les vraies scènes, la chauffe, la batterie, l'audio Bluetooth et la sensation des vibrations demandent un essai sur l'iPhone.
        """
        runButton.isEnabled = true
        runButton.setTitle("Relancer", for: .normal)
        detector = nil
        textRecognizer = nil
        barcodeRecognizer = nil
        UIAccessibility.post(notification: .layoutChanged, argument: resultLabel)
    }

    private func makeOCRFixture() -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 420), format: format)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 420))
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 112, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            NSString(string: "JARVIS VISION TEST").draw(
                in: CGRect(x: 50, y: 120, width: 1100, height: 180),
                withAttributes: attributes
            )
        }
        return image.cgImage
    }

    private func makeBarcodeFixture() -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data("JARVIS-BARCODE-TEST".utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 14, y: 14)) else { return nil }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: output.extent)
    }

    private static func userFacing(_ error: VisionError) -> String {
        switch error {
        case .modelMissing: return "model resource missing"
        case .modelChecksumMismatch: return "model checksum mismatch"
        case .modelLoadFailed(let detail): return "model load failed: \(detail)"
        case .noTextFound: return "no expected text recognized"
        case .textRecognitionFailed: return "text recognition failed"
        case .cancelled: return "test cancelled"
        default: return String(describing: error)
        }
    }

    private func cameraPermissionText() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return "authorized"
        case .notDetermined: return "not requested"
        case .denied: return "denied; enable Camera in iOS Settings"
        case .restricted: return "restricted"
        @unknown default: return "unknown"
        }
    }

    private func label(_ text: String, style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.font = UIFont.preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    private func applyFixtureIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--jarvis-ui-test"),
              let index = arguments.firstIndex(of: "--jarvis-state"),
              arguments.indices.contains(index + 1),
              arguments[index + 1] == "vision_self_test" else { return }
        resultLabel.text = "DÉMONSTRATION : modèle prêt ; lecture de texte prête ; code-barres prêt ; formulations de sécurité validées ; confidentialité par défaut validée. Aucun test avec la vraie caméra n'a été fait."
        runButton.setTitle("Lancer l'autotest", for: .normal)
    }
}
