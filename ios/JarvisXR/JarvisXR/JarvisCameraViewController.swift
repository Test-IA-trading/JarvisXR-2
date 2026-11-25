import AVFoundation
import UIKit

/// The accessible Jarvis Vision product surface. Camera ownership, analysis,
/// tracking, safety policy, and narration remain in their dedicated services.
final class JarvisCameraViewController: UIViewController {
    private let camera = CameraSessionService()
    private let pipeline = VisionPipelineCoordinator()
    private let speech = JarvisSpeechService.shared
    private let voiceInput = JarvisVoiceInputService.shared
    private let haptics = VisionHapticsService.shared
    private let preferencesStore = VisionPreferencesStore.shared
    /// The phone's own rotation during Live Guide, so a pan is not announced as a move.
    private let motionMonitor = VisionCameraMotionMonitor()
    /// Vision speech is held while the microphone listens, so Jarvis does not hear itself.
    private var narrationPausedForListening = false

    private var launchRequest: JarvisVisionLaunchRequest
    private var currentMode: VisionMode
    private var currentState: VisionSessionState = .idle
    private var currentTarget: String?
    private var requestedRegion: SpatialRegion?
    private var speechSessionID: UUID?
    private var hapticSessionID: UUID?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasAppliedInitialRequest = false
    private var isFixtureDriven = false
    private var ignoredAutomaticNarrationSnapshotID: UUID?
    private var latestSnapshot: SceneSnapshot?
    private var lastPresentedNarration: SceneNarration?
    private var lastAnnouncement: (text: String, date: Date)?
    private var lastTargetCentered = false

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let fixtureBanner = UILabel()
    private let modeScrollView = UIScrollView()
    private let modeStack = UIStackView()
    private var modeButtons: [VisionMode: UIButton] = [:]
    private let modeLabel = UILabel()
    private let stateLabel = UILabel()
    private let guidanceLabel = UILabel()
    private let previewView = UIView()
    private let resultPanel = JarvisPanelView()
    private let resultLabel = UILabel()
    private let failurePanel = JarvisPanelView()
    private let failureLabel = UILabel()
    private let openSystemSettingsButton = JarvisTheme.button(title: "Ouvrir les Réglages iOS")
    private let retryButton = JarvisTheme.button(title: "Réessayer")
    private let primaryButton = UIButton(type: .system)
    private let repeatButton = JarvisTheme.button(title: "Répéter")
    private let lightButton = JarvisTheme.button(title: "Lampe éteinte")
    private let moreDetailButton = JarvisTheme.button(title: "Plus de détails")
    private let readingControls = UIStackView()
    private let previousLineButton = JarvisTheme.button(title: "Ligne précédente")
    private let pauseReadingButton = JarvisTheme.button(title: "Pause lecture")
    private let nextLineButton = JarvisTheme.button(title: "Ligne suivante")
    private let bottomBar = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterialDark))
    private let voiceButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)

    private var preferences: VisionPreferences { preferencesStore.value }

    init(launchRequest: JarvisVisionLaunchRequest = JarvisVisionLaunchRequest()) {
        self.launchRequest = launchRequest
        self.currentMode = launchRequest.mode == .inactive ? .describe : launchRequest.mode
        self.currentTarget = launchRequest.target
        self.requestedRegion = launchRequest.region
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        launchRequest = JarvisVisionLaunchRequest()
        currentMode = .describe
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Jarvis Vision"
        view.backgroundColor = JarvisTheme.background
        navigationItem.largeTitleDisplayMode = .never
        buildInterface()
        wireServices()
        setMode(currentMode, announce: false)
        renderState(.idle, guidance: currentMode.visionReadyGuidance, announce: false)
        applyFixtureStateIfNeeded()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !hasAppliedInitialRequest else { return }
        hasAppliedInitialRequest = true
        guard !isFixtureDriven else { return }
        apply(launchRequest)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isMovingFromParent || navigationController?.topViewController !== self else { return }
        stopVision(announce: false, message: "Vision arrêtée.")
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = previewView.bounds
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        pipeline.stop()
        pipeline.unbindCamera()
        camera.shutdown()
        voiceInput.cancel()
        motionMonitor.stop()
    }

    func apply(_ request: JarvisVisionLaunchRequest) {
        launchRequest = request
        if request.command == .run || request.command == .checkQuality {
            currentTarget = request.mode == .find ? request.target : nil
            requestedRegion = request.region
        } else if let target = request.target {
            currentTarget = target
        }

        let selectsMode: Bool
        switch request.command {
        case .run, .checkQuality:
            selectsMode = true
        case .pause, .resume, .nextReadingLine, .previousReadingLine:
            selectsMode = currentState != .active && currentState != .paused
        default:
            selectsMode = false
        }
        if selectsMode, request.mode != .inactive {
            if request.mode != currentMode,
               currentState == .active || currentState == .paused || currentState == .preparing {
                stopVision(announce: false, message: "Mode Vision précédent arrêté.")
            }
            setMode(request.mode, announce: true)
        }

        switch request.command {
        case .run:
            if request.startsImmediately {
                beginCurrentMode()
            }
        case .stop:
            stopVision(announce: true, message: "Vision et voix arrêtées.")
        case .pause:
            pauseVision()
        case .resume:
            resumeVision()
        case .repeatLast:
            repeatLastResult()
        case .moreDetail:
            presentMoreDetail()
        case .lessDetail:
            preferencesStore.update {
                $0.narrationVerbosity = .concise
                if request.mode == .liveGuide { $0.importantChangesOnly = true }
            }
            showResult(
                request.mode == .liveGuide ? "Le guide en direct n'annoncera que les changements importants." : "Les descriptions sont maintenant concises.",
                announce: true
            )
        case .whatChanged:
            repeatLastResult(prefix: "Dernier changement confirmé. ")
        case .nextReadingLine:
            pipeline.advanceReadingLine(by: 1)
            speakCurrentReadingLine()
        case .previousReadingLine:
            pipeline.advanceReadingLine(by: -1)
            speakCurrentReadingLine()
        case .flashlightOn:
            setFlashlight(true)
        case .flashlightOff:
            setFlashlight(false)
        case .flashlightStatus:
            let enabled = camera.isTorchEnabled
            lightButton.setTitle(enabled ? "Lampe allumée" : "Lampe éteinte", for: .normal)
            lightButton.accessibilityValue = enabled ? "Allumée" : "Éteinte"
            showResult(enabled ? "La lampe de Vision est allumée." : "La lampe de Vision est éteinte.", announce: true)
        case .checkQuality:
            setMode(.describe, announce: true)
            beginCurrentMode()
        }
    }

    private func buildInterface() {
        configureNavigation()
        configureFixtureBanner()
        configureModePicker()
        configureStatus()
        configurePreview()
        configureResultPanel()
        configureFailurePanel()
        configureActions()
        configureBottomBar()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.accessibilityIdentifier = "jarvis.vision.scroll"

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.axis = .vertical
        contentStack.spacing = 14

        [
            fixtureBanner,
            makeSectionLabel("Mode"),
            modeScrollView,
            makeStatusPanel(),
            guidanceLabel,
            previewView,
            failurePanel,
            resultPanel,
            primaryButton,
            makeSecondaryActionRow(),
            readingControls,
        ].forEach(contentStack.addArrangedSubview)

        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)
        view.addSubview(bottomBar)

        NSLayoutConstraint.activate([
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomBar.topAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 14),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
        ])

        view.accessibilityElements = [scrollView, bottomBar]
    }

    private func configureNavigation() {
        let help = UIBarButtonItem(
            title: "Aide",
            style: .plain,
            target: self,
            action: #selector(helpTapped)
        )
        help.accessibilityLabel = "Aide Vision"
        help.accessibilityHint = "Ouvre l'aide par tâche et les limites de sécurité."
        help.accessibilityIdentifier = "jarvis.vision.help"

        let settings = UIBarButtonItem(
            title: "Réglages",
            style: .plain,
            target: self,
            action: #selector(settingsTapped)
        )
        settings.accessibilityLabel = "Réglages Vision"
        settings.accessibilityHint = "Ouvre les réglages de voix, vibrations, caméra et confidentialité."
        settings.accessibilityIdentifier = "jarvis.vision.settings"
        navigationItem.rightBarButtonItems = [settings, help]
    }

    private func configureFixtureBanner() {
        fixtureBanner.text = "DÉMONSTRATION • La caméra n'est pas active"
        fixtureBanner.textColor = JarvisTheme.background
        fixtureBanner.backgroundColor = JarvisTheme.warning
        fixtureBanner.font = UIFont.preferredFont(forTextStyle: .caption1)
        fixtureBanner.adjustsFontForContentSizeCategory = true
        fixtureBanner.textAlignment = .center
        fixtureBanner.numberOfLines = 0
        fixtureBanner.layer.cornerRadius = 8
        fixtureBanner.clipsToBounds = true
        fixtureBanner.isHidden = true
        fixtureBanner.accessibilityIdentifier = "jarvis.vision.fixtureBanner"
        fixtureBanner.accessibilityLabel = "Démonstration. La caméra n'est pas active."
        fixtureBanner.heightAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
    }

    private func configureModePicker() {
        modeScrollView.translatesAutoresizingMaskIntoConstraints = false
        modeScrollView.showsHorizontalScrollIndicator = false
        modeScrollView.accessibilityIdentifier = "jarvis.vision.modePicker"
        modeScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true

        modeStack.translatesAutoresizingMaskIntoConstraints = false
        modeStack.axis = .horizontal
        modeStack.spacing = 8
        modeScrollView.addSubview(modeStack)
        NSLayoutConstraint.activate([
            modeStack.topAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.topAnchor),
            modeStack.bottomAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.bottomAnchor),
            modeStack.leadingAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.leadingAnchor),
            modeStack.trailingAnchor.constraint(equalTo: modeScrollView.contentLayoutGuide.trailingAnchor),
            modeStack.heightAnchor.constraint(equalTo: modeScrollView.frameLayoutGuide.heightAnchor),
        ])

        let visibleModes: [VisionMode] = [.describe, .liveGuide, .find, .readText, .scanBarcode]
        for mode in visibleModes {
            let button = UIButton(type: .system)
            button.setTitle(mode.visionDisplayName, for: .normal)
            button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.setTitleColor(JarvisTheme.text, for: .normal)
            button.backgroundColor = JarvisTheme.panelRaised
            button.layer.borderColor = JarvisTheme.panelBorder.cgColor
            button.layer.borderWidth = 1
            button.layer.cornerRadius = 12
            button.contentEdgeInsets = UIEdgeInsets(top: 11, left: 15, bottom: 11, right: 15)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.accessibilityLabel = "Mode \(mode.visionDisplayName)"
            button.accessibilityHint = mode.visionReadyGuidance
            button.accessibilityIdentifier = "jarvis.vision.mode.\(mode.rawValue)"
            button.addAction(UIAction { [weak self] _ in self?.modeSelected(mode) }, for: .touchUpInside)
            modeStack.addArrangedSubview(button)
            modeButtons[mode] = button
        }
    }

    private func configureStatus() {
        modeLabel.textColor = JarvisTheme.accentHot
        modeLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        modeLabel.adjustsFontForContentSizeCategory = true
        modeLabel.numberOfLines = 0
        modeLabel.accessibilityIdentifier = "jarvis.vision.currentMode"

        stateLabel.textColor = JarvisTheme.text
        stateLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        stateLabel.adjustsFontForContentSizeCategory = true
        stateLabel.numberOfLines = 0
        stateLabel.accessibilityIdentifier = "jarvis.vision.state"

        guidanceLabel.textColor = JarvisTheme.mutedText
        guidanceLabel.font = UIFont.preferredFont(forTextStyle: .body)
        guidanceLabel.adjustsFontForContentSizeCategory = true
        guidanceLabel.numberOfLines = 0
        guidanceLabel.accessibilityIdentifier = "jarvis.inspection.status"
    }

    private func makeStatusPanel() -> UIView {
        let panel = JarvisPanelView()
        let stack = UIStackView(arrangedSubviews: [modeLabel, stateLabel])
        stack.axis = .vertical
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
        ])
        panel.accessibilityElements = [modeLabel, stateLabel]
        return panel
    }

    private func configurePreview() {
        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.backgroundColor = UIColor(white: 0.04, alpha: 1)
        previewView.layer.borderColor = JarvisTheme.panelBorder.cgColor
        previewView.layer.borderWidth = 1
        previewView.layer.cornerRadius = 14
        previewView.clipsToBounds = true
        previewView.heightAnchor.constraint(equalToConstant: 164).isActive = true
        previewView.isAccessibilityElement = true
        previewView.accessibilityLabel = "Aperçu de la caméra"
        previewView.accessibilityHint = "Le résultat parlé contient l'information utile de la caméra."
        previewView.accessibilityIdentifier = "jarvis.vision.preview"

        let previewMessage = UILabel()
        previewMessage.text = "La caméra ne démarre que lorsque vous choisissez une action."
        previewMessage.textColor = JarvisTheme.mutedText
        previewMessage.font = UIFont.preferredFont(forTextStyle: .footnote)
        previewMessage.adjustsFontForContentSizeCategory = true
        previewMessage.numberOfLines = 0
        previewMessage.textAlignment = .center
        previewMessage.translatesAutoresizingMaskIntoConstraints = false
        previewView.addSubview(previewMessage)
        NSLayoutConstraint.activate([
            previewMessage.centerYAnchor.constraint(equalTo: previewView.centerYAnchor),
            previewMessage.leadingAnchor.constraint(equalTo: previewView.leadingAnchor, constant: 24),
            previewMessage.trailingAnchor.constraint(equalTo: previewView.trailingAnchor, constant: -24),
        ])
    }

    private func configureResultPanel() {
        let title = makeSectionLabel("Résultat")
        title.accessibilityIdentifier = "jarvis.vision.resultHeading"
        resultLabel.text = "Pas encore de résultat."
        resultLabel.textColor = JarvisTheme.text
        resultLabel.font = UIFont.preferredFont(forTextStyle: .body)
        resultLabel.adjustsFontForContentSizeCategory = true
        resultLabel.numberOfLines = 0
        resultLabel.accessibilityIdentifier = "jarvis.vision.result"

        let stack = UIStackView(arrangedSubviews: [title, resultLabel])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        resultPanel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: resultPanel.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: resultPanel.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: resultPanel.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: resultPanel.bottomAnchor, constant: -14),
        ])
        resultPanel.accessibilityElements = [title, resultLabel]
    }

    private func configureFailurePanel() {
        failureLabel.textColor = JarvisTheme.text
        failureLabel.font = UIFont.preferredFont(forTextStyle: .body)
        failureLabel.adjustsFontForContentSizeCategory = true
        failureLabel.numberOfLines = 0
        failureLabel.accessibilityIdentifier = "jarvis.vision.failure"

        openSystemSettingsButton.addTarget(self, action: #selector(openSystemSettingsTapped), for: .touchUpInside)
        openSystemSettingsButton.accessibilityHint = "Ouvre la page Jarvis des Réglages iOS pour modifier l'accès à la caméra."
        openSystemSettingsButton.accessibilityIdentifier = "jarvis.vision.openSystemSettings"
        retryButton.addTarget(self, action: #selector(retryTapped), for: .touchUpInside)
        retryButton.accessibilityIdentifier = "jarvis.vision.retry"
        [openSystemSettingsButton, retryButton].forEach(configureDynamicButton)

        let buttons = UIStackView(arrangedSubviews: [openSystemSettingsButton, retryButton])
        buttons.axis = .horizontal
        buttons.spacing = 8
        buttons.distribution = .fillEqually
        let stack = UIStackView(arrangedSubviews: [makeSectionLabel("À vérifier"), failureLabel, buttons])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        failurePanel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: failurePanel.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: failurePanel.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: failurePanel.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: failurePanel.bottomAnchor, constant: -14),
        ])
        failurePanel.layer.borderColor = JarvisTheme.warning.cgColor
        failurePanel.isHidden = true
        failurePanel.accessibilityIdentifier = "jarvis.vision.failurePanel"
    }

    private func configureActions() {
        primaryButton.setTitleColor(JarvisTheme.background, for: .normal)
        primaryButton.backgroundColor = JarvisTheme.accentHot
        primaryButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title3)
        primaryButton.titleLabel?.adjustsFontForContentSizeCategory = true
        primaryButton.titleLabel?.numberOfLines = 0
        primaryButton.titleLabel?.textAlignment = .center
        primaryButton.layer.cornerRadius = 16
        primaryButton.contentEdgeInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        primaryButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        primaryButton.addTarget(self, action: #selector(primaryTapped), for: .touchUpInside)
        primaryButton.accessibilityIdentifier = "jarvis.vision.primaryAction"

        repeatButton.addTarget(self, action: #selector(repeatTapped), for: .touchUpInside)
        repeatButton.accessibilityLabel = "Répéter le dernier résultat Vision"
        repeatButton.accessibilityHint = "Relit le dernier résultat sans reprendre de photo."
        repeatButton.accessibilityIdentifier = "jarvis.vision.repeat"
        lightButton.addTarget(self, action: #selector(lightTapped), for: .touchUpInside)
        lightButton.accessibilityLabel = "Lampe"
        lightButton.accessibilityIdentifier = "jarvis.vision.flashlight"
        moreDetailButton.addTarget(self, action: #selector(moreDetailTapped), for: .touchUpInside)
        moreDetailButton.accessibilityLabel = "Plus de détails"
        moreDetailButton.accessibilityHint = "Décrit la dernière scène plus en détail sans reprendre de photo."
        moreDetailButton.accessibilityIdentifier = "jarvis.vision.moreDetail"
        [repeatButton, lightButton, moreDetailButton, previousLineButton, pauseReadingButton, nextLineButton]
            .forEach(configureDynamicButton)

        readingControls.axis = .horizontal
        readingControls.spacing = 8
        readingControls.distribution = .fillEqually
        readingControls.addArrangedSubview(previousLineButton)
        readingControls.addArrangedSubview(pauseReadingButton)
        readingControls.addArrangedSubview(nextLineButton)
        readingControls.isHidden = true
        previousLineButton.addTarget(self, action: #selector(previousLineTapped), for: .touchUpInside)
        pauseReadingButton.addTarget(self, action: #selector(pauseReadingTapped), for: .touchUpInside)
        nextLineButton.addTarget(self, action: #selector(nextLineTapped), for: .touchUpInside)
        previousLineButton.accessibilityIdentifier = "jarvis.vision.read.previous"
        pauseReadingButton.accessibilityIdentifier = "jarvis.vision.read.pause"
        nextLineButton.accessibilityIdentifier = "jarvis.vision.read.next"
    }

    private func makeSecondaryActionRow() -> UIView {
        let stack = UIStackView(arrangedSubviews: [repeatButton, moreDetailButton, lightButton])
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        return stack
    }

    private func configureBottomBar() {
        bottomBar.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.accessibilityIdentifier = "jarvis.vision.persistentActions"

        voiceButton.setTitle("Voix", for: .normal)
        voiceButton.setTitleColor(JarvisTheme.text, for: .normal)
        voiceButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        voiceButton.titleLabel?.adjustsFontForContentSizeCategory = true
        voiceButton.backgroundColor = JarvisTheme.panelRaised
        voiceButton.layer.cornerRadius = 14
        voiceButton.layer.borderColor = JarvisTheme.panelBorder.cgColor
        voiceButton.layer.borderWidth = 1
        voiceButton.addTarget(self, action: #selector(voiceTapped), for: .touchUpInside)
        voiceButton.accessibilityLabel = "Commande vocale dans Vision"
        voiceButton.accessibilityHint = "Lance ou arrête l'écoute d'une commande Vision."
        voiceButton.accessibilityIdentifier = "jarvis.vision.voice"

        stopButton.setTitle("Stop", for: .normal)
        stopButton.setTitleColor(.white, for: .normal)
        stopButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        stopButton.titleLabel?.adjustsFontForContentSizeCategory = true
        stopButton.backgroundColor = JarvisTheme.error
        stopButton.layer.cornerRadius = 14
        stopButton.addTarget(self, action: #selector(stopTapped), for: .touchUpInside)
        stopButton.accessibilityLabel = "Arrêter Vision et la voix"
        stopButton.accessibilityHint = "Arrête aussitôt l'analyse de la caméra, les annonces, les vibrations et l'écoute."
        stopButton.accessibilityIdentifier = "jarvis.vision.stop"

        let row = UIStackView(arrangedSubviews: [voiceButton, stopButton])
        row.axis = .horizontal
        row.spacing = 12
        row.distribution = .fillEqually
        row.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.contentView.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: bottomBar.contentView.topAnchor, constant: 10),
            row.leadingAnchor.constraint(equalTo: bottomBar.contentView.leadingAnchor, constant: 16),
            row.trailingAnchor.constraint(equalTo: bottomBar.contentView.trailingAnchor, constant: -16),
            row.bottomAnchor.constraint(equalTo: bottomBar.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            voiceButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
            stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 54),
        ])
        bottomBar.accessibilityElements = [voiceButton, stopButton]
    }

    private func makeSectionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = JarvisTheme.mutedText
        label.font = UIFont.preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.accessibilityTraits.insert(.header)
        return label
    }

    private func configureDynamicButton(_ button: UIButton) {
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.titleLabel?.textAlignment = .center
    }

    private func wireServices() {
        pipeline.bind(to: camera)
        pipeline.apply(preferences: preferences)
        let motionMonitor = self.motionMonitor
        pipeline.cameraPoseProvider = { motionMonitor.sample() }

        pipeline.onStateChange = { [weak self] mode, state in
            DispatchQueue.main.async { self?.pipelineStateChanged(mode: mode, state: state) }
        }
        pipeline.onSnapshot = { [weak self] snapshot in
            DispatchQueue.main.async { self?.received(snapshot: snapshot) }
        }
        pipeline.onNarration = { [weak self] narration in
            DispatchQueue.main.async { self?.received(narration: narration) }
        }
        pipeline.onError = { [weak self] error in
            DispatchQueue.main.async { self?.handle(error: error) }
        }
        pipeline.onReadingStateChange = { [weak self] readingState in
            DispatchQueue.main.async { self?.readingStateChanged(readingState) }
        }
        pipeline.onColorResult = { [weak self] result in
            DispatchQueue.main.async {
                self?.guidanceLabel.text = result.isUncertain
                    ? "La couleur du centre varie dans la zone mesurée."
                    : "Couleur du centre identifiée sur l'image actuelle."
            }
        }

        voiceInput.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .standby:
                self.voiceButton.setTitle("Voix", for: .normal)
                self.resumeNarrationAfterListening()
            case .listening:
                self.voiceButton.setTitle("Terminer", for: .normal)
                self.pauseNarrationForListening()
                self.renderState(self.currentState, guidance: "Micro actif : dites une commande Vision.", announce: true)
            case .hearingSound:
                if self.voiceInput.currentTranscript.isEmpty {
                    self.guidanceLabel.text = "Son reçu…"
                }
            case .heardYou(let transcript):
                self.guidanceLabel.text = "Compris : « \(transcript) »"
            case .processing:
                self.guidanceLabel.text = "Traitement de la commande vocale."
            case .noSpeech:
                self.resumeNarrationAfterListening()
                self.renderState(self.currentState, guidance: "Aucune parole détectée. Réessayez ou utilisez un bouton.", announce: true)
            case .unavailable(let failure):
                self.resumeNarrationAfterListening()
                self.showFailure(failure.message, offersSettings: failure.offersSettings)
            }
        }
        voiceInput.onPartialTranscript = { [weak self] text in
            guard !text.isEmpty else { return }
            self?.guidanceLabel.text = "J'écoute : \(text)"
        }
        voiceInput.onInputLevel = nil
        voiceInput.onFinalTranscript = { [weak self] text in
            self?.handleVisionVoiceCommand(text)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(preferencesChanged),
            name: .jarvisVisionPreferencesDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(runtimeConditionsChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(runtimeConditionsChanged),
            name: .NSProcessInfoPowerStateDidChange,
            object: nil
        )
    }

    private func modeSelected(_ mode: VisionMode) {
        if currentState == .active || currentState == .paused || currentState == .preparing {
            stopVision(announce: false, message: "Mode Vision précédent arrêté.")
        }
        currentTarget = mode == .find ? currentTarget : nil
        requestedRegion = nil
        latestSnapshot = nil
        lastPresentedNarration = nil
        resultLabel.text = "Pas encore de résultat."
        setMode(mode, announce: true)
        if mode == .find {
            promptForFindTarget()
        }
    }

    private func setMode(_ mode: VisionMode, announce: Bool) {
        currentMode = mode == .inactive ? .describe : mode
        modeLabel.text = "Mode \(currentMode.visionDisplayName)"
        for (buttonMode, button) in modeButtons {
            let selected = buttonMode == currentMode
            button.backgroundColor = selected ? JarvisTheme.accentDim : JarvisTheme.panelRaised
            button.layer.borderColor = (selected ? JarvisTheme.accentHot : JarvisTheme.panelBorder).cgColor
            if selected {
                button.accessibilityTraits.insert(.selected)
            } else {
                button.accessibilityTraits.remove(.selected)
            }
        }
        readingControls.isHidden = currentMode != .readText
        moreDetailButton.isHidden = currentMode == .readText || currentMode == .scanBarcode
        primaryButton.setTitle(primaryTitle(), for: .normal)
        renderState(.idle, guidance: currentMode.visionReadyGuidance, announce: false)
        if announce {
            postAnnouncement("Mode \(currentMode.visionDisplayName). \(currentMode.visionReadyGuidance)", force: true)
            playHaptic(.success)
        }
    }

    private func beginCurrentMode() {
        guard !isFixtureDriven else { return }
        if currentMode == .find, currentTarget?.isEmpty != false {
            promptForFindTarget()
            return
        }
        latestSnapshot = nil
        lastPresentedNarration = nil
        resultLabel.text = "En attente d'un résultat confirmé."
        failurePanel.isHidden = true
        resetFeedbackSessions()
        renderState(.preparing, guidance: "Préparation de la caméra.", announce: true)
        ensureFeedbackSessions()
        let position: CameraSessionService.CameraPosition = preferences.cameraChoice == .front ? .front : .rear
        camera.requestAccessAndStart(position: position) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.handleCameraStartFailure(error)
            case .success:
                self.attachPreviewIfNeeded()
                VisionDiagnosticsStore.shared.setPermissions(camera: .authorized)
                VisionDiagnosticsStore.shared.setActiveCamera(
                    self.preferences.cameraChoice == .front ? .front : .rear
                )
                self.pipeline.updateRuntimeConditions(
                    thermalState: ProcessInfo.processInfo.thermalState,
                    lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
                )
                self.pipeline.apply(preferences: self.preferences)
                self.speech.setQuietVisionGuideEnabled(self.preferences.importantChangesOnly)
                if self.currentMode == .liveGuide {
                    self.motionMonitor.start()
                } else {
                    self.motionMonitor.stop()
                }
                self.pipeline.start(mode: self.currentMode, target: self.currentTarget)
                self.updateScreenAwake()
                switch self.currentMode {
                case .describe, .readText, .identifyColor:
                    self.captureStillForCurrentMode()
                case .liveGuide, .find, .scanBarcode:
                    self.renderState(.active, guidance: self.activeGuidance(), announce: true)
                case .inactive:
                    break
                }
            }
        }
    }

    private func captureStillForCurrentMode() {
        renderState(.active, guidance: currentMode == .readText ? "Capture du texte. Restez immobile." : "Capture et analyse en cours.", announce: true)
        camera.captureHighResolutionPhoto { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.showFailure(error.localizedDescription, offersSettings: false)
            case .success(let captured):
                guard let cgImage = captured.image.cgImage else {
                    self.handle(error: .cameraUnavailable)
                    return
                }
                self.pipeline.analyzeStillImage(
                    cgImage,
                    orientation: captured.orientation,
                    mode: self.currentMode,
                    target: self.currentTarget
                )
            }
        }
    }

    private func pauseVision() {
        guard currentState == .active else {
            showResult("Vision n'est pas active pour le moment.", announce: true)
            return
        }
        pipeline.pause()
        motionMonitor.stop()
        speech.pauseVisionNarration()
        renderState(.paused, guidance: "Vision en pause. La caméra n'est plus analysée.", announce: true)
        updateScreenAwake()
    }

    private func resumeVision() {
        guard currentState == .paused else {
            beginCurrentMode()
            return
        }
        if currentMode == .liveGuide {
            motionMonitor.start()
        }
        pipeline.resume()
        speech.resumeVisionNarration()
        renderState(.active, guidance: activeGuidance(), announce: true)
        updateScreenAwake()
    }

    private func stopVision(announce: Bool, message: String) {
        voiceInput.cancel()
        narrationPausedForListening = false
        pipeline.stop()
        camera.stop()
        motionMonitor.stop()
        if let speechSessionID {
            speech.cancelVisionNarrationSession(speechSessionID)
            self.speechSessionID = nil
        } else {
            speech.stop()
        }
        if let hapticSessionID {
            haptics.endSession(hapticSessionID)
            self.hapticSessionID = nil
        }
        latestSnapshot = nil
        lastPresentedNarration = nil
        resultLabel.text = "Vision arrêtée. Le résultat de la session est effacé."
        VisionDiagnosticsStore.shared.setActiveCamera(nil)
        UIApplication.shared.isIdleTimerDisabled = false
        currentState = .stopped
        stateLabel.text = "Arrêté"
        guidanceLabel.text = message
        primaryButton.setTitle(primaryTitle(), for: .normal)
        pauseReadingButton.setTitle("Pause lecture", for: .normal)
        if announce {
            postAnnouncement(message, force: true)
        }
    }

    private func pipelineStateChanged(mode: VisionMode, state: VisionSessionState) {
        guard mode == currentMode || mode == .inactive else { return }
        renderState(state, guidance: guidance(for: state), announce: state == .failed || state == .unavailable)
        if state == .stopped && (currentMode == .describe || currentMode == .readText || currentMode == .identifyColor) {
            camera.stop()
            VisionDiagnosticsStore.shared.setActiveCamera(nil)
        }
        updateScreenAwake()
    }

    private func received(snapshot: SceneSnapshot) {
        guard snapshot.mode == currentMode else { return }
        latestSnapshot = snapshot
        if let guidance = snapshot.quality.guidance.first, !snapshot.quality.isUsable {
            guidanceLabel.text = guidance
            playHaptic(.warning)
        }

        if let region = requestedRegion, currentMode == .describe {
            let narration = VisionNarrationService().narrate(
                snapshot: snapshot,
                verbosity: preferences.narrationVerbosity,
                region: region
            )
            ignoredAutomaticNarrationSnapshotID = snapshot.id
            received(narration: narration)
        }

        if currentMode == .find {
            updateFindHaptics(from: snapshot)
        }
    }

    private func received(narration: SceneNarration) {
        guard narration.snapshotIdentifier != ignoredAutomaticNarrationSnapshotID else {
            ignoredAutomaticNarrationSnapshotID = nil
            return
        }
        lastPresentedNarration = narration
        showResult(narration.text, announce: !speech.isEnabled)
        ensureFeedbackSessions()
        if let speechSessionID {
            speech.enqueueVisionNarration(narration, sessionID: speechSessionID)
        }
        switch narration.priority {
        case .warning:
            playHaptic(.warning)
        case .target:
            playHaptic(.targetAcquired)
        default:
            if narration.contentKind == .reading || narration.contentKind == .barcode {
                playHaptic(.success)
            }
        }
    }

    private func readingStateChanged(_ state: VisionReadingState) {
        readingControls.isHidden = currentMode != .readText
        let isPaused = state.status == .paused
        pauseReadingButton.setTitle(isPaused ? "Reprendre la lecture" : "Pause lecture", for: .normal)
        pauseReadingButton.accessibilityLabel = isPaused ? "Reprendre la lecture" : "Mettre la lecture en pause"
    }

    private func handle(error: VisionError) {
        VisionDiagnosticsStore.shared.record(error: error)
        let message: String
        let offersSettings: Bool
        switch error {
        case .cameraPermissionDenied:
            message = "L'accès à la caméra est coupé. Activez Caméra dans les Réglages iOS, puis revenez et réessayez."
            offersSettings = true
        case .cameraUnavailable, .cameraInterrupted:
            message = "La caméra est indisponible pour le moment. Fermez les autres usages de la caméra et réessayez."
            offersSettings = false
        case .modelMissing, .modelChecksumMismatch, .modelLoadFailed(_), .invalidModelOutput:
            message = "Le modèle d'objets de l'iPhone est indisponible ou n'a pas passé la vérification. Lire et Code-barres peuvent encore fonctionner."
            offersSettings = false
        case .unsupportedTarget(let target):
            message = "Jarvis ne peut pas trouver cet objet de façon fiable avec le modèle installé. \(target)"
            offersSettings = false
        case .targetNotFound(let target):
            message = "Je n'ai pas trouvé \(VisionFrenchVocabulary.noun(for: target).definite). Balayez lentement, ou arrêtez et réessayez d'un autre endroit."
            offersSettings = false
        case .noTextFound:
            message = "Aucun texte lisible confirmé. Approchez-vous, tenez le téléphone plus immobile et réessayez."
            offersSettings = false
        case .flashlightUnavailable:
            message = "La lampe n'est pas disponible sur cette caméra."
            offersSettings = false
        case .thermalDegraded:
            message = "Vision analyse moins souvent car l'iPhone chauffe."
            offersSettings = false
        case .textRecognitionFailed:
            message = "La lecture du texte n'a pas abouti. Tenez le téléphone immobile et réessayez."
            offersSettings = false
        case .speechUnavailable:
            message = "La voix est indisponible. Les résultats restent affichés à l'écran."
            offersSettings = true
        case .hapticsUnavailable:
            message = "Les vibrations sont indisponibles. Le guidage passera par la voix."
            offersSettings = false
        case .insufficientMemory:
            message = "Vision s'est arrêtée faute de mémoire. Fermez d'autres apps et réessayez."
            offersSettings = false
        case .cancelled:
            return
        }
        showFailure(message, offersSettings: offersSettings)
        switch error {
        case .cameraInterrupted, .thermalDegraded, .flashlightUnavailable, .speechUnavailable, .hapticsUnavailable:
            break
        default:
            camera.stop()
            VisionDiagnosticsStore.shared.setActiveCamera(nil)
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func handleCameraStartFailure(_ error: Error) {
        let authorization = CameraSessionService.authorizationStatus
        let diagnosticState: VisionAuthorizationState = authorization == .denied
            ? .denied
            : (authorization == .restricted ? .restricted : .unavailable)
        VisionDiagnosticsStore.shared.setPermissions(camera: diagnosticState)
        let message = authorization == .restricted
            ? "L'accès à la caméra est restreint sur cet iPhone. Un administrateur ou le contrôle parental doit peut-être le modifier."
            : error.localizedDescription
        showFailure(message, offersSettings: authorization == .denied)
    }

    private func renderState(_ state: VisionSessionState, guidance: String, announce: Bool) {
        currentState = state
        stateLabel.text = stateDisplayName(state)
        guidanceLabel.text = guidance
        primaryButton.setTitle(primaryTitle(), for: .normal)
        if announce {
            postAnnouncement("\(modeLabel.text ?? "Vision"). \(stateLabel.text ?? ""). \(guidance)")
        }
    }

    private func stateDisplayName(_ state: VisionSessionState) -> String {
        switch state {
        case .idle: return "Prêt"
        case .preparing: return "Préparation"
        case .active:
            if currentMode == .find, let currentTarget { return "Recherche : \(VisionFrenchVocabulary.noun(for: currentTarget).singular)" }
            if currentMode == .readText { return "Lecture"
            }
            return "Actif"
        case .paused: return "En pause"
        case .stopping: return "Arrêt en cours"
        case .stopped: return "Arrêté"
        case .unavailable: return "Indisponible"
        case .failed: return "À vérifier"
        }
    }

    private func guidance(for state: VisionSessionState) -> String {
        switch state {
        case .idle: return currentMode.visionReadyGuidance
        case .preparing: return "Préparation de Vision sur l'iPhone."
        case .active: return activeGuidance()
        case .paused: return "Vision est en pause."
        case .stopping: return "Arrêt de l'analyse et des annonces."
        case .stopped: return "Vision est arrêtée."
        case .unavailable: return "Vision est indisponible. Voyez la solution proposée ci-dessous."
        case .failed: return "Vision n'a pas pu terminer. Voyez la solution proposée ci-dessous."
        }
    }

    private func activeGuidance() -> String {
        switch currentMode {
        case .liveGuide: return "Guide en direct actif : j'annonce une fois ce qui apparaît, bouge ou disparaît. Demandez « Elle est où ? » avec Voix. Stop reste en bas."
        case .find: return "Je cherche \(currentTarget.map { VisionFrenchVocabulary.noun(for: $0).definite } ?? "l'objet choisi"). Balayez lentement."
        case .scanBarcode: return "Recherche d'un code-barres. Jarvis n'ouvre jamais de lien tout seul."
        case .readText: return "Lecture du texte capturé, sur l'iPhone."
        case .identifyColor: return "Identification de la couleur du centre."
        case .describe, .inactive: return "Analyse de la scène capturée, sur l'iPhone."
        }
    }

    private func primaryTitle() -> String {
        if currentState == .paused { return "Reprendre : \(currentMode.visionDisplayName)" }
        if currentState == .active {
            switch currentMode {
            case .liveGuide: return "Mettre le guide en pause"
            case .find: return "Changer l'objet à trouver"
            case .scanBarcode: return "Mettre le scan en pause"
            default: break
            }
        }
        if currentMode == .find, let currentTarget {
            return "Trouver \(VisionFrenchVocabulary.noun(for: currentTarget).definite)"
        }
        return currentMode.visionPrimaryActionTitle
    }

    private func showResult(_ text: String, announce: Bool) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        resultLabel.text = clean
        failurePanel.isHidden = true
        if announce {
            postAnnouncement(clean)
        }
    }

    private func showFailure(_ message: String, offersSettings: Bool) {
        currentState = .unavailable
        stateLabel.text = "À vérifier"
        guidanceLabel.text = message
        failureLabel.text = message
        failurePanel.isHidden = false
        openSystemSettingsButton.isHidden = !offersSettings
        retryButton.isHidden = false
        playHaptic(.warning)
        postAnnouncement("Vision : à vérifier. \(message)", force: true)
    }

    private func repeatLastResult(prefix: String = "") {
        guard let narration = lastPresentedNarration ?? pipeline.repeatLastNarration() else {
            if resultLabel.text != "Pas encore de résultat." {
                postAnnouncement("\(prefix)\(resultLabel.text ?? "")", force: true)
            } else {
                showResult("Il n'y a pas encore de résultat Vision à répéter.", announce: true)
            }
            return
        }
        let text = prefix + narration.text
        showResult(text, announce: !speech.isEnabled)
        ensureFeedbackSessions()
        if let speechSessionID {
            let repeated = SceneNarration(
                snapshotIdentifier: narration.snapshotIdentifier,
                text: text,
                priority: narration.priority,
                verbosity: narration.verbosity,
                contentKind: narration.contentKind,
                groundedObservationIdentifiers: narration.groundedObservationIdentifiers,
                isVerbatim: narration.isVerbatim
            )
            speech.enqueueVisionNarration(repeated, sessionID: speechSessionID)
        }
    }

    private func presentMoreDetail() {
        let narration: SceneNarration?
        if let latestSnapshot, let requestedRegion {
            narration = VisionNarrationService().narrate(
                snapshot: latestSnapshot,
                verbosity: .detailed,
                region: requestedRegion
            )
        } else {
            narration = pipeline.narration(moreDetailed: true)
        }
        guard let narration else {
            showResult("Capturez une scène avant de demander plus de détails.", announce: true)
            return
        }
        received(narration: narration)
    }

    private func speakCurrentReadingLine() {
        guard let line = pipeline.currentReadingLine() else {
            showResult("Il n'y a pas d'autre ligne à lire.", announce: true)
            return
        }
        showResult(line.text, announce: false)
        let narration = SceneNarration(
            snapshotIdentifier: UUID(),
            text: line.text,
            priority: .prominent,
            verbosity: .standard,
            contentKind: .reading,
            groundedObservationIdentifiers: [line.id],
            isVerbatim: true
        )
        ensureFeedbackSessions()
        if let speechSessionID {
            speech.enqueueVisionNarration(narration, sessionID: speechSessionID)
        }
    }

    private func updateFindHaptics(from snapshot: SceneSnapshot) {
        guard let target = currentTarget?.lowercased() else { return }
        let match = snapshot.objects.first {
            $0.isConfirmed && (
                $0.name.lowercased() == target ||
                $0.classIdentifier.lowercased() == target ||
                $0.name.lowercased().contains(target)
            )
        }
        guard let match else {
            if lastTargetCentered { playHaptic(.targetLost) }
            lastTargetCentered = false
            return
        }
        switch match.horizontalRegion {
        case .left: playHaptic(.directionLeft)
        case .right: playHaptic(.directionRight)
        case .center:
            playHaptic(lastTargetCentered ? .directionCenter : .targetAcquired)
            lastTargetCentered = true
        }
    }

    private func ensureFeedbackSessions() {
        if speechSessionID == nil {
            speechSessionID = speech.beginVisionNarrationSession()
        }
        if hapticSessionID == nil, preferences.hapticsEnabled {
            hapticSessionID = haptics.beginSession()
        }
    }

    private func resetFeedbackSessions() {
        if let speechSessionID {
            speech.cancelVisionNarrationSession(speechSessionID)
            self.speechSessionID = nil
        }
        if let hapticSessionID {
            haptics.endSession(hapticSessionID)
            self.hapticSessionID = nil
        }
    }

    private func playHaptic(_ cue: VisionHapticCue) {
        guard preferences.hapticsEnabled else { return }
        ensureFeedbackSessions()
        guard let hapticSessionID else { return }
        haptics.play(cue, intensity: preferences.hapticIntensity, sessionID: hapticSessionID)
    }

    private func updateScreenAwake() {
        UIApplication.shared.isIdleTimerDisabled = currentMode == .liveGuide && currentState == .active && preferences.keepScreenAwakeDuringLiveGuide
    }

    private func setFlashlight(_ enabled: Bool) {
        guard camera.state == .running else {
            let position: CameraSessionService.CameraPosition = preferences.cameraChoice == .front ? .front : .rear
            renderState(.preparing, guidance: "Préparation de la caméra pour la lampe.", announce: true)
            camera.requestAccessAndStart(position: position) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    self.attachPreviewIfNeeded()
                    VisionDiagnosticsStore.shared.setPermissions(camera: .authorized)
                    VisionDiagnosticsStore.shared.setActiveCamera(
                        self.preferences.cameraChoice == .front ? .front : .rear
                    )
                    self.renderState(.active, guidance: "Caméra active pour la lampe. Stop l'éteint.", announce: false)
                    self.setFlashlight(enabled)
                case .failure(let error):
                    self.handleCameraStartFailure(error)
                }
            }
            return
        }
        camera.setTorch(enabled: enabled) { [weak self] result in
            switch result {
            case .success(let actual):
                self?.lightButton.setTitle(actual ? "Lampe allumée" : "Lampe éteinte", for: .normal)
                self?.lightButton.accessibilityValue = actual ? "Allumée" : "Éteinte"
                self?.showResult(actual ? "Lampe allumée." : "Lampe éteinte.", announce: true)
            case .failure:
                self?.handle(error: .flashlightUnavailable)
            }
        }
    }

    private func attachPreviewIfNeeded() {
        guard previewLayer == nil else { return }
        let layer = AVCaptureVideoPreviewLayer(session: camera.session)
        layer.videoGravity = .resizeAspectFill
        previewView.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        view.setNeedsLayout()
    }

    private static let frenchStopPhrases: Set<String> = [
        "stop", "arrete", "arrete tout", "annule", "coupe", "coupe tout", "stop vision", "stop jarvis",
        "arrete le guide", "arrete le guide en direct", "coupe le guide", "coupe le guide en direct",
        "arrete d'observer", "arrete de regarder", "arrete la camera", "coupe la camera", "ferme la camera",
        "eteins la camera", "arrete la vision", "coupe la vision"
    ]

    private func handleVisionVoiceCommand(_ spokenText: String) {
        voiceButton.setTitle("Voix", for: .normal)
        resumeNarrationAfterListening()
        let frenchRequest = JarvisFrenchCommandRouter.stripWakeWord(JarvisFrenchCommandRouter.normalize(spokenText))
        if Self.frenchStopPhrases.contains(frenchRequest) {
            apply(JarvisVisionLaunchRequest(mode: currentMode, command: .stop, source: "vision_voice"))
            return
        }
        // Live Guide answers from what it saw: « Elle est où maintenant ? », « Qu'est-ce qui a bougé ? ».
        // Once stopped, « décris » still starts a description instead.
        if currentMode == .liveGuide, let answer = pipeline.liveGuide.answer(to: spokenText),
           pipeline.liveGuide.isObserving || JarvisFrenchCommandRouter.translateAction(spokenText)?.command != "describe this" {
            presentSpokenAnswer(answer)
            return
        }
        // Dictation is French: translate the French wording of a Vision action first.
        let raw = JarvisFrenchCommandRouter.translateAction(spokenText)?.command ?? spokenText
        let normalized = JarvisCommandPlanner().normalize(raw)
        if ["stop", "stop vision", "stop live guide", "stop reading", "stop speaking", "cancel"].contains(normalized) {
            apply(JarvisVisionLaunchRequest(mode: currentMode, command: .stop, source: "vision_voice"))
            return
        }
        if normalized == "help" || normalized == "vision help" {
            helpTapped()
            return
        }
        if normalized == "settings" || normalized == "vision settings" {
            settingsTapped()
            return
        }
        let plan = JarvisCommandPlanner().plan(raw)
        guard let request = plan.visionLaunchRequest else {
            showResult("Commande Vision non reconnue. Essayez : « décris », « guide en direct », « lis ce texte », « code-barres » ou « stop ».", announce: true)
            return
        }
        var sourced = request
        sourced.source = "vision_voice"
        apply(sourced)
    }

    /// Shows and speaks an answer through the Vision speech queue, so Stop silences it too.
    private func presentSpokenAnswer(_ text: String) {
        let narration = SceneNarration(
            snapshotIdentifier: latestSnapshot?.id ?? UUID(),
            text: VisionSafetyPolicy().safeNarration(text),
            priority: .target,
            verbosity: preferences.narrationVerbosity,
            contentKind: .target
        )
        lastPresentedNarration = narration
        showResult(narration.text, announce: !speech.isEnabled)
        ensureFeedbackSessions()
        if let speechSessionID {
            speech.enqueueVisionNarration(narration, sessionID: speechSessionID)
        }
    }

    private func pauseNarrationForListening() {
        guard !narrationPausedForListening, currentState == .active else { return }
        narrationPausedForListening = true
        speech.pauseVisionNarration()
    }

    private func resumeNarrationAfterListening() {
        guard narrationPausedForListening else { return }
        narrationPausedForListening = false
        if currentState == .active {
            speech.resumeVisionNarration()
        }
    }

    private func promptForFindTarget() {
        let alert = UIAlertController(
            title: "Trouver un objet",
            message: "Nommez un objet reconnu par le modèle installé (tasse, chaise, bouteille…). Jarvis vous dira honnêtement s'il ne le reconnaît pas.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Exemple : tasse ou chaise"
            field.accessibilityLabel = "Objet à trouver"
            field.textContentType = .none
        }
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lancer la recherche", style: .default) { [weak self, weak alert] _ in
            guard let self else { return }
            let target = alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !target.isEmpty else {
                self.showResult("Nommez un objet avant de lancer la recherche.", announce: true)
                return
            }
            self.currentTarget = target
            self.primaryButton.setTitle(self.primaryTitle(), for: .normal)
            self.beginCurrentMode()
        })
        present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func postAnnouncement(_ text: String, force: Bool = false) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let now = Date()
        if !force, let lastAnnouncement {
            guard lastAnnouncement.text != text,
                  now.timeIntervalSince(lastAnnouncement.date) >= 1.2 else { return }
        }
        lastAnnouncement = (text, now)
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private func applyFixtureStateIfNeeded() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("-JARVIS_UI_TESTING") || arguments.contains("--jarvis-ui-test") else { return }
        let stateKey = arguments.firstIndex(of: "--jarvis-state") ?? arguments.firstIndex(of: "-JARVIS_VISUAL_STATE")
        let fixture = stateKey.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil } ?? "inspection"
        guard fixture == "inspection" || fixture == "object_model_missing" || fixture.hasPrefix("vision_") else { return }
        isFixtureDriven = true
        fixtureBanner.isHidden = false
        previewView.accessibilityLabel = "Aperçu de démonstration. La caméra n'est pas active."

        switch fixture {
        case "vision_describe_listening":
            setMode(.describe, announce: false)
            stateLabel.text = "À l'écoute"
            guidanceLabel.text = "J'écoute une commande Vision."
        case "vision_describe_analyzing":
            setMode(.describe, announce: false)
            renderState(.active, guidance: "Analyse d'une image de démonstration, sur l'iPhone.", announce: false)
        case "vision_describe_result":
            setMode(.describe, announce: false)
            renderState(.stopped, guidance: "Analyse de démonstration terminée.", announce: false)
            showResult("Je vois peut-être une chaise au centre et une table à gauche.", announce: false)
        case "vision_live_active":
            setMode(.liveGuide, announce: false)
            renderState(.active, guidance: "Démonstration du guide en direct. La caméra n'est pas active.", announce: false)
            showResult("La tasse s'est déplacée du centre vers la droite.", announce: false)
        case "vision_find_searching":
            currentTarget = "chair"
            setMode(.find, announce: false)
            renderState(.active, guidance: "Recherche de démonstration : chaise. Balayez lentement.", announce: false)
        case "vision_find_centered":
            currentTarget = "chair"
            setMode(.find, announce: false)
            renderState(.active, guidance: "Objet centré dans la démonstration.", announce: false)
            showResult("Je détecte une chaise au centre.", announce: false)
        case "vision_reading":
            setMode(.readText, announce: false)
            renderState(.active, guidance: "Lecture d'un texte de démonstration. La caméra n'est pas active.", announce: false)
            showResult("Démonstration Jarvis Vision : traitement sur l'iPhone, aucune image enregistrée.", announce: false)
        case "vision_scan_result":
            setMode(.scanBarcode, announce: false)
            renderState(.active, guidance: "Code-barres de démonstration trouvé. Aucun lien ouvert.", announce: false)
            showResult("Code-barres de démonstration : 012345678905", announce: false)
        case "vision_permission_denied":
            setMode(.describe, announce: false)
            showFailure("L'accès à la caméra est coupé. Activez Caméra dans les Réglages iOS, puis revenez et réessayez.", offersSettings: true)
        case "vision_model_unavailable", "object_model_missing":
            setMode(.describe, announce: false)
            showFailure("Le modèle d'objets de l'iPhone est indisponible ou n'a pas passé la vérification. Lire et Code-barres peuvent encore fonctionner.", offersSettings: false)
            guidanceLabel.text = "Visual scan ready. The on-device object model is unavailable."
        default:
            setMode(.describe, announce: false)
            renderState(.idle, guidance: "Vision est prête. Démonstration seulement : la caméra n'est pas active.", announce: false)
        }
    }

    @objc private func primaryTapped() {
        if isFixtureDriven {
            if currentState == .active {
                renderState(.paused, guidance: "Démonstration en pause. La caméra n'est pas active.", announce: false)
            } else {
                renderState(.active, guidance: "Démonstration active. La caméra n'est pas active.", announce: false)
            }
            return
        }
        if currentState == .paused {
            resumeVision()
        } else if currentState == .active && (currentMode == .liveGuide || currentMode == .scanBarcode) {
            pauseVision()
        } else if currentState == .active && currentMode == .find {
            promptForFindTarget()
        } else {
            beginCurrentMode()
        }
    }

    @objc private func stopTapped() {
        stopVision(announce: true, message: "Vision et voix arrêtées.")
    }

    @objc private func voiceTapped() {
        if voiceInput.isListening {
            voiceInput.stopListening(process: true)
        } else {
            voiceInput.startListening()
        }
    }

    @objc private func repeatTapped() { repeatLastResult() }
    @objc private func moreDetailTapped() { presentMoreDetail() }
    @objc private func lightTapped() { setFlashlight(!camera.isTorchEnabled) }
    @objc private func retryTapped() { beginCurrentMode() }
    @objc private func previousLineTapped() {
        pipeline.advanceReadingLine(by: -1)
        speakCurrentReadingLine()
    }
    @objc private func nextLineTapped() {
        pipeline.advanceReadingLine(by: 1)
        speakCurrentReadingLine()
    }
    @objc private func pauseReadingTapped() {
        let shouldPause = pauseReadingButton.currentTitle != "Reprendre la lecture"
        pipeline.setReadingPaused(shouldPause)
        if shouldPause { speech.pauseVisionNarration() } else { speech.resumeVisionNarration() }
    }

    @objc private func helpTapped() {
        let controller = JarvisHelpViewController(initialSection: .vision)
        navigationController?.pushViewController(controller, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func settingsTapped() {
        navigationController?.pushViewController(JarvisSettingsViewController(initialSection: .vision), animated: !UIAccessibility.isReduceMotionEnabled)
    }

    @objc private func openSystemSettingsTapped() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func applicationEnteredBackground() {
        guard currentState == .active || currentState == .preparing || currentState == .paused else { return }
        stopVision(announce: false, message: "Vision arrêtée : Jarvis est passé en arrière-plan.")
    }

    @objc private func preferencesChanged() {
        pipeline.apply(preferences: preferences)
        speech.setQuietVisionGuideEnabled(preferences.importantChangesOnly)
        updateScreenAwake()
    }

    @objc private func runtimeConditionsChanged() {
        pipeline.updateRuntimeConditions(
            thermalState: ProcessInfo.processInfo.thermalState,
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
        )
    }
}
