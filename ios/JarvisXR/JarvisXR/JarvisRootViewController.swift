import UIKit

final class JarvisRootViewController: UIViewController, UITextFieldDelegate {
    private let assistant = JarvisAssistantCore()
    private let memory = JarvisMemoryStore.shared
    private let speech = JarvisSpeechService.shared
    private let voiceInput = JarvisVoiceInputService.shared
    private lazy var messageComposition = JarvisMessageCompositionService(presenter: self) { [weak self] response in
        self?.render(response: response)
    }

    private let backgroundLayer = CAGradientLayer()
    private let wordmarkLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let orbView = JarvisOrbView()
    private let stateLabel = UILabel()
    private let hintLabel = UILabel()
    private let transientResponseLabel = UILabel()
    /// Discreet four-step indicator: micro actif → son reçu → texte compris → réponse.
    private let voiceStageLabel = UILabel()
    private var voiceStage: JarvisVoiceStage = .idle
    private var voiceStageFailed = false
    private var voiceLevel: Float = 0
    /// True while an exchange started at the microphone continues hands-free: after a
    /// spoken reply, Jarvis listens again without a tap (setting « conversation continue »).
    private var conversationActive = false
    private var currentTurnIsAutomatic = false
    private var rearmWorkItem: DispatchWorkItem?
    /// Réveil par la voix: the next wait for « Jarvis », and whether « Oui ? » was just
    /// said to a bare « Jarvis » (the request is listened to right after).
    private var wakeRestartWorkItem: DispatchWorkItem?
    private var listenAfterWakeReply = false
    /// A few words while an answer takes time (« Voyons voir. »), as in a conversation.
    private var thinkingFiller = JarvisThinkingFiller()
    private var fillerWorkItem: DispatchWorkItem?
    /// The reply being said is a stream (sentences as they come, or the filler first).
    private var brainReplyStreaming = false
    /// Each request and each question to the brain: a late answer to an earlier one is dropped.
    private var brainTurn = 0
    /// The request being handled, and one that waits for the screen (background watch).
    private var lastCommandText = ""
    private var pendingScreenCommand: (text: String, date: Date)?
    private var pendingRanAt: Date?
    /// The user started speaking over Jarvis: the microphone listens, and Jarvis stops once
    /// real words of the user are heard (JarvisEchoFilter), not its own echo or a noise.
    private var bargeInProbe = false
    private var bargeInConfirmed = false
    private var bargeInTimeout: DispatchWorkItem?
    private var didOfferBrainDownload = false
    private var wasDownloadingBrain = false
    private var brainDownloadObserver: NSObjectProtocol?
    private let inputContainer = JarvisPanelView()
    private let commandField = UITextField()
    private let submitButton = UIButton(type: .system)
    private let menuButton = UIButton(type: .system)
    private let helpButton = UIButton(type: .system)

    private var inputBottomConstraint: NSLayoutConstraint?
    private var wordmarkTopConstraint: NSLayoutConstraint?
    private var orbCenterYConstraint: NSLayoutConstraint?
    private var orbWidthMultiplierConstraint: NSLayoutConstraint?
    private var orbMaxWidthConstraint: NSLayoutConstraint?
    private var responseHideWorkItem: DispatchWorkItem?
    private var didCheckFirstLaunch = false
    private var interfaceState: JarvisInteractionState = .standby
    private var longPressSuppressesNextTap = false
    private var didApplyVisualProofState = false
    private var pendingVisionRequestAfterOnboarding: JarvisVisionLaunchRequest?
    private var isUITestMode: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("-JARVIS_UI_TESTING") || arguments.contains("--jarvis-ui-test")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "JARVIS"
        view.backgroundColor = JarvisTheme.background
        navigationController?.setNavigationBarHidden(true, animated: false)
        buildInterface()
        wireVoice()
        NotificationCenter.default.addObserver(self, selector: #selector(deepLinkReceived(_:)), name: .jarvisDeepLinkReceived, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appBecameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appEnteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        observeBrainDownload()
        setInterfaceState(speech.isEnabled ? .standby : .quiet, hint: "JARVIS est prêt.")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        if let pending = JarvisPendingIntentStore.consumeAction() {
            handle(action: pending)
            return
        }
        applyVisualProofStateIfNeeded()
        if !didCheckFirstLaunch {
            didCheckFirstLaunch = true
            showFirstLaunchIfNeeded()
        }
        // Back from Settings or another screen: share notes and hear the PC's messages.
        if !isUITestMode { synchronizeWithPC() }
        scheduleWakeListening()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Vision, the cube and Settings own the microphone while they are on screen.
        stopWakeListening()
        cancelThinkingFiller()
        if !voiceInput.isListening && !speech.isSpeaking {
            voiceInput.closeConversationAudio()
        }
    }

    @objc private func appBecameActive() {
        // Background watch: the Dynamic Island can only be started on screen.
        if JarvisWakeWordSettings.watchesInBackground {
            JarvisLiveActivity.shared.start()
        } else {
            JarvisLiveActivity.shared.stop()
        }
        if runPendingScreenCommand() { return }
        scheduleWakeListening()
        synchronizeWithPC()
    }

    @objc private func appEnteredBackground() {
        let watching = JarvisActivityAttributes.ContentState.watching
        liveShow(watching.phase, title: watching.title, detail: watching.detail)
    }

    // MARK: - Background watch (Dynamic Island)

    private var isOffScreen: Bool { UIApplication.shared.applicationState != .active }

    /// What Jarvis does, on the Dynamic Island and the lock screen, while it is off screen.
    private func liveShow(_ phase: JarvisActivityAttributes.ContentState.Phase, title: String, detail: String, backToWatch: TimeInterval? = nil) {
        guard isOffScreen, JarvisWakeWordSettings.watchesInBackground else { return }
        JarvisLiveActivity.shared.show(phase, title: title, detail: detail, backToWatch: backToWatch)
    }

    /// A call, a message or the photos need the screen: the request waits for Jarvis to
    /// open (a tap on the Dynamic Island), then runs.
    private func waitForScreen(_ response: JarvisResponse) {
        pendingScreenCommand = (lastCommandText, Date())
        liveShow(.needsScreen, title: lastCommandText, detail: "Touchez ici pour continuer : \(response.spokenResponse)")
        if speech.isEnabled {
            setInterfaceState(.speaking, hint: JarvisBackgroundPolicy.waitingForScreen)
            say(JarvisBackgroundPolicy.waitingForScreen)
        } else {
            setInterfaceState(.ready, hint: JarvisBackgroundPolicy.waitingForScreen)
        }
    }

    /// Runs the request that waited for the screen, once. True when one ran.
    @discardableResult
    private func runPendingScreenCommand() -> Bool {
        guard let pending = pendingScreenCommand, !isOffScreen else { return false }
        pendingScreenCommand = nil
        guard Date().timeIntervalSince(pending.date) < JarvisBackgroundPolicy.pendingLifetime, !pending.text.isEmpty else { return false }
        pendingRanAt = Date()
        execute(pending.text, source: "voice")
        return true
    }

    /// After an answer given off screen: back to waiting for the claps.
    private func returnToBackgroundWatch() {
        guard isOffScreen, JarvisWakeWordSettings.watchesInBackground, !voiceInput.isListening else { return }
        voiceInput.startBackgroundWatch()
    }

    /// Shares the first name and the notes with Jarvis PC, then says its messages
    /// (« Envoie sur mon téléphone que… » on the PC).
    private func synchronizeWithPC() {
        JarvisPCLink.shared.synchronize { [weak self] messages in
            guard let self else { return }
            let text = messages.count == 1 ? "Message du PC : \(messages[0])" : "Messages du PC : " + messages.joined(separator: " ; ")
            self.showTransient(text)
            if self.speech.isEnabled, !self.voiceInput.isListening, !self.speech.isSpeaking {
                self.speech.speak(text)
            }
        }
    }

    // MARK: - Réveil par la voix

    private var isWakeListening: Bool { voiceInput.isListening && voiceInput.mode == .wake }

    /// Waits for « Jarvis » again once this screen is idle; the guards in
    /// `startWakeListeningIfIdle` decide at that moment.
    private func scheduleWakeListening(after delay: TimeInterval = 0.6) {
        wakeRestartWorkItem?.cancel()
        wakeRestartWorkItem = nil
        guard JarvisWakeWordSettings.isEnabled, !isUITestMode else { return }
        let work = DispatchWorkItem { [weak self] in
            self?.startWakeListeningIfIdle()
        }
        wakeRestartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func startWakeListeningIfIdle() {
        guard JarvisWakeWordSettings.isEnabled,
              !isUITestMode,
              navigationController?.topViewController === self,
              !isOffScreen || JarvisWakeWordSettings.watchesInBackground else { return }
        if presentedViewController != nil {
            // A sheet or an alert is open (closing it does not call viewDidAppear here).
            scheduleWakeListening(after: 2.0)
            return
        }
        if commandField.isFirstResponder {
            // The user is typing a request: the microphone waits for the keyboard to close.
            scheduleWakeListening(after: 2.0)
            return
        }
        if speech.isSpeaking || speech.isStreamingReply || JarvisLocalBrain.shared.isGenerating {
            // Jarvis is talking or thinking: wait until it is quiet.
            scheduleWakeListening(after: 1.0)
            return
        }
        let idleStates: [JarvisInteractionState] = [.standby, .ready, .done, .quiet]
        guard !voiceInput.isListening,
              !conversationActive,
              !listenAfterWakeReply,
              idleStates.contains(interfaceState) else { return }
        if isOffScreen {
            // Off screen: the next wait for « Jarvis » and the claps, on the microphone kept open.
            voiceInput.startBackgroundWatch()
        } else {
            voiceInput.startListening(mode: .wake)
        }
    }

    private func stopWakeListening() {
        if isWakeListening {
            voiceInput.cancel()
        }
        wakeRestartWorkItem?.cancel()
        wakeRestartWorkItem = nil
    }

    /// Voice events of a wait for « Jarvis »: nothing is shown of what the room says.
    private func handleWakeState(_ state: JarvisVoiceInputState) {
        switch state {
        case .listening:
            if [.standby, .ready, .done, .quiet].contains(interfaceState) {
                hintLabel.text = "À l'écoute : dites « Jarvis », puis votre demande."
            }
        case .standby, .noSpeech:
            scheduleWakeListening(after: 0.25)
        case .unavailable(let failure):
            // No retry loop on an error: the next tap or return to this screen tries again.
            hintLabel.text = "Réveil par la voix en pause : \(failure.message)"
            // Off screen, the claps go on (the recognizer is not tried again until the next return to the background).
            if isOffScreen { scheduleWakeListening(after: 1.0) }
        case .hearingSound, .heardYou, .processing:
            break
        }
    }

    private func handleWakeTranscript(_ transcript: String) {
        // A sheet or an alert is open: drop this request and wait for it to close.
        guard presentedViewController == nil else {
            scheduleWakeListening(after: 2.0)
            return
        }
        guard let request = JarvisWakeWord.command(in: transcript) else {
            // Not addressed to Jarvis: forget it and keep waiting.
            setInterfaceState(interfaceState, hint: "À l'écoute : dites « Jarvis », puis votre demande.")
            return
        }
        if request.isEmpty {
            answerWakeCall()
            return
        }
        execute(request, source: "voice")
    }

    /// Two claps, whatever Jarvis is doing: the same as calling it by name. It stops talking
    /// or thinking, answers « Oui ? » and listens.
    private func handleDoubleClap() {
        guard presentedViewController == nil, !listenAfterWakeReply else { return }
        // Already listening to a request: the claps change nothing.
        if voiceInput.isListening, voiceInput.mode == .command, !bargeInProbe { return }
        // A plain microphone hears Jarvis's own voice: only claps heard with echo cancellation stop it.
        if speech.isSpeaking, !voiceInput.hearsOverJarvis { return }
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
        cancelThinkingFiller()
        resetBargeIn()
        if speech.isSpeaking || speech.isStreamingReply || JarvisLocalBrain.shared.isGenerating {
            JarvisLocalBrain.shared.cancel()
            speech.stop()
        }
        stopWakeListening()
        if voiceInput.isListening { voiceInput.cancel() }
        answerWakeCall()
    }

    /// « Jarvis ? » alone or two claps: answer « Oui ? », then listen to the request.
    private func answerWakeCall() {
        listenAfterWakeReply = true
        setInterfaceState(.ready, hint: "Oui ?")
        if speech.isEnabled {
            // Said through the conversation audio, whose open microphone keeps the words
            // the user says right after « Oui ? ».
            voiceInput.openConversationAudio()
            liveShow(.listening, title: "Oui ?", detail: "Je vous écoute.")
            speech.speak("Oui ?")
        } else {
            listenAfterWakeReply = false
            startVoiceTurn()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // The Vision screen temporarily owns the shared in-app voice callbacks.
        // Rewire them whenever the user returns to the main Jarvis surface.
        wireVoice()
        if interfaceState == .inspection {
            setInterfaceState(.ready, hint: "Vision JARVIS fermée. JARVIS est prêt.")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        voiceInput.cancel()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        backgroundLayer.frame = view.bounds
    }

    private func buildInterface() {
        backgroundLayer.colors = [
            UIColor(red: 0.002, green: 0.005, blue: 0.009, alpha: 1).cgColor,
            UIColor(red: 0.010, green: 0.020, blue: 0.026, alpha: 1).cgColor,
            UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 1).cgColor
        ]
        backgroundLayer.locations = [0, 0.48, 1]
        view.layer.insertSublayer(backgroundLayer, at: 0)

        wordmarkLabel.text = "JARVIS"
        wordmarkLabel.textColor = JarvisTheme.text
        wordmarkLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: JarvisTheme.titleFont(size: 32))
        wordmarkLabel.adjustsFontForContentSizeCategory = true
        wordmarkLabel.textAlignment = .center
        wordmarkLabel.letterSpacing(5.5)
        wordmarkLabel.accessibilityLabel = "JARVIS"
        wordmarkLabel.accessibilityIdentifier = "jarvis.wordmark"

        subtitleLabel.text = "Assistance visuelle à la voix"
        subtitleLabel.textColor = JarvisTheme.mutedText
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textAlignment = .center
        subtitleLabel.accessibilityIdentifier = "jarvis.subtitle"

        orbView.translatesAutoresizingMaskIntoConstraints = false
        orbView.isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(orbTapped))
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(orbLongPressed(_:)))
        longPress.minimumPressDuration = 0.72
        tap.require(toFail: longPress)
        orbView.addGestureRecognizer(tap)
        orbView.addGestureRecognizer(longPress)
        orbView.accessibilityHint = "Appuyez pour réveiller, écouter ou traiter. Maintenez pour mettre en veille."
        orbView.accessibilityIdentifier = "jarvis.orb"

        stateLabel.textColor = JarvisTheme.accentHot
        stateLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        stateLabel.adjustsFontForContentSizeCategory = true
        stateLabel.textAlignment = .center
        stateLabel.accessibilityIdentifier = "jarvis.state"

        hintLabel.textColor = JarvisTheme.mutedText
        hintLabel.font = UIFont.preferredFont(forTextStyle: .body)
        hintLabel.adjustsFontForContentSizeCategory = true
        hintLabel.textAlignment = .center
        hintLabel.numberOfLines = 2
        hintLabel.accessibilityIdentifier = "jarvis.hint"

        transientResponseLabel.textColor = JarvisTheme.text
        transientResponseLabel.font = UIFont.preferredFont(forTextStyle: .body)
        transientResponseLabel.adjustsFontForContentSizeCategory = true
        transientResponseLabel.textAlignment = .center
        transientResponseLabel.numberOfLines = 3
        transientResponseLabel.alpha = 0
        transientResponseLabel.accessibilityIdentifier = "jarvis.transientResponse"

        voiceStageLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        voiceStageLabel.adjustsFontForContentSizeCategory = true
        voiceStageLabel.textAlignment = .center
        voiceStageLabel.numberOfLines = 1
        voiceStageLabel.adjustsFontSizeToFitWidth = true
        voiceStageLabel.minimumScaleFactor = 0.7
        voiceStageLabel.accessibilityIdentifier = "jarvis.voiceStage"
        renderVoiceStage()

        commandField.delegate = self
        commandField.attributedPlaceholder = NSAttributedString(
            string: "Demandez à JARVIS…",
            attributes: [.foregroundColor: JarvisTheme.mutedText]
        )
        commandField.textColor = JarvisTheme.text
        commandField.tintColor = JarvisTheme.accent
        commandField.font = UIFont.preferredFont(forTextStyle: .body)
        commandField.adjustsFontForContentSizeCategory = true
        commandField.autocorrectionType = .no
        commandField.autocapitalizationType = .sentences
        commandField.returnKeyType = .send
        commandField.borderStyle = .none
        commandField.setLeftPadding(4)
        commandField.accessibilityLabel = "Saisie de commande"
        commandField.accessibilityIdentifier = "jarvis.commandInput"

        submitButton.setTitle("Envoyer", for: .normal)
        submitButton.setTitleColor(JarvisTheme.background, for: .normal)
        submitButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        submitButton.titleLabel?.adjustsFontForContentSizeCategory = true
        submitButton.backgroundColor = JarvisTheme.accentHot
        submitButton.layer.cornerRadius = 14
        submitButton.addTarget(self, action: #selector(submitTapped), for: .touchUpInside)
        submitButton.accessibilityLabel = "Envoyer la commande"
        submitButton.accessibilityIdentifier = "jarvis.send"

        menuButton.setTitle("Vision", for: .normal)
        menuButton.setTitleColor(JarvisTheme.mutedText, for: .normal)
        menuButton.titleLabel?.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: JarvisTheme.titleFont(size: 12))
        menuButton.titleLabel?.adjustsFontForContentSizeCategory = true
        menuButton.titleLabel?.adjustsFontSizeToFitWidth = true
        menuButton.titleLabel?.minimumScaleFactor = 0.7
        menuButton.backgroundColor = UIColor.white.withAlphaComponent(0.05)
        menuButton.layer.cornerRadius = 13
        menuButton.layer.borderWidth = 1
        menuButton.layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.menu = utilityMenu()
        menuButton.accessibilityLabel = "Vision JARVIS et systèmes"
        menuButton.accessibilityIdentifier = "jarvis.meshMenu"

        helpButton.setTitle("?", for: .normal)
        helpButton.setTitleColor(JarvisTheme.accentHot, for: .normal)
        helpButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .title2)
        helpButton.titleLabel?.adjustsFontForContentSizeCategory = true
        helpButton.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        helpButton.layer.cornerRadius = 18
        helpButton.layer.borderWidth = 1
        helpButton.layer.borderColor = JarvisTheme.accent.withAlphaComponent(0.42).cgColor
        helpButton.addTarget(self, action: #selector(helpTapped), for: .touchUpInside)
        helpButton.accessibilityLabel = "Aide JARVIS"
        helpButton.accessibilityIdentifier = "jarvis.help"

        let inputRow = UIStackView(arrangedSubviews: [commandField, submitButton])
        inputRow.axis = .horizontal
        inputRow.alignment = .center
        inputRow.spacing = 10
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputContainer.addSubview(inputRow)
        inputContainer.backgroundColor = UIColor(red: 0.025, green: 0.033, blue: 0.040, alpha: 0.92)
        inputContainer.layer.cornerRadius = JarvisDesignSystem.Radius.commandBar

        [wordmarkLabel, subtitleLabel, orbView, stateLabel, hintLabel, voiceStageLabel, transientResponseLabel, inputContainer, menuButton, helpButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }
        view.accessibilityElements = [
            wordmarkLabel,
            subtitleLabel,
            menuButton,
            helpButton,
            orbView,
            stateLabel,
            hintLabel,
            voiceStageLabel,
            transientResponseLabel,
            inputContainer,
        ]

        inputBottomConstraint = inputContainer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -10)
        inputBottomConstraint?.priority = .defaultHigh
        let inputSafeBottomConstraint = inputContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10)
        inputSafeBottomConstraint.priority = .defaultLow
        wordmarkTopConstraint = wordmarkLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8)
        orbCenterYConstraint = orbView.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor, constant: -54)
        orbWidthMultiplierConstraint = orbView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.74)
        orbMaxWidthConstraint = orbView.widthAnchor.constraint(lessThanOrEqualToConstant: 320)

        NSLayoutConstraint.activate([
            wordmarkTopConstraint!,
            wordmarkLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            wordmarkLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            subtitleLabel.topAnchor.constraint(equalTo: wordmarkLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            menuButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            menuButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            menuButton.widthAnchor.constraint(equalToConstant: JarvisDesignSystem.Size.meshWidth),
            menuButton.heightAnchor.constraint(equalToConstant: max(44, JarvisDesignSystem.Size.meshHeight)),

            helpButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 7),
            helpButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            helpButton.widthAnchor.constraint(equalToConstant: max(44, JarvisDesignSystem.Size.helpButton)),
            helpButton.heightAnchor.constraint(equalToConstant: max(44, JarvisDesignSystem.Size.helpButton)),

            orbView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            orbCenterYConstraint!,
            orbWidthMultiplierConstraint!,
            orbView.heightAnchor.constraint(equalTo: orbView.widthAnchor),
            orbMaxWidthConstraint!,

            stateLabel.topAnchor.constraint(equalTo: orbView.bottomAnchor, constant: 18),
            stateLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stateLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),

            hintLabel.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            hintLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            voiceStageLabel.topAnchor.constraint(equalTo: hintLabel.bottomAnchor, constant: 8),
            voiceStageLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            voiceStageLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),

            transientResponseLabel.topAnchor.constraint(equalTo: voiceStageLabel.bottomAnchor, constant: 12),
            transientResponseLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            transientResponseLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),

            inputContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            inputContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            inputContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: JarvisDesignSystem.Size.commandBarHeight),
            inputContainer.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -10),
            inputSafeBottomConstraint,
            inputBottomConstraint!,

            inputRow.leadingAnchor.constraint(equalTo: inputContainer.leadingAnchor, constant: 14),
            inputRow.trailingAnchor.constraint(equalTo: inputContainer.trailingAnchor, constant: -10),
            inputRow.topAnchor.constraint(equalTo: inputContainer.topAnchor, constant: 8),
            inputRow.bottomAnchor.constraint(equalTo: inputContainer.bottomAnchor, constant: -8),
            submitButton.widthAnchor.constraint(equalToConstant: JarvisDesignSystem.Size.sendWidth),
            submitButton.heightAnchor.constraint(greaterThanOrEqualToConstant: JarvisDesignSystem.Size.sendHeight)
        ])
    }

    private func utilityMenu() -> UIMenu {
        UIMenu(title: "Vision et systèmes", children: [
            UIAction(title: "Ouvrir Vision JARVIS") { [weak self] _ in self?.execute("open vision", source: "menu") },
            UIAction(title: "Cube AR à la pince") { [weak self] _ in self?.openARCube() },
            UIAction(title: "Décrire") { [weak self] _ in self?.execute("describe this", source: "menu") },
            UIAction(title: "Guide en direct") { [weak self] _ in self?.execute("start live guide", source: "menu") },
            UIAction(title: "Trouver") { [weak self] _ in
                self?.openVision(JarvisVisionLaunchRequest(mode: .find, command: .run, source: "menu"))
            },
            UIAction(title: "Lire le texte") { [weak self] _ in self?.execute("read this", source: "menu") },
            UIAction(title: "Scanner un code-barres") { [weak self] _ in self?.execute("scan barcode", source: "menu") },
            UIAction(title: "Envoyer un message à un contact") { [weak self] _ in self?.execute("message a contact", source: "menu") },
            UIAction(title: "Control Mesh") { [weak self] _ in self?.controlMeshTapped() },
            UIAction(title: "Réglages") { [weak self] _ in self?.settingsTapped() },
            UIAction(title: "Diagnostics") { [weak self] _ in self?.diagnosticsTapped() },
            UIAction(title: "Mémoire") { [weak self] _ in self?.execute("show notes", source: "menu") },
            UIAction(title: "Aide") { [weak self] _ in self?.helpTapped() }
        ])
    }

    private func wireVoice() {
        speech.onSpeechStart = { [weak self] in
            // Jarvis must not hear its own voice while it waits for « Jarvis ».
            self?.stopWakeListening()
            self?.setVoiceStage(.reply)
            self?.setInterfaceState(.speaking, hint: "JARVIS parle.")
            // In a conversation, the user may interrupt Jarvis by speaking.
            self?.armBargeIn()
        }
        speech.onSpeechFinish = { [weak self] in
            guard let self else { return }
            self.voiceInput.monitorBargeIn(false)
            self.brainReplyStreaming = false
            // A reply interrupted by a new turn reports didCancel asynchronously; it must
            // not pull the screen out of the listening state the user just entered.
            guard !self.voiceInput.isListening else { return }
            if self.listenAfterWakeReply {
                self.listenAfterWakeReply = false
                self.setVoiceStage(.idle)
                // The conversation audio already listens: no need to wait for the voice's tail.
                let delay = self.voiceInput.usesConversationAudio ? 0.1 : 0.35
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, !self.voiceInput.isListening else { return }
                    self.startVoiceTurn()
                }
                return
            }
            self.setVoiceStage(.idle)
            if JarvisSpeechService.shared.isEnabled {
                self.setInterfaceState(.ready, hint: self.conversationActive ? "JARVIS vous écoute à nouveau…" : "JARVIS est prêt. Touchez l'orbe pour parler.")
                self.scheduleConversationRearm()
            } else {
                self.setInterfaceState(.quiet, hint: "Mode silencieux.")
            }
            if !self.conversationActive || self.navigationController?.topViewController !== self {
                // No hands-free exchange goes on here: the microphone closes.
                self.voiceInput.closeConversationAudio()
            }
            // Off screen, the answer given: back to waiting for the claps.
            self.returnToBackgroundWatch()
        }
        voiceInput.onPossibleBargeIn = { [weak self] in
            self?.handlePossibleBargeIn()
        }
        voiceInput.onStateChange = { [weak self] state in
            guard let self else { return }
            if self.voiceInput.mode == .wake {
                self.handleWakeState(state)
                return
            }
            if self.bargeInProbe && !self.bargeInConfirmed {
                // Listening over Jarvis's voice, before the user's words are confirmed.
                self.handleProbeState(state)
                return
            }
            switch state {
            case .standby:
                self.resetBargeIn()
                self.endConversation()
                self.setVoiceStage(.idle)
                self.setInterfaceState(.standby, hint: "JARVIS est prêt.")
            case .listening:
                self.setVoiceStage(.micro)
                self.setInterfaceState(.listening, hint: self.currentTurnIsAutomatic
                    ? "Je vous écoute (conversation continue)."
                    : "Micro actif. Parlez maintenant.")
            case .hearingSound:
                self.setVoiceStage(.sound)
                if self.voiceInput.currentTranscript.isEmpty {
                    self.hintLabel.text = "Son reçu…"
                }
            case .heardYou(let transcript):
                self.currentTurnIsAutomatic = false
                self.setVoiceStage(.text)
                self.setInterfaceState(.heardYou, hint: "« \(transcript) »")
            case .processing:
                self.setInterfaceState(.processing, hint: "Traitement en cours.")
            case .noSpeech:
                self.resetBargeIn()
                if self.currentTurnIsAutomatic {
                    // Silence after a reply ends the hands-free exchange quietly.
                    self.endConversation()
                    self.setVoiceStage(.idle)
                    self.setInterfaceState(.ready, hint: "Conversation en pause. Touchez l'orbe pour reprendre.")
                    return
                }
                self.setVoiceStage(self.voiceStage, failed: true)
                self.setInterfaceState(.ready, hint: "Aucune parole détectée.")
                self.showTransient(self.voiceStage == .sound
                    ? "J'ai capté du son mais aucun mot. Parlez un peu plus près du téléphone, puis touchez l'orbe."
                    : "Le micro n'a capté qu'un son très faible. Parlez plus fort ou plus près, puis touchez l'orbe.")
            case .unavailable(let failure):
                self.resetBargeIn()
                self.endConversation()
                self.setVoiceStage(self.voiceStage, failed: true)
                self.setInterfaceState(.attention, hint: failure.message)
                self.showTransient(failure.message)
                if failure.offersSettings {
                    self.offerVoiceSettings(for: failure)
                }
            }
        }
        voiceInput.onPartialTranscript = { [weak self] transcript in
            guard let self else { return }
            if self.voiceInput.mode == .wake {
                // Only the words addressed to Jarvis appear, never the room's conversation.
                if let request = JarvisWakeWord.command(in: transcript) {
                    self.hintLabel.text = request.isEmpty ? "Oui ?" : request
                }
                return
            }
            if self.bargeInProbe && !self.bargeInConfirmed {
                // Jarvis's echo or a noise is never shown; the user's words stop Jarvis.
                self.handleProbeTranscript(transcript)
                return
            }
            if !transcript.isEmpty { self.setVoiceStage(.text) }
            self.hintLabel.text = transcript.isEmpty ? "Micro actif. Parlez maintenant." : transcript
        }
        voiceInput.onDoubleClap = { [weak self] in
            self?.handleDoubleClap()
        }
        voiceInput.onFinalTranscript = { [weak self] transcript in
            guard let self else { return }
            if self.voiceInput.mode == .wake {
                self.handleWakeTranscript(transcript)
                return
            }
            if self.bargeInProbe && !self.bargeInConfirmed {
                // Only Jarvis's own words were heard: nothing to run, the reply goes on.
                self.endBargeInProbe()
                return
            }
            self.resetBargeIn()
            self.execute(transcript, source: "voice")
        }
        voiceInput.onInputLevel = { [weak self] level in
            guard let self, self.voiceStage == .micro || self.voiceStage == .sound || self.voiceStage == .text else { return }
            self.voiceLevel = level
            self.renderVoiceStage()
        }
    }

    private func startVoiceTurn(automatic: Bool = false) {
        // Stop any reply first so the speech service releases the audio session before
        // the microphone takes it, then listen.
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
        cancelThinkingFiller()
        resetBargeIn()
        // A wait for « Jarvis » gives the microphone to this request.
        stopWakeListening()
        currentTurnIsAutomatic = automatic
        speech.stop()
        voiceStageFailed = false
        voiceLevel = 0
        voiceInput.startListening()
    }

    // MARK: - Interrupting Jarvis by speaking

    /// Jarvis starts a reply in a hands-free conversation: the microphone listens for the
    /// user speaking over it (conversation audio, with echo cancellation).
    private func armBargeIn() {
        guard conversationActive, JarvisConversationSettings.interruptsByVoice, voiceInput.hearsOverJarvis,
              speech.isSpeaking, !voiceInput.isListening, !bargeInProbe else { return }
        voiceInput.monitorBargeIn(true)
    }

    /// The level says the user may be speaking over Jarvis: listen at once, Jarvis's voice
    /// lowered, and stop Jarvis when real words come (handleProbeTranscript).
    private func handlePossibleBargeIn() {
        guard conversationActive, speech.isSpeaking, !voiceInput.isListening, presentedViewController == nil else { return }
        voiceInput.monitorBargeIn(false)
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
        bargeInProbe = true
        bargeInConfirmed = false
        currentTurnIsAutomatic = true
        speech.setVoiceLowered(true)
        voiceInput.startListening()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.bargeInProbe, !self.bargeInConfirmed else { return }
            // Only a noise, or Jarvis's own voice: the reply goes on.
            self.voiceInput.cancel()
        }
        bargeInTimeout?.cancel()
        bargeInTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: timeout)
    }

    private func handleProbeTranscript(_ transcript: String) {
        guard JarvisEchoFilter.isInterruption(transcript, spoken: speech.currentReplyText) else { return }
        // The user speaks: Jarvis stops, and this turn goes on with the user's words.
        bargeInConfirmed = true
        bargeInTimeout?.cancel()
        bargeInTimeout = nil
        speech.setVoiceLowered(false)
        JarvisLocalBrain.shared.cancel()
        speech.stop()
        setVoiceStage(.text)
        setInterfaceState(.listening, hint: transcript)
    }

    private func handleProbeState(_ state: JarvisVoiceInputState) {
        switch state {
        case .standby, .noSpeech, .unavailable:
            endBargeInProbe()
        case .listening, .hearingSound, .heardYou, .processing:
            // Jarvis keeps speaking, lowered, until the user's words are heard.
            break
        }
    }

    /// The probe heard no words of the user: Jarvis goes on as if nothing happened.
    private func endBargeInProbe() {
        resetBargeIn()
        if speech.isSpeaking {
            setVoiceStage(.reply)
            setInterfaceState(.speaking, hint: "JARVIS parle.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.armBargeIn()
            }
        } else {
            // The reply ended meanwhile: the conversation listens again, as after any reply.
            setVoiceStage(.idle)
            setInterfaceState(.ready, hint: "JARVIS vous écoute à nouveau…")
            scheduleConversationRearm()
        }
    }

    private func resetBargeIn() {
        guard bargeInProbe || bargeInTimeout != nil else { return }
        bargeInProbe = false
        bargeInConfirmed = false
        bargeInTimeout?.cancel()
        bargeInTimeout = nil
        speech.setVoiceLowered(false)
    }

    // MARK: - Thinking aloud

    /// A few words when the answer is slow to come (« Voyons voir. »), so the conversation
    /// has no blank; the answer then follows without cutting them. `phrase` replaces the
    /// usual words (« Je regarde la météo. »).
    private func scheduleThinkingFiller(for question: String, phrase: String? = nil) {
        fillerWorkItem?.cancel()
        fillerWorkItem = nil
        guard speech.isEnabled, JarvisConversationSettings.thinksAloud, !brainReplyStreaming else { return }
        let words = phrase ?? thinkingFiller.next(for: question)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.interfaceState == .processing, !self.brainReplyStreaming, !self.voiceInput.isListening,
                  !self.speech.isSpeaking else { return }
            self.brainReplyStreaming = true
            self.speech.beginStreamedReply()
            self.speech.appendStreamedReply(words)
        }
        fillerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + JarvisThinkingFiller.delay, execute: work)
    }

    private func cancelThinkingFiller() {
        fillerWorkItem?.cancel()
        fillerWorkItem = nil
    }

    /// Says a reply. After a filler, the reply follows it in the same stream.
    private func say(_ text: String) {
        if brainReplyStreaming, speech.isStreamingReply {
            brainReplyStreaming = false
            speech.appendStreamedReply(text)
            speech.endStreamedReply()
        } else {
            speech.speak(text)
        }
    }

    /// After a spoken reply to a spoken request, listen again without a tap. The short
    /// delay lets the reply's audio tail end so Jarvis does not hear itself.
    private func scheduleConversationRearm() {
        guard conversationActive,
              JarvisConversationSettings.isContinuous,
              navigationController?.topViewController === self,
              presentedViewController == nil,
              UIApplication.shared.applicationState == .active else { return }
        rearmWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.conversationActive,
                  !self.voiceInput.isListening,
                  self.interfaceState == .ready || self.interfaceState == .done,
                  self.navigationController?.topViewController === self,
                  self.presentedViewController == nil else { return }
            self.startVoiceTurn(automatic: true)
        }
        rearmWorkItem = work
        // With the conversation audio, the echo is cancelled and the microphone already
        // open: the next turn starts at once (its first second is kept anyway).
        DispatchQueue.main.asyncAfter(deadline: .now() + (voiceInput.usesConversationAudio ? 0.15 : 0.45), execute: work)
    }

    private func endConversation() {
        conversationActive = false
        currentTurnIsAutomatic = false
        rearmWorkItem?.cancel()
        rearmWorkItem = nil
        cancelThinkingFiller()
        resetBargeIn()
        voiceInput.monitorBargeIn(false)
        // The conversation's microphone closes once Jarvis has finished speaking.
        if !speech.isSpeaking {
            voiceInput.closeConversationAudio()
        }
    }

    private func setVoiceStage(_ stage: JarvisVoiceStage, failed: Bool = false) {
        voiceStage = stage
        voiceStageFailed = failed
        if stage == .idle || failed { voiceLevel = 0 }
        renderVoiceStage()
    }

    private func renderVoiceStage() {
        let steps: [(JarvisVoiceStage, String)] = [(.micro, "Micro"), (.sound, "Son"), (.text, "Texte"), (.reply, "Réponse")]
        let result = NSMutableAttributedString()
        var spoken: [String] = []
        for (index, step) in steps.enumerated() {
            let reached = voiceStage.rawValue >= step.0.rawValue
            let blocked = voiceStageFailed && step.0.rawValue == voiceStage.rawValue + 1
            let color: UIColor = blocked ? JarvisTheme.warning : reached ? JarvisTheme.accentHot : JarvisTheme.mutedText.withAlphaComponent(0.55)
            var label = "\(blocked ? "✕" : reached ? "●" : "○") \(step.1)"
            if step.0 == .sound, voiceStage.rawValue >= JarvisVoiceStage.micro.rawValue, voiceStage != .reply, !voiceStageFailed {
                let bars = ["▁", "▂", "▃", "▅", "▇"]
                label += " " + bars[min(bars.count - 1, Int(voiceLevel * Float(bars.count)))]
            }
            if index > 0 { result.append(NSAttributedString(string: "  ·  ", attributes: [.foregroundColor: JarvisTheme.mutedText.withAlphaComponent(0.4)])) }
            result.append(NSAttributedString(string: label, attributes: [.foregroundColor: color]))
            spoken.append("\(step.1) \(blocked ? "bloqué" : reached ? "validé" : "en attente")")
        }
        voiceStageLabel.attributedText = result
        voiceStageLabel.accessibilityLabel = "Étapes de la voix : " + spoken.joined(separator: ", ")
    }

    private func offerVoiceSettings(for failure: JarvisVoiceFailure) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "Voix indisponible", message: "\(failure.message)\n\nDétail technique : \(failure.diagnostic)", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Ouvrir Réglages", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        alert.addAction(UIAlertAction(title: "Utiliser le clavier", style: .cancel) { [weak self] _ in
            self?.commandField.becomeFirstResponder()
        })
        present(alert, animated: true)
    }

    private func execute(_ text: String, source: String = "typed") {
        let commandText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !commandText.isEmpty else {
            setInterfaceState(.ready, hint: "JARVIS est prêt.")
            return
        }

        setInterfaceState(.processing, hint: "Traitement en cours.")
        // A spoken request keeps the hands-free exchange going; typing ends it.
        conversationActive = source == "voice" && JarvisConversationSettings.isContinuous
        // A new request: an answer still coming for the previous one is dropped.
        brainTurn += 1
        lastCommandText = commandText
        liveShow(.thinking, title: commandText, detail: "Je réfléchis…")
        if !speech.isStreamingReply { brainReplyStreaming = false }
        let command = JarvisCommand(commandText)
        let decision = assistant.decide(commandText)
        if decision.plan?.shouldPersistGeneralHistory != false {
            let historyCommand = source == "typed" ? command.rawText : "\(source): \(command.rawText)"
            memory.appendHistory(command: historyCommand, response: decision.response.displayResponse)
        }
        run(decision, source: source)
    }

    private func run(_ decision: JarvisAssistantDecision, source: String) {
        var visionRequest = decision.plan?.visionLaunchRequest
        visionRequest?.source = source
        if let plan = decision.plan,
           plan.route == .inAppMessage,
           let rawAction = plan.data["message_action"],
           let action = JarvisMessageAction(rawValue: rawAction) {
            if isOffScreen {
                waitForScreen(decision.response)
                return
            }
            messageComposition.handle(JarvisMessageCommandDetails(
                action: action,
                recipientHint: plan.data["message_recipient_hint"],
                body: plan.data["message_body"]
            ))
            return
        }
        render(response: decision.response, visionRequest: visionRequest)
    }

    /// The PC's brain understood a free request as a command (« Préviens Marie que… » →
    /// « envoie un message à Marie pour lui dire que… »): it runs as if said that way.
    private func runBrainCommand(_ command: String, question: String) {
        let decision = assistant.decide(command)
        if decision.response.data["action"] == "local_brain" {
            // Not a command of the iPhone after all: the brain answers the question itself.
            askLocalBrain(question, allowCommands: false)
            return
        }
        memory.appendHistory(command: "voice: \(question)", response: decision.response.displayResponse)
        lastCommandText = command
        run(decision, source: "voice")
    }

    /// Open question: the local brain writes the answer (shown as it comes), then the
    /// normal rendering speaks it. A tap on the orb interrupts it.
    private func askLocalBrain(_ question: String, allowCommands: Bool = true) {
        setInterfaceState(.processing, hint: "Je réfléchis…")
        showTransient("…")
        brainTurn += 1
        let turn = brainTurn
        if !speech.isStreamingReply { brainReplyStreaming = false }
        // No blank while the answer is written: a few words if it is slow to come.
        scheduleThinkingFiller(for: question)
        // Speech starts with the first complete sentence while the rest is written.
        var streamer = JarvisSentenceStreamer()
        JarvisLocalBrain.shared.answerOpenQuestion(question, allowCommands: allowCommands, onPartial: { [weak self] partial in
            guard let self, self.brainTurn == turn, !partial.isEmpty, !self.voiceInput.isListening,
                  self.interfaceState == .processing || self.interfaceState == .speaking else { return }
            self.showTransient(partial)
            guard self.speech.isEnabled else { return }
            let sentences = streamer.newSentences(in: partial, final: false)
            guard !sentences.isEmpty else { return }
            self.cancelThinkingFiller()
            if !self.brainReplyStreaming {
                self.brainReplyStreaming = true
                self.speech.beginStreamedReply()
                self.scheduleSpeechStartCheck()
            }
            sentences.forEach { self.speech.appendStreamedReply($0) }
        }, completion: { [weak self] answer in
            guard let self, self.brainTurn == turn else { return }
            self.cancelThinkingFiller()
            // A new turn already started (the user tapped and spoke): drop this answer.
            guard !self.voiceInput.isListening else { return }
            // The PC's brain reworded the request into a command: run it.
            if answer.data["action"] == "reroute", let command = answer.data["text"] {
                self.runBrainCommand(command, question: answer.data["question"] ?? question)
                return
            }
            guard self.brainReplyStreaming else {
                self.render(response: answer)
                self.offerBrainDownloadIfNeeded()
                return
            }
            if answer.status == .ok, self.speech.isStreamingReply {
                streamer.newSentences(in: answer.spokenResponse, final: true).forEach { self.speech.appendStreamedReply($0) }
                self.showTransient(answer.displayResponse)
                self.speech.endStreamedReply()
            } else {
                self.speech.stop()
                self.render(response: answer)
            }
        })
    }

    /// First open question without the model: offer the download right here, once per launch.
    private func offerBrainDownloadIfNeeded() {
        guard JarvisLocalBrain.shared.availability == .notInstalled,
              !didOfferBrainDownload,
              presentedViewController == nil,
              !JarvisModelDownloader.shared.isDownloading else { return }
        didOfferBrainDownload = true
        let model = JarvisLocalBrain.shared.model
        let alert = UIAlertController(
            title: "Installer le cerveau local ?",
            message: "Pour répondre aux questions libres sans Internet ni PC, JARVIS télécharge une seule fois \(model.displayName) (\(model.sizeDescription), licence \(model.license)). Wi-Fi conseillé ; gardez JARVIS ouvert pendant le téléchargement.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Plus tard", style: .cancel))
        alert.addAction(UIAlertAction(title: "Télécharger", style: .default) { [weak self] _ in
            if let problem = JarvisModelDownloader.shared.startDownload() {
                self?.showTransient(problem)
            }
        })
        present(alert, animated: true)
    }

    /// Download progress and completion, shown on the home screen.
    private func observeBrainDownload() {
        guard brainDownloadObserver == nil else { return }
        brainDownloadObserver = NotificationCenter.default.addObserver(forName: .jarvisLocalBrainStateChanged, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let downloader = JarvisModelDownloader.shared
            UIApplication.shared.isIdleTimerDisabled = downloader.isDownloading
            if let progress = downloader.stateDescription {
                self.showTransient(progress)
                self.wasDownloadingBrain = downloader.isDownloading
            } else if self.wasDownloadingBrain, downloader.isInstalled {
                self.wasDownloadingBrain = false
                let message = "Cerveau local installé. Posez-moi une question, même sans Internet."
                self.showTransient(message)
                if self.speech.isEnabled, !self.voiceInput.isListening { self.speech.speak(message) }
            }
        }
    }

    /// If the reply never becomes audible, say so instead of staying silent.
    private func scheduleSpeechStartCheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, self.speech.speechFailedToStart(after: 2.4) else { return }
            self.setInterfaceState(.ready, hint: "La voix ne démarre pas : montez le volume, ou vérifiez qu'une voix française est installée (Réglages iOS › Accessibilité › Contenu énoncé › Voix).")
        }
    }

    /// Timers, reminders, agenda, briefing: run the side effect, then render its result.
    private func performLifeAction(_ response: JarvisResponse) {
        setInterfaceState(.processing, hint: response.displayResponse)
        // « Je regarde la météo. », « Je demande au PC. » is said when the result is slow to come.
        let announce = response.spokenResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        scheduleThinkingFiller(for: response.displayResponse, phrase: announce.isEmpty ? nil : announce)
        let turn = brainTurn
        JarvisLifeActionPerformer.perform(response) { [weak self] final in
            guard let self, self.brainTurn == turn else { return }
            self.cancelThinkingFiller()
            guard !self.voiceInput.isListening else { return }
            self.render(response: JarvisLifeActionPerformer.withoutAction(final))
        }
    }

    private func render(response: JarvisResponse, visionRequest: JarvisVisionLaunchRequest? = nil) {
        // Off screen, what iOS shows only on screen (a call, the photos) waits for a tap.
        if isOffScreen, JarvisBackgroundPolicy.needsScreen(response, opensVision: visionRequest != nil) {
            waitForScreen(response)
            return
        }
        if JarvisLifeActionPerformer.handles(response) {
            performLifeAction(response)
            return
        }
        if response.data["action"] == "local_brain", let question = response.data["question"],
           JarvisLocalBrain.shared.availability != .unsupported {
            askLocalBrain(question)
            return
        }
        showTransient(response.displayResponse)
        if response.status == .refused || response.status == .unavailable || response.status == .error {
            setInterfaceState(.ready, hint: response.displayResponse)
        }

        if let visionRequest {
            setInterfaceState(.inspection, hint: "Ouverture de \(visionRequest.mode.visionDisplayName).")
            openVision(visionRequest)
            return
        } else if response.data["action"] == "open_camera" || response.data["action"] == "inspect" {
            let hint = response.data["vision"] == "ocr" ? "Lecture de la cible." : response.data["vision"] == "visual_classification" ? "Ouverture de l'analyse visuelle." : "Ouverture de l'inspection."
            setInterfaceState(.inspection, hint: hint)
            openCamera()
        } else if response.data["action"] == "ar_cube" {
            endConversation()
            openARCube()
        } else if response.data["action"] == "ar_summary" {
            endConversation()
            openARCube(summary: JarvisARSummaryCard(data: response.data))
        } else if response.data["action"] == "diagnostics" {
            diagnosticsTapped()
        } else if response.data["action"] == "settings" {
            settingsTapped()
        } else if response.data["action"] == "control_mesh" {
            controlMeshTapped()
        } else if response.data["url_scheme"] != nil {
            openExternalRoute(response.data["url_scheme"])
        } else if response.data["mode"] == "conversation_end" || response.data["mode"] == "conversation_off" {
            endConversation()
        } else if response.data["mode"] == "standby" {
            endConversation()
            setInterfaceState(.standby, hint: "JARVIS est en attente.")
        } else if response.data["mode"] == "ready" {
            setInterfaceState(.ready, hint: "JARVIS est prêt.")
        } else if response.data["mode"] == "quiet" {
            setInterfaceState(.quiet, hint: "La sortie vocale est muette.")
        }

        // In a hands-free conversation, what cannot be done is said too, not only shown.
        let spokenStatus = response.status == .ok || response.status == .confirmationRequired || (response.status == .unavailable && conversationActive)
        if response.shouldSpeak && speech.isEnabled && spokenStatus && !response.spokenResponse.isEmpty {
            setInterfaceState(.speaking, hint: "JARVIS parle.")
            liveShow(.answering, title: lastCommandText, detail: response.spokenResponse, backToWatch: 20)
            say(response.spokenResponse)
            scheduleSpeechStartCheck()
        } else {
            // A filler said while waiting ends here when nothing follows it.
            if brainReplyStreaming, speech.isStreamingReply {
                brainReplyStreaming = false
                speech.endStreamedReply()
            }
            if response.status == .ok && response.data["action"] == nil {
                setInterfaceState(speech.isEnabled ? .done : .quiet, hint: response.spokenResponse)
            }
        }
    }

    private func setInterfaceState(_ state: JarvisInteractionState, hint: String) {
        interfaceState = state
        if [.standby, .ready, .done, .quiet].contains(state), !isWakeListening {
            scheduleWakeListening()
        }
        stateLabel.text = state.displayName
        stateLabel.accessibilityLabel = state.displayName
        hintLabel.text = hint
        switch state {
        case .standby:
            stateLabel.textColor = JarvisTheme.accent
            orbView.setState(.standby)
        case .ready:
            stateLabel.textColor = JarvisTheme.accentHot
            orbView.setState(.idle)
        case .listening:
            stateLabel.textColor = JarvisTheme.accentHot
            orbView.setState(.listening)
        case .heardYou:
            stateLabel.textColor = JarvisTheme.success
            orbView.setState(.processing)
        case .processing:
            stateLabel.textColor = JarvisTheme.accentHot
            orbView.setState(.processing)
        case .speaking:
            stateLabel.textColor = JarvisTheme.success
            orbView.setState(.speaking)
        case .inspection:
            stateLabel.textColor = JarvisTheme.accentHot
            orbView.setState(.inspection)
        case .done:
            stateLabel.textColor = JarvisTheme.accent
            orbView.setState(.idle)
        case .quiet:
            stateLabel.textColor = JarvisTheme.warning
            orbView.setState(.quiet)
        case .attention:
            stateLabel.textColor = JarvisTheme.warning
            orbView.setState(.error)
        }
    }

    private func showTransient(_ text: String) {
        responseHideWorkItem?.cancel()
        transientResponseLabel.text = compactDisplay(text)
        UIView.animate(withDuration: 0.18) {
            self.transientResponseLabel.alpha = 1
        }
        let work = DispatchWorkItem { [weak self] in
            UIView.animate(withDuration: 0.35) {
                self?.transientResponseLabel.alpha = 0.18
            }
        }
        responseHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
    }

    private func compactDisplay(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = lines.prefix(2).joined(separator: " ")
        return joined.count > 150 ? String(joined.prefix(147)) + "..." : joined
    }

    private func openExternalRoute(_ route: String?) {
        guard let route, let url = URL(string: route) else { return }
        UIApplication.shared.open(url) { [weak self] success in
            guard !success else { return }
            self?.showTransient("Use Control Mesh: say Open \(url.host ?? "the app") or open it from Home.")
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        // Typing a request: the wait for « Jarvis » gives way to the keyboard.
        stopWakeListening()
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        scheduleWakeListening()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        submitCurrentCommand()
        return true
    }

    @objc private func submitTapped() {
        submitCurrentCommand()
    }

    @objc private func orbTapped() {
        if longPressSuppressesNextTap {
            longPressSuppressesNextTap = false
            return
        }
        // A tap always wins over a wait for « Jarvis ».
        stopWakeListening()
        if isUITestMode {
            handleUITestOrbTap()
            return
        }
        switch interfaceState {
        case .standby:
            speech.isEnabled = true
            setInterfaceState(.ready, hint: "JARVIS est prêt.")
            speech.speak("JARVIS est prêt.", notifyState: false)
        case .ready, .done, .attention, .quiet:
            conversationActive = JarvisConversationSettings.isContinuous
            startVoiceTurn()
        case .listening, .heardYou:
            voiceInput.stopListening(process: true)
        case .processing:
            if JarvisLocalBrain.shared.isGenerating {
                JarvisLocalBrain.shared.cancel()
                showTransient("J'arrête de réfléchir.")
            } else {
                showTransient("Traitement en cours.")
            }
        case .speaking:
            JarvisLocalBrain.shared.cancel()
            if bargeInProbe && !bargeInConfirmed {
                // A tap ends the listening over Jarvis's voice too.
                resetBargeIn()
                voiceInput.cancel()
            }
            cancelThinkingFiller()
            speech.stop()
            setVoiceStage(.idle)
            setInterfaceState(.ready, hint: "Parole arrêtée.")
        case .inspection:
            startVoiceTurn()
        }
    }

    @objc private func helpTapped() {
        let controller = JarvisHelpViewController()
        controller.modalPresentationStyle = .pageSheet
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(controller, animated: true)
    }

    @objc private func orbLongPressed(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            longPressSuppressesNextTap = true
            enterStandbyFromLongPress()
        } else if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.longPressSuppressesNextTap = false
            }
        }
    }

    private func enterStandbyFromLongPress() {
        endConversation()
        JarvisLocalBrain.shared.cancel()
        responseHideWorkItem?.cancel()
        transientResponseLabel.alpha = 0
        if voiceInput.isListening {
            voiceInput.stopListening(process: false)
        } else {
            voiceInput.cancel()
        }
        speech.stop()
        commandField.resignFirstResponder()
        setInterfaceState(.standby, hint: "En veille.")
    }

    private func handleUITestOrbTap() {
        switch interfaceState {
        case .standby:
            speech.isEnabled = true
            setInterfaceState(.ready, hint: "JARVIS est prêt.")
        case .ready, .done, .attention, .quiet, .inspection:
            speech.stop()
            setInterfaceState(.listening, hint: "Écoute en cours.")
        case .listening, .heardYou:
            let transcript = (commandField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if transcript.isEmpty {
                setInterfaceState(.ready, hint: "Aucune parole détectée.")
                showTransient("Aucune parole détectée.")
            } else {
                execute(transcript, source: "voice")
            }
        case .processing:
            showTransient("Traitement en cours.")
        case .speaking:
            speech.stop()
            setInterfaceState(.ready, hint: "Parole arrêtée.")
        }
    }

    private func submitCurrentCommand() {
        let text = commandField.text ?? ""
        execute(text)
        commandField.text = ""
        commandField.resignFirstResponder()
    }

    /// Opens the AR cube, optionally with the notes summary card to place on the table.
    /// ARKit then owns the camera; the Vision screen is not running.
    private func openARCube(summary: JarvisARSummaryCard? = nil) {
        guard JarvisARCubeViewController.isSupported else {
            showTransient("La réalité augmentée n'est pas disponible sur cet appareil.")
            return
        }
        if let current = navigationController?.topViewController as? JarvisARCubeViewController {
            if let summary { current.showSummary(summary) }
            return
        }
        navigationController?.pushViewController(JarvisARCubeViewController(pendingSummary: summary), animated: true)
    }

    /// « Dis Jarvis » (raccourci vocal iOS → intention « Parler à JARVIS ») : back to the
    /// home screen and open the microphone. The delay lets Siri release the audio session.
    private func startListeningFromShortcut() {
        if navigationController?.topViewController !== self {
            navigationController?.popToViewController(self, animated: false)
        }
        if presentedViewController != nil {
            dismiss(animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.voiceInput.isListening else { return }
            if self.interfaceState == .standby {
                self.speech.isEnabled = true
            }
            self.conversationActive = JarvisConversationSettings.isContinuous
            self.startVoiceTurn()
        }
    }

    private func controlMeshTapped() {
        setInterfaceState(.processing, hint: "Ouverture de Control Mesh.")
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(JarvisControlMeshViewController(), animated: true)
    }

    private func diagnosticsTapped() {
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(JarvisDiagnosticsViewController(), animated: true)
    }

    private func settingsTapped() {
        navigationController?.setNavigationBarHidden(false, animated: true)
        navigationController?.pushViewController(JarvisSettingsViewController(), animated: true)
    }

    private func openCamera() {
        let preferred = VisionPreferencesStore.shared.value.defaultMode
        let mode = preferred == .inactive || preferred == .identifyColor ? VisionMode.describe : preferred
        openVision(JarvisVisionLaunchRequest(mode: mode, command: .run, source: "legacy"))
    }

    private func openVision(_ request: JarvisVisionLaunchRequest) {
        if !isUITestMode, JarvisVisionFirstRunStore.shared.shouldPresent {
            pendingVisionRequestAfterOnboarding = request
            showFirstLaunchIfNeeded()
            return
        }
        navigationController?.setNavigationBarHidden(false, animated: true)
        if let controller = navigationController?.topViewController as? JarvisCameraViewController {
            controller.apply(request)
            return
        }
        navigationController?.pushViewController(
            JarvisCameraViewController(launchRequest: request),
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }

    @objc private func deepLinkReceived(_ notification: Notification) {
        guard let action = notification.object as? JarvisDeepLinkAction else { return }
        handle(action: action)
    }

    private func handle(action: JarvisDeepLinkAction) {
        switch action {
        case .command(let text):
            execute(text, source: "deep link")
        case .vision(var request):
            request.source = "deep_link"
            openVision(request)
        case .inspect:
            openVision(JarvisVisionLaunchRequest(mode: .describe, command: .run, source: "deep_link"))
        case .diagnostics:
            diagnosticsTapped()
        case .settings:
            settingsTapped()
        case .standby:
            execute("standby", source: "deep link")
        case .online:
            execute("status", source: "deep link")
        case .controlMesh:
            controlMeshTapped()
        case .listen:
            // A tap on the Dynamic Island: first what waited for the screen.
            if runPendingScreenCommand() { return }
            if let ran = pendingRanAt, Date().timeIntervalSince(ran) < 3 { return }
            startListeningFromShortcut()
        case .unknown(let raw):
            render(response: JarvisResponse(status: .refused, spokenResponse: "Deep link not recognized.", displayResponse: "Unknown JARVIS deep link: \(raw)", shouldSpeak: false))
        }
    }

    private func showFirstLaunchIfNeeded() {
        guard !isUITestMode else { return }
        guard JarvisVisionFirstRunStore.shared.shouldPresent else { return }
        if let existing = (presentedViewController as? UINavigationController)?.viewControllers.first as? JarvisVisionOnboardingViewController {
            configureOnboarding(existing)
            return
        }
        let controller = JarvisVisionOnboardingViewController()
        configureOnboarding(controller)
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigation, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    private func configureOnboarding(_ controller: JarvisVisionOnboardingViewController) {
        controller.onOpenVision = { [weak self] in
            guard let self else { return }
            let request = self.pendingVisionRequestAfterOnboarding
                ?? JarvisVisionLaunchRequest(mode: .describe, command: .run, source: "onboarding")
            self.pendingVisionRequestAfterOnboarding = nil
            self.openVision(request)
        }
        controller.onContinue = { [weak self] in
            guard let self, let request = self.pendingVisionRequestAfterOnboarding else { return }
            self.pendingVisionRequestAfterOnboarding = nil
            self.openVision(request)
        }
    }

    private func applyVisualProofStateIfNeeded() {
        guard isUITestMode, !didApplyVisualProofState else { return }
        didApplyVisualProofState = true
        let arguments = ProcessInfo.processInfo.arguments
        let stateKey = arguments.firstIndex(of: "--jarvis-state") ?? arguments.firstIndex(of: "-JARVIS_VISUAL_STATE")
        guard let index = stateKey,
              arguments.indices.contains(index + 1) else { return }
        switch arguments[index + 1] {
        case "ready":
            setInterfaceState(.ready, hint: "JARVIS est prêt.")
        case "listening":
            setInterfaceState(.listening, hint: "Écoute en cours.")
        case "no_speech":
            setInterfaceState(.ready, hint: "Aucune parole détectée.")
            showTransient("Aucune parole détectée.")
        case "long_hold_standby":
            setInterfaceState(.standby, hint: "En veille.")
        case "processing":
            execute("status", source: "visual proof")
        case "speaking":
            setInterfaceState(.speaking, hint: "JARVIS parle.")
            showTransient("JARVIS parle.")
        case "keyboard":
            setInterfaceState(.ready, hint: "JARVIS est prêt.")
            commandField.becomeFirstResponder()
        case "help":
            helpTapped()
        case "inspection":
            openCamera()
        case "object_model_missing":
            openCamera()
        case "vision_idle", "vision_describe_listening", "vision_describe_analyzing", "vision_describe_result",
             "vision_live_active", "vision_find_searching", "vision_find_centered", "vision_reading",
             "vision_scan_result", "vision_permission_denied", "vision_model_unavailable":
            openVision(JarvisVisionLaunchRequest(mode: .describe, command: .run, source: "ui_fixture"))
        case "vision_settings":
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.pushViewController(JarvisSettingsViewController(initialSection: .vision), animated: false)
        case "vision_help":
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.pushViewController(JarvisHelpViewController(initialSection: .vision), animated: false)
        case "vision_self_test":
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.pushViewController(JarvisVisionSelfTestViewController(), animated: false)
        case "vision_onboarding":
            let controller = JarvisVisionOnboardingViewController()
            present(UINavigationController(rootViewController: controller), animated: false)
        case "settings":
            settingsTapped()
        case "diagnostics":
            diagnosticsTapped()
        case "mesh":
            controlMeshTapped()
        default:
            break
        }
    }
}

private extension UITextField {
    func setLeftPadding(_ amount: CGFloat) {
        let padding = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: 1))
        leftView = padding
        leftViewMode = .always
    }
}

private extension UILabel {
    func letterSpacing(_ value: CGFloat) {
        guard let text = text else { return }
        attributedText = NSAttributedString(
            string: text,
            attributes: [.kern: value, .foregroundColor: textColor as Any, .font: font as Any]
        )
    }
}
