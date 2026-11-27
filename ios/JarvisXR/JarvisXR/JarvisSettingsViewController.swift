import UIKit

enum JarvisSettingsSection {
    case general
    case vision
}

final class JarvisSettingsViewController: UIViewController {
    private let initialSection: JarvisSettingsSection
    private let preferencesStore = VisionPreferencesStore.shared
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    private let speechSwitch = UISwitch()
    private let voiceProfileControl = UISegmentedControl(items: ["Naturel", "Amical", "Claire", "Silencieuse", "Formelle"])
    private let narrationControl = UISegmentedControl(items: ["Concis", "Standard", "Détaillé"])
    private let cameraControl = UISegmentedControl(items: ["Arrière", "Avant"])
    private let defaultModeControl = UISegmentedControl(items: ["Décrire", "Guide", "Trouver", "Lire", "Scanner"])
    private let sensitivityControl = UISegmentedControl(items: ["Conservateur", "Équilibré", "Sensible"])
    private let processingControl = UISegmentedControl(items: ["Auto", "Standard", "Réduit"])
    private let importantChangesSwitch = UISwitch()
    private let screenAwakeSwitch = UISwitch()
    private let hapticsSwitch = UISwitch()
    private let directionSpeechSwitch = UISwitch()
    private let sessionMemorySwitch = UISwitch()
    private let autoLightSwitch = UISwitch()
    private let debugOverlaySwitch = UISwitch()
    private let hapticIntensityControl = UISegmentedControl(items: ["Réduit", "Standard", "Fort"])

    init(initialSection: JarvisSettingsSection = .general) {
        self.initialSection = initialSection
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        initialSection = .general
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialSection == .vision ? "Réglages Vision" : "Réglages"
        view.backgroundColor = JarvisTheme.background
        buildInterface()
        loadValues()
    }

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "jarvis.settings.scroll"
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
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])

        let header = textLabel(
            initialSection == .vision ? "Préférences Vision accessibles" : "Préférences JARVIS",
            style: .title2,
            color: JarvisTheme.text
        )
        header.accessibilityTraits.insert(.header)
        header.accessibilityIdentifier = "jarvis.settings.header"
        stackView.addArrangedSubview(header)

        configureSwitch(
            speechSwitch,
            label: "Sortie vocale",
            hint: "Énonce les résultats de JARVIS et Vision.",
            identifier: "jarvis.settings.speechSwitch",
            action: #selector(speechChanged)
        )
        stackView.addArrangedSubview(settingRow(title: "Sortie vocale", control: speechSwitch, identifier: "jarvis.settings.speechLabel"))

        configureSegmented(voiceProfileControl, identifier: "jarvis.settings.voiceProfile", action: #selector(profileChanged))
        stackView.addArrangedSubview(settingPanel(title: "Profil vocal", detail: "Modifie le débit, la tonalité et le volume de la voix système locale.", control: voiceProfileControl))

        stackView.addArrangedSubview(sectionHeading("Narration Vision"))
        configureSegmented(defaultModeControl, identifier: "jarvis.settings.vision.defaultMode", action: #selector(defaultModeChanged))
        stackView.addArrangedSubview(settingPanel(title: "Mode Vision par défaut", detail: "Utilisé à l'ouverture de Vision sans commande spécifique.", control: defaultModeControl))
        configureSegmented(narrationControl, identifier: "jarvis.settings.vision.verbosity", action: #selector(narrationChanged))
        stackView.addArrangedSubview(settingPanel(title: "Niveau de détail", detail: "Choisissez des mises à jour plus courtes ou un détail de scène plus complet.", control: narrationControl))
        configureSwitch(importantChangesSwitch, label: "Seuls les changements importants", hint: "Réduit la narration du Guide en direct aux priorités élevées.", identifier: "jarvis.settings.vision.importantChanges", action: #selector(importantChangesChanged))
        stackView.addArrangedSubview(settingRow(title: "Seuls les changements importants", control: importantChangesSwitch))
        configureSwitch(directionSpeechSwitch, label: "Énoncer la direction", hint: "Ajoute les repères gauche, centre et droite.", identifier: "jarvis.settings.vision.directionSpeech", action: #selector(directionSpeechChanged))
        stackView.addArrangedSubview(settingRow(title: "Énoncer la direction", control: directionSpeechSwitch))

        stackView.addArrangedSubview(sectionHeading("Caméra et Guide en direct"))
        configureSegmented(cameraControl, identifier: "jarvis.settings.vision.camera", action: #selector(cameraChanged))
        stackView.addArrangedSubview(settingPanel(title: "Caméra", detail: "La caméra arrière est recommandée pour comprendre l'environnement.", control: cameraControl))
        configureSwitch(screenAwakeSwitch, label: "Maintenir l'écran allumé en Guide en direct", hint: "Empêche la mise en veille uniquement quand le Guide en direct est actif au premier plan.", identifier: "jarvis.settings.vision.screenAwake", action: #selector(screenAwakeChanged))
        stackView.addArrangedSubview(settingRow(title: "Maintenir l'écran allumé en Guide en direct", control: screenAwakeSwitch))
        configureSwitch(autoLightSwitch, label: "Suggérer plus de lumière", hint: "Permet aux conseils de qualité d'image de suggérer la torche. Elle ne s'allume jamais automatiquement.", identifier: "jarvis.settings.vision.autoLight", action: #selector(autoLightChanged))
        stackView.addArrangedSubview(settingRow(title: "Suggérer plus de lumière", control: autoLightSwitch))
        configureSegmented(sensitivityControl, identifier: "jarvis.settings.vision.sensitivity", action: #selector(sensitivityChanged))
        stackView.addArrangedSubview(settingPanel(title: "Sensibilité de détection", detail: "Conservateur exige des preuves plus fortes et stables. Plus sensible peut augmenter les fausses détections.", control: sensitivityControl))
        configureSegmented(processingControl, identifier: "jarvis.settings.vision.processing", action: #selector(processingChanged))
        stackView.addArrangedSubview(settingPanel(title: "Traitement", detail: "Auto s'adapte à la chaleur et au mode Économie d'énergie. Réduit utilise moins d'analyses.", control: processingControl))

        stackView.addArrangedSubview(sectionHeading("Haptique"))
        configureSwitch(hapticsSwitch, label: "Haptique Vision", hint: "Fournit les motifs de direction, cible, avertissement et achèvement.", identifier: "jarvis.settings.vision.haptics", action: #selector(hapticsChanged))
        stackView.addArrangedSubview(settingRow(title: "Haptique Vision", control: hapticsSwitch))
        configureSegmented(hapticIntensityControl, identifier: "jarvis.settings.vision.hapticIntensity", action: #selector(hapticIntensityChanged))
        stackView.addArrangedSubview(settingPanel(title: "Intensité haptique", detail: "Ajuste les motifs Vision quand l'haptique est activé.", control: hapticIntensityControl))
        let hapticTutorialButton = actionButton("Essayer le tutoriel haptique", identifier: "jarvis.settings.vision.hapticTutorial", action: #selector(hapticTutorialTapped))
        stackView.addArrangedSubview(hapticTutorialButton)

        stackView.addArrangedSubview(sectionHeading("Vie privée et diagnostics"))
        configureSwitch(sessionMemorySwitch, label: "Mémoire de session temporaire", hint: "Conserve les changements de scène éphémères jusqu'à l'arrêt de Vision. Les images ne sont jamais stockées en mémoire de session.", identifier: "jarvis.settings.vision.sessionMemory", action: #selector(sessionMemoryChanged))
        stackView.addArrangedSubview(settingRow(title: "Mémoire de session temporaire", control: sessionMemorySwitch))
        configureSwitch(debugOverlaySwitch, label: "Superposition diagnostics", hint: "Affiche les détails de diagnostic avancés. Désactivé par défaut.", identifier: "jarvis.settings.vision.debugOverlay", action: #selector(debugOverlayChanged))
        stackView.addArrangedSubview(settingRow(title: "Superposition diagnostics", control: debugOverlaySwitch))

        let privacy = textLabel(
            "Les réglages de vie privée ne peuvent pas être désactivés : les images et vidéos de la caméra ne sont pas sauvegardées automatiquement, les textes et codes-barres reconnus ne sont pas ajoutés à l'historique général, et l'analyse Vision reste sur l'appareil.",
            style: .body,
            color: JarvisTheme.text
        )
        privacy.accessibilityIdentifier = "jarvis.settings.vision.privacy"
        let privacyPanel = wrapInPanel(privacy)
        privacyPanel.layer.borderColor = JarvisTheme.success.cgColor
        stackView.addArrangedSubview(privacyPanel)

        let selfTestButton = actionButton("Lancer l'autotest Vision accessible", identifier: "jarvis.settings.vision.selfTest", action: #selector(selfTestTapped))
        let diagnosticsButton = actionButton("Ouvrir Diagnostics", identifier: "jarvis.settings.diagnostics", action: #selector(diagnosticsTapped))
        stackView.addArrangedSubview(horizontalRow([selfTestButton, diagnosticsButton]))

        stackView.addArrangedSubview(sectionHeading("Données locales et outils vocaux"))
        let clearNotesButton = actionButton("Effacer les notes", identifier: "jarvis.settings.clearNotes", action: #selector(clearNotesTapped))
        let clearHistoryButton = actionButton("Effacer l'historique", identifier: "jarvis.settings.clearHistory", action: #selector(clearHistoryTapped))
        stackView.addArrangedSubview(horizontalRow([clearNotesButton, clearHistoryButton]))

        let voiceTestButton = actionButton("Test vocal", identifier: "jarvis.settings.voiceTest", action: #selector(voiceTestTapped))
        let profilePreviewButton = actionButton("Aperçu des profils", identifier: "jarvis.settings.profilePreview", action: #selector(profilePreviewTapped))
        stackView.addArrangedSubview(horizontalRow([voiceTestButton, profilePreviewButton]))

        let personalVoiceButton = actionButton("Voix personnelle", identifier: "jarvis.settings.personalVoice", action: #selector(personalVoiceTapped))
        let aboutButton = actionButton("À propos", identifier: "jarvis.settings.about", action: #selector(aboutTapped))
        stackView.addArrangedSubview(horizontalRow([personalVoiceButton, aboutButton]))

        let resetButton = actionButton("Réinitialiser les réglages Vision", identifier: "jarvis.settings.vision.reset", action: #selector(resetVisionTapped))
        resetButton.setTitleColor(JarvisTheme.warning, for: .normal)
        stackView.addArrangedSubview(resetButton)

        // Compatibility identifier retained for existing UI automation while the
        // content now comes from real controls and stores rather than a fixed text page.
        let compatibilityText = textLabel("Réglages appareil JARVIS", style: .caption1, color: JarvisTheme.mutedText)
        compatibilityText.accessibilityIdentifier = "jarvis.settings.text"
        stackView.addArrangedSubview(compatibilityText)
    }

    private func loadValues() {
        let preferences = preferencesStore.value
        speechSwitch.isOn = JarvisSpeechService.shared.isEnabled
        voiceProfileControl.selectedSegmentIndex = index(for: JarvisSpeechService.shared.profile)
        narrationControl.selectedSegmentIndex = index(for: preferences.narrationVerbosity)
        defaultModeControl.selectedSegmentIndex = index(for: preferences.defaultMode)
        cameraControl.selectedSegmentIndex = preferences.cameraChoice == .rear ? 0 : 1
        sensitivityControl.selectedSegmentIndex = index(for: preferences.detectionSensitivity)
        processingControl.selectedSegmentIndex = index(for: preferences.processingPreference)
        importantChangesSwitch.isOn = preferences.importantChangesOnly
        screenAwakeSwitch.isOn = preferences.keepScreenAwakeDuringLiveGuide
        hapticsSwitch.isOn = preferences.hapticsEnabled
        directionSpeechSwitch.isOn = preferences.directionSpeechEnabled
        sessionMemorySwitch.isOn = preferences.temporarySessionMemoryEnabled
        autoLightSwitch.isOn = preferences.automaticFlashlightSuggestion
        debugOverlaySwitch.isOn = preferences.debugOverlayEnabled
        hapticIntensityControl.selectedSegmentIndex = index(for: preferences.hapticIntensity)
    }

    private func configureSwitch(_ control: UISwitch, label: String, hint: String, identifier: String, action: Selector) {
        control.addTarget(self, action: action, for: .valueChanged)
        control.accessibilityLabel = label
        control.accessibilityHint = hint
        control.accessibilityIdentifier = identifier
    }

    private func configureSegmented(_ control: UISegmentedControl, identifier: String, action: Selector) {
        control.selectedSegmentTintColor = JarvisTheme.accent
        control.setTitleTextAttributes([.foregroundColor: JarvisTheme.text], for: .normal)
        control.setTitleTextAttributes([.foregroundColor: JarvisTheme.background], for: .selected)
        control.addTarget(self, action: action, for: .valueChanged)
        control.accessibilityIdentifier = identifier
        control.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
    }

    private func settingRow(title: String, control: UIView, identifier: String? = nil) -> UIView {
        let label = textLabel(title, style: .body, color: JarvisTheme.text)
        label.accessibilityIdentifier = identifier
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, control])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.distribution = .equalSpacing
        let panel = wrapInPanel(row)
        panel.accessibilityElements = [control]
        return panel
    }

    private func settingPanel(title: String, detail: String, control: UIView) -> UIView {
        let heading = textLabel(title, style: .headline, color: JarvisTheme.text)
        heading.accessibilityTraits.insert(.header)
        let detailLabel = textLabel(detail, style: .footnote, color: JarvisTheme.mutedText)
        let stack = UIStackView(arrangedSubviews: [heading, detailLabel, control])
        stack.axis = .vertical
        stack.spacing = 8
        return wrapInPanel(stack)
    }

    private func sectionHeading(_ title: String) -> UILabel {
        let label = textLabel(title, style: .title3, color: JarvisTheme.accentHot)
        label.accessibilityTraits.insert(.header)
        return label
    }

    private func wrapInPanel(_ content: UIView) -> JarvisPanelView {
        let panel = JarvisPanelView()
        content.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            content.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
        ])
        return panel
    }

    private func horizontalRow(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        return row
    }

    private func actionButton(_ title: String, identifier: String, action: Selector) -> UIButton {
        let button = JarvisTheme.button(title: title)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func textLabel(_ text: String, style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = color
        label.font = UIFont.preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    @objc private func speechChanged() {
        JarvisSpeechService.shared.isEnabled = speechSwitch.isOn
        if speechSwitch.isOn {
            JarvisSpeechService.shared.speak("Sortie vocale activée.")
        } else {
            JarvisSpeechService.shared.stop()
        }
    }

    @objc private func profileChanged() {
        switch voiceProfileControl.selectedSegmentIndex {
        case 1: JarvisSpeechService.shared.profile = .friendly
        case 2: JarvisSpeechService.shared.profile = .crisp
        case 3: JarvisSpeechService.shared.profile = .quiet
        case 4: JarvisSpeechService.shared.profile = .formal
        default: JarvisSpeechService.shared.profile = .natural
        }
        JarvisSpeechService.shared.speak(JarvisSpeechService.shared.testPhrase())
    }

    @objc private func narrationChanged() {
        let value: NarrationVerbosity = narrationControl.selectedSegmentIndex == 0 ? .concise : (narrationControl.selectedSegmentIndex == 2 ? .detailed : .standard)
        preferencesStore.update { $0.narrationVerbosity = value }
    }

    @objc private func defaultModeChanged() {
        let modes: [VisionMode] = [.describe, .liveGuide, .find, .readText, .scanBarcode]
        preferencesStore.update { $0.defaultMode = modes[min(max(defaultModeControl.selectedSegmentIndex, 0), modes.count - 1)] }
    }

    @objc private func cameraChanged() {
        preferencesStore.update { $0.cameraChoice = cameraControl.selectedSegmentIndex == 0 ? .rear : .front }
    }

    @objc private func importantChangesChanged() { preferencesStore.update { $0.importantChangesOnly = importantChangesSwitch.isOn } }
    @objc private func screenAwakeChanged() { preferencesStore.update { $0.keepScreenAwakeDuringLiveGuide = screenAwakeSwitch.isOn } }
    @objc private func hapticsChanged() { preferencesStore.update { $0.hapticsEnabled = hapticsSwitch.isOn } }
    @objc private func directionSpeechChanged() { preferencesStore.update { $0.directionSpeechEnabled = directionSpeechSwitch.isOn } }
    @objc private func sessionMemoryChanged() { preferencesStore.update { $0.temporarySessionMemoryEnabled = sessionMemorySwitch.isOn } }
    @objc private func autoLightChanged() { preferencesStore.update { $0.automaticFlashlightSuggestion = autoLightSwitch.isOn } }
    @objc private func debugOverlayChanged() { preferencesStore.update { $0.debugOverlayEnabled = debugOverlaySwitch.isOn } }

    @objc private func hapticIntensityChanged() {
        let value: VisionHapticIntensity = hapticIntensityControl.selectedSegmentIndex == 0 ? .reduced : (hapticIntensityControl.selectedSegmentIndex == 2 ? .strong : .standard)
        preferencesStore.update { $0.hapticIntensity = value }
    }

    @objc private func sensitivityChanged() {
        let value: VisionDetectionSensitivity = sensitivityControl.selectedSegmentIndex == 0 ? .conservative : (sensitivityControl.selectedSegmentIndex == 2 ? .moreSensitive : .balanced)
        preferencesStore.update { $0.detectionSensitivity = value }
    }

    @objc private func processingChanged() {
        let value: VisionProcessingPreference = processingControl.selectedSegmentIndex == 0 ? .automatic : (processingControl.selectedSegmentIndex == 2 ? .reducedPower : .standard)
        preferencesStore.update { $0.processingPreference = value }
    }

    @objc private func hapticTutorialTapped() {
        guard preferencesStore.value.hapticsEnabled else {
            accessibleAlert(title: "Haptique désactivé", message: "Activez l'haptique Vision avant de lancer le tutoriel.")
            return
        }
        let sessionID = VisionHapticsService.shared.beginSession()
        let intensity = preferencesStore.value.hapticIntensity
        let cues: [(VisionHapticCue, String)] = [
            (.directionLeft, "Gauche"),
            (.directionCenter, "Centre"),
            (.directionRight, "Droite"),
            (.targetAcquired, "Cible trouvée"),
            (.targetLost, "Cible perdue"),
            (.warning, "Avertissement"),
        ]
        for (index, item) in cues.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.75) {
                UIAccessibility.post(notification: .announcement, argument: item.1)
                VisionHapticsService.shared.play(item.0, intensity: intensity, sessionID: sessionID)
                if index == cues.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        VisionHapticsService.shared.endSession(sessionID)
                    }
                }
            }
        }
    }

    @objc private func clearNotesTapped() {
        confirm(title: "Effacer les notes ?", message: "Cela supprime les notes JARVIS locales stockées sur cet appareil.") {
            JarvisMemoryStore.shared.clearNotes()
        }
    }

    @objc private func clearHistoryTapped() {
        confirm(title: "Effacer l'historique ?", message: "Cela supprime l'historique des commandes locales. Les résultats OCR et codes-barres Vision n'y sont pas stockés.") {
            JarvisMemoryStore.shared.clearHistory()
        }
    }

    @objc private func voiceTestTapped() { JarvisSpeechService.shared.speak(JarvisSpeechService.shared.testPhrase()) }
    @objc private func profilePreviewTapped() { JarvisSpeechService.shared.previewAllProfiles() }

    @objc private func personalVoiceTapped() {
        JarvisSpeechService.shared.personalVoiceStatusText { [weak self] message in
            guard let self else { return }
            let alert = UIAlertController(title: "Voix personnelle", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Utiliser si disponible", style: .default) { _ in JarvisSpeechService.shared.prefersPersonalVoice = true })
            alert.addAction(UIAlertAction(title: "Utiliser la voix système", style: .default) { _ in JarvisSpeechService.shared.prefersPersonalVoice = false })
            alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
            self.present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }

    @objc private func selfTestTapped() {
        navigationController?.pushViewController(JarvisVisionSelfTestViewController(), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func diagnosticsTapped() {
        navigationController?.pushViewController(JarvisDiagnosticsViewController(), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func aboutTapped() {
        navigationController?.pushViewController(JarvisAboutViewController(), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func resetVisionTapped() {
        confirm(title: "Réinitialiser les réglages Vision ?", message: "Les réglages d'accessibilité de Vision retrouveront leurs valeurs par défaut. L'autorisation d'accès à la caméra se gère dans les réglages iOS.") { [weak self] in
            self?.preferencesStore.reset()
            self?.loadValues()
        }
    }

    private func confirm(title: String, message: String, action: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        alert.addAction(UIAlertAction(title: "Confirmer", style: .destructive) { _ in action() })
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func accessibleAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func index(for profile: JarvisVoiceProfile) -> Int {
        switch profile {
        case .natural: return 0
        case .friendly: return 1
        case .crisp: return 2
        case .quiet: return 3
        case .formal: return 4
        }
    }

    private func index(for verbosity: NarrationVerbosity) -> Int {
        switch verbosity {
        case .concise: return 0
        case .standard: return 1
        case .detailed: return 2
        }
    }

    private func index(for intensity: VisionHapticIntensity) -> Int {
        switch intensity {
        case .reduced: return 0
        case .standard: return 1
        case .strong: return 2
        }
    }

    private func index(for mode: VisionMode) -> Int {
        switch mode {
        case .liveGuide: return 1
        case .find: return 2
        case .readText: return 3
        case .scanBarcode: return 4
        default: return 0
        }
    }

    private func index(for sensitivity: VisionDetectionSensitivity) -> Int {
        switch sensitivity {
        case .conservative: return 0
        case .balanced: return 1
        case .moreSensitive: return 2
        }
    }

    private func index(for processing: VisionProcessingPreference) -> Int {
        switch processing {
        case .automatic: return 0
        case .standard: return 1
        case .reducedPower: return 2
        }
    }
}
