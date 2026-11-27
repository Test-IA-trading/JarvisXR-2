import AVFoundation
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
    private let wakeWordSwitch = UISwitch()
    private let clapSwitch = UISwitch()
    private let voiceProfileControl = UISegmentedControl(items: ["Jarvis", "Naturel", "Amical", "Claire", "Discrète", "Formelle"])
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

    // Contextual help: « À quoi sert cette option ? » answers about the option touched last.
    private let assistantLabel = UILabel()
    private var optionsByControl: [ObjectIdentifier: JarvisScreenContext.Option] = [:]
    private var optionsByPanel: [ObjectIdentifier: JarvisScreenContext.Option] = [:]
    private var panelsByControl: [ObjectIdentifier: UIView] = [:]
    private var originalBorders: [ObjectIdentifier: (width: CGFloat, color: CGColor?)] = [:]
    private weak var selectedPanel: UIView?
    private let voiceInput = JarvisVoiceInputService.shared
    private let assistant = JarvisAssistantCore()

    // Local brain (on-device language model) controls.
    private let brainExplanationLabel = UILabel()
    private let brainModelControl = UISegmentedControl(items: ["Standard", "Avancé"])
    private let brainStatusLabel = UILabel()
    private let brainSwitch = UISwitch()
    private var brainActionButton: UIButton?
    private var brainObserver: NSObjectProtocol?

    // Jarvis PC: the same assistant on the user's PC, paired with its code.
    private let pcAddressField = UITextField()
    private let pcCodeField = UITextField()
    private let pcStatusLabel = UILabel()
    private let pcBrainSwitch = UISwitch()

    // Voice of Jarvis: which installed French voice speaks, and how to get a better one.
    private let voiceStatusLabel = UILabel()
    private var voiceObservers: [NSObjectProtocol] = []

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
        let ask = UIBarButtonItem(title: "Demander", style: .plain, target: self, action: #selector(askTapped))
        ask.accessibilityLabel = "Demander à JARVIS à quoi sert l'option sélectionnée"
        navigationItem.rightBarButtonItem = ask
        buildInterface()
        loadValues()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        wireVoice()
        refreshVoiceSection()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if voiceInput.isListening {
            voiceInput.cancel()
        }
        JarvisScreenContext.shared.leaveScreen()
    }

    deinit {
        if let brainObserver {
            NotificationCenter.default.removeObserver(brainObserver)
        }
        voiceObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: - Jarvis PC

    private func buildPCSection() {
        let link = JarvisPCLink.shared
        stackView.addArrangedSubview(sectionHeading("Jarvis PC"))
        stackView.addArrangedSubview(textLabel(
            "Jarvis tourne aussi sur votre PC (Jarvis.bat). Relié par son code, il répond avec le cerveau du PC, exécute « Sur le PC, ouvre Spotify » et partage votre prénom et vos notes. À la maison par le Wi-Fi ; ailleurs avec Tailscale.",
            style: .footnote,
            color: JarvisTheme.mutedText
        ))
        configurePCField(pcAddressField, placeholder: "Adresse du PC, par exemple 192.168.1.23", identifier: "jarvis.settings.pc.address")
        pcAddressField.keyboardType = .URL
        pcAddressField.autocapitalizationType = .none
        pcAddressField.text = link.address
        configurePCField(pcCodeField, placeholder: "Code d'appairage affiché par le PC", identifier: "jarvis.settings.pc.code")
        pcCodeField.autocapitalizationType = .allCharacters
        pcCodeField.text = link.pairingCode
        let fields = UIStackView(arrangedSubviews: [pcAddressField, pcCodeField])
        fields.axis = .vertical
        fields.spacing = 10
        stackView.addArrangedSubview(wrapInPanel(fields))

        pcStatusLabel.font = UIFont.preferredFont(forTextStyle: .body)
        pcStatusLabel.adjustsFontForContentSizeCategory = true
        pcStatusLabel.textColor = JarvisTheme.text
        pcStatusLabel.numberOfLines = 0
        pcStatusLabel.accessibilityIdentifier = "jarvis.settings.pc.status"
        pcStatusLabel.text = link.isConfigured
            ? "Adresse enregistrée : \(link.address). Touchez « Tester la liaison »."
            : "Non relié : lancez Jarvis.bat sur le PC, puis saisissez l'adresse et le code qu'il affiche."
        stackView.addArrangedSubview(wrapInPanel(pcStatusLabel))

        let findButton = actionButton("Chercher mon PC", identifier: "jarvis.settings.pc.find", action: #selector(findPCTapped))
        let testButton = actionButton("Tester la liaison", identifier: "jarvis.settings.pc.test", action: #selector(testPCTapped))
        stackView.addArrangedSubview(horizontalRow([findButton, testButton]))

        configureSwitch(
            pcBrainSwitch,
            label: "Poser les questions au cerveau du PC",
            hint: "Quand le PC répond, les questions libres vont à son grand modèle ; sinon, l'iPhone répond lui-même.",
            identifier: "jarvis.settings.pc.brain",
            action: #selector(pcBrainChanged)
        )
        pcBrainSwitch.isOn = link.usesPCBrain
        stackView.addArrangedSubview(settingRow(title: "Poser les questions au cerveau du PC", control: pcBrainSwitch))
    }

    private func configurePCField(_ field: UITextField, placeholder: String, identifier: String) {
        field.placeholder = placeholder
        field.borderStyle = .roundedRect
        field.font = UIFont.preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.clearButtonMode = .whileEditing
        field.returnKeyType = .done
        field.accessibilityIdentifier = identifier
        field.addTarget(self, action: #selector(pcFieldsChanged), for: .editingDidEnd)
        field.addTarget(self, action: #selector(pcFieldReturn(_:)), for: .editingDidEndOnExit)
    }

    @objc private func pcFieldsChanged() {
        JarvisPCLink.shared.address = pcAddressField.text ?? ""
        JarvisPCLink.shared.pairingCode = pcCodeField.text
    }

    @objc private func pcFieldReturn(_ field: UITextField) {
        field.resignFirstResponder()
    }

    @objc private func findPCTapped() {
        pcStatusLabel.text = "Recherche de Jarvis PC sur le Wi-Fi…"
        JarvisPCLink.shared.discover { [weak self] address in
            guard let self else { return }
            guard let address else {
                self.pcStatusLabel.text = "Je ne trouve pas Jarvis PC sur ce Wi-Fi : vérifiez qu'il est lancé, ou saisissez l'adresse qu'il affiche."
                return
            }
            self.pcAddressField.text = address
            JarvisPCLink.shared.address = address
            self.pcStatusLabel.text = "Jarvis PC trouvé à l'adresse \(address). Saisissez son code, puis touchez « Tester la liaison »."
        }
    }

    @objc private func testPCTapped() {
        view.endEditing(true)
        pcFieldsChanged()
        pcStatusLabel.text = "Test de la liaison…"
        JarvisPCLink.shared.checkConnection { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let model):
                self.pcStatusLabel.text = "Relié à Jarvis PC. Cerveau du PC : \(model)."
            case .failure(let error):
                self.pcStatusLabel.text = error.message
            }
        }
    }

    @objc private func pcBrainChanged() {
        JarvisPCLink.shared.usesPCBrain = pcBrainSwitch.isOn
    }

    // MARK: - Voice of Jarvis

    private func buildVoiceSection() {
        stackView.addArrangedSubview(sectionHeading("Voix de Jarvis"))
        voiceStatusLabel.font = UIFont.preferredFont(forTextStyle: .body)
        voiceStatusLabel.adjustsFontForContentSizeCategory = true
        voiceStatusLabel.textColor = JarvisTheme.text
        voiceStatusLabel.numberOfLines = 0
        voiceStatusLabel.accessibilityIdentifier = "jarvis.settings.voice.status"
        voiceStatusLabel.accessibilityTraits.insert(.updatesFrequently)
        stackView.addArrangedSubview(wrapInPanel(voiceStatusLabel))

        let chooseButton = actionButton("Choisir la voix", identifier: "jarvis.settings.voice.choose", action: #selector(chooseVoiceTapped(_:)))
        let betterButton = actionButton("Voix plus naturelle", identifier: "jarvis.settings.voice.better", action: #selector(betterVoiceTapped))
        stackView.addArrangedSubview(horizontalRow([chooseButton, betterButton]))

        // A voice downloaded in iOS Settings shows up when the user comes back.
        let center = NotificationCenter.default
        voiceObservers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshVoiceSection()
        })
        voiceObservers.append(center.addObserver(forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshVoiceSection()
        })
        refreshVoiceSection()
    }

    private func refreshVoiceSection() {
        voiceStatusLabel.text = JarvisSpeechService.shared.currentVoiceDescription()
    }

    @objc private func chooseVoiceTapped(_ sender: UIButton) {
        let speech = JarvisSpeechService.shared
        let choices = speech.frenchVoiceChoices()
        let sheet = UIAlertController(
            title: "Voix de Jarvis",
            message: choices.isEmpty
                ? "Aucune voix française n'est installée sur cet iPhone."
                : "Touchez une voix : Jarvis la fait entendre et la garde.",
            preferredStyle: .actionSheet
        )
        let automaticTitle = (speech.chosenVoiceIdentifier == nil ? "✓ " : "") + "Automatique (meilleure voix installée)"
        sheet.addAction(UIAlertAction(title: automaticTitle, style: .default) { [weak self] _ in
            speech.chosenVoiceIdentifier = nil
            speech.previewVoice(identifier: nil)
            self?.refreshVoiceSection()
        })
        for choice in choices.prefix(12) {
            let mark = speech.chosenVoiceIdentifier == choice.identifier ? "✓ " : ""
            sheet.addAction(UIAlertAction(title: mark + choice.menuTitle, style: .default) { [weak self] _ in
                speech.chosenVoiceIdentifier = choice.identifier
                speech.previewVoice(identifier: choice.identifier)
                self?.refreshVoiceSection()
            })
        }
        sheet.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        sheet.popoverPresentationController?.sourceView = sender
        sheet.popoverPresentationController?.sourceRect = sender.bounds
        present(sheet, animated: true)
    }

    @objc private func betterVoiceTapped() {
        let alert = UIAlertController(
            title: "Une voix plus naturelle",
            message: "Les voix « Améliorée » et « Premium » d'Apple sont gratuites et fonctionnent sans Internet une fois téléchargées. Une app ne peut pas les télécharger elle-même.\n\n1. Ouvrez l'app Réglages de l'iPhone › Accessibilité › Contenu énoncé › Voix.\n2. Touchez Français, puis une voix : Thomas est une voix d'homme, la plus proche de Jarvis.\n3. Téléchargez sa version « Améliorée » (ou « Premium » si elle existe).\n\nRevenez ensuite dans Jarvis : il prend tout seul la meilleure voix installée.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Local brain

    private func buildBrainSection() {
        stackView.addArrangedSubview(sectionHeading("Cerveau local (hors ligne)"))
        brainExplanationLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        brainExplanationLabel.adjustsFontForContentSizeCategory = true
        brainExplanationLabel.textColor = JarvisTheme.mutedText
        brainExplanationLabel.numberOfLines = 0
        brainExplanationLabel.accessibilityIdentifier = "jarvis.settings.brain.explanation"
        stackView.addArrangedSubview(brainExplanationLabel)

        let standard = JarvisLocalModel.qwen25Instruct1_5B
        let advanced = JarvisLocalModel.qwen3Instruct4B
        configureSegmented(brainModelControl, identifier: "jarvis.settings.brain.model", action: #selector(brainModelChanged))
        stackView.addArrangedSubview(settingPanel(
            title: "Cerveau",
            detail: "Standard : \(standard.displayName), \(standard.sizeDescription), rapide. Avancé : \(advanced.displayName), \(advanced.sizeDescription), bien meilleur en raisonnement et en maths, plus lent ; il lui faut environ \(JarvisLocalModel.gigabytes(advanced.requiredMemoryBytes)) de mémoire libre.",
            control: brainModelControl
        ))

        brainStatusLabel.font = UIFont.preferredFont(forTextStyle: .body)
        brainStatusLabel.adjustsFontForContentSizeCategory = true
        brainStatusLabel.textColor = JarvisTheme.text
        brainStatusLabel.numberOfLines = 0
        brainStatusLabel.accessibilityIdentifier = "jarvis.settings.brain.status"
        brainStatusLabel.accessibilityTraits.insert(.updatesFrequently)
        stackView.addArrangedSubview(wrapInPanel(brainStatusLabel))

        let button = actionButton("Télécharger le cerveau", identifier: "jarvis.settings.brain.action", action: #selector(brainActionTapped))
        brainActionButton = button
        stackView.addArrangedSubview(button)

        configureSwitch(
            brainSwitch,
            label: "Répondre aux questions libres",
            hint: "Quand aucune commande ne correspond, JARVIS pose la question au cerveau local installé sur l'iPhone.",
            identifier: "jarvis.settings.brain.enabled",
            action: #selector(brainSwitchChanged)
        )
        stackView.addArrangedSubview(settingRow(title: "Répondre aux questions libres", control: brainSwitch))

        brainObserver = NotificationCenter.default.addObserver(forName: .jarvisLocalBrainStateChanged, object: nil, queue: .main) { [weak self] _ in
            self?.refreshBrainSection()
        }
        refreshBrainSection()
    }

    private func refreshBrainSection() {
        let brain = JarvisLocalBrain.shared
        let downloader = JarvisModelDownloader.shared
        let model = brain.model
        brainExplanationLabel.text = "Pour répondre aux questions libres sans Internet ni PC, JARVIS utilise un modèle de langage installé sur l'iPhone : \(model.displayName), licence \(model.license), \(model.sizeDescription) téléchargés une seule fois depuis \(model.source). Vos questions restent sur l'iPhone."
        brainModelControl.selectedSegmentIndex = model.isAdvanced ? 1 : 0
        // One download at a time: the choice waits until it ends.
        brainModelControl.isEnabled = !JarvisModelDownloader.isAnyDownloading
        brainSwitch.isOn = brain.isEnabled
        if let progress = downloader.stateDescription {
            brainStatusLabel.text = progress
        } else {
            brainStatusLabel.text = brain.statusDescription
        }
        let title: String
        if !JarvisLocalBrain.isEngineCompiled {
            title = "Disponible sur iPhone"
            brainActionButton?.isEnabled = false
        } else if downloader.isDownloading {
            title = "Annuler le téléchargement"
            brainActionButton?.isEnabled = true
        } else if downloader.isInstalled {
            title = "Supprimer le cerveau (\(brain.model.sizeDescription))"
            brainActionButton?.isEnabled = true
        } else {
            title = "Télécharger le cerveau (\(brain.model.sizeDescription))"
            brainActionButton?.isEnabled = true
        }
        brainActionButton?.setTitle(title, for: .normal)
        brainActionButton?.accessibilityLabel = title
        // Keep the screen on while the model downloads: the download needs the app open.
        UIApplication.shared.isIdleTimerDisabled = downloader.isDownloading
    }

    @objc private func brainSwitchChanged() {
        JarvisLocalBrain.shared.isEnabled = brainSwitch.isOn
    }

    /// Standard or Avancé: each brain is downloaded once, both can stay installed.
    @objc private func brainModelChanged() {
        guard !JarvisModelDownloader.isAnyDownloading else {
            refreshBrainSection()
            return
        }
        JarvisLocalModel.selected = brainModelControl.selectedSegmentIndex == 1 ? .qwen3Instruct4B : .qwen25Instruct1_5B
        JarvisLocalBrain.shared.unloadIfIdle()
        NotificationCenter.default.post(name: .jarvisLocalBrainStateChanged, object: nil)
        refreshBrainSection()
    }

    @objc private func brainActionTapped() {
        let downloader = JarvisModelDownloader.shared
        let model = JarvisLocalBrain.shared.model
        if downloader.isDownloading {
            downloader.cancelDownload()
            return
        }
        if downloader.isInstalled {
            let alert = UIAlertController(
                title: "Supprimer le cerveau local ?",
                message: "Le fichier de \(model.sizeDescription) sera effacé. JARVIS gardera ses commandes, mais ne répondra plus aux questions libres tant que vous ne l'aurez pas retéléchargé.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
            alert.addAction(UIAlertAction(title: "Supprimer", style: .destructive) { _ in
                JarvisLocalBrain.shared.unloadIfIdle()
                downloader.deleteModel()
            })
            present(alert, animated: true)
            return
        }
        let alert = UIAlertController(
            title: "Télécharger le cerveau local ?",
            message: "\(model.displayName), \(model.sizeDescription), licence \(model.license), depuis \(model.source). Le Wi-Fi est conseillé ; gardez JARVIS ouvert pendant le téléchargement. Ensuite, tout fonctionne sans Internet et vos questions restent sur l'iPhone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Annuler", style: .cancel))
        alert.addAction(UIAlertAction(title: "Télécharger", style: .default) { [weak self] _ in
            if let problem = downloader.startDownload() {
                self?.brainStatusLabel.text = problem
            }
        })
        present(alert, animated: true)
    }

    // MARK: - Contextual help

    private func registerOption(_ control: UIView, title: String, explanation: String) {
        let option = JarvisScreenContext.Option(title: title, explanation: explanation, screen: self.title ?? "Réglages")
        optionsByControl[ObjectIdentifier(control)] = option
        if let uiControl = control as? UIControl {
            uiControl.addTarget(self, action: #selector(optionChanged(_:)), for: .valueChanged)
        }
    }

    /// Lets a tap on the option's panel select it without changing its value.
    private func linkPanel(_ panel: UIView, to control: UIView) {
        guard let option = optionsByControl[ObjectIdentifier(control)] else { return }
        optionsByPanel[ObjectIdentifier(panel)] = option
        panelsByControl[ObjectIdentifier(control)] = panel
        let tap = UITapGestureRecognizer(target: self, action: #selector(panelTapped(_:)))
        tap.cancelsTouchesInView = false
        panel.addGestureRecognizer(tap)
    }

    @objc private func optionChanged(_ sender: UIControl) {
        guard let option = optionsByControl[ObjectIdentifier(sender)] else { return }
        select(option, panel: panelsByControl[ObjectIdentifier(sender)])
    }

    @objc private func panelTapped(_ gesture: UITapGestureRecognizer) {
        guard let panel = gesture.view, let option = optionsByPanel[ObjectIdentifier(panel)] else { return }
        select(option, panel: panel)
    }

    private func select(_ option: JarvisScreenContext.Option, panel: UIView?) {
        let context = JarvisScreenContext.shared
        guard context.isAssistanceEnabled else { return }
        context.select(option)
        if let previous = selectedPanel, let original = originalBorders[ObjectIdentifier(previous)] {
            previous.layer.borderWidth = original.width
            previous.layer.borderColor = original.color
        }
        guard let panel else { return }
        if originalBorders[ObjectIdentifier(panel)] == nil {
            originalBorders[ObjectIdentifier(panel)] = (panel.layer.borderWidth, panel.layer.borderColor)
        }
        panel.layer.borderWidth = 2
        panel.layer.borderColor = JarvisTheme.accentHot.cgColor
        selectedPanel = panel
        panel.accessibilityValue = "Sélectionnée pour l'aide JARVIS"
    }

    @objc private func askTapped() {
        if voiceInput.isListening {
            voiceInput.stopListening(process: true)
            return
        }
        JarvisSpeechService.shared.stop()
        voiceInput.startListening()
    }

    private func showAssistant(_ text: String) {
        assistantLabel.text = text
        assistantLabel.isHidden = text.isEmpty
    }

    private func wireVoice() {
        voiceInput.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .listening:
                self.navigationItem.rightBarButtonItem?.title = "Terminer"
                self.showAssistant("Micro actif : demandez « À quoi sert cette option ? ».")
            case .hearingSound:
                if self.voiceInput.currentTranscript.isEmpty { self.showAssistant("Son reçu…") }
            case .heardYou(let transcript):
                self.showAssistant("« \(transcript) »")
            case .processing:
                self.navigationItem.rightBarButtonItem?.title = "Demander"
            case .standby:
                self.navigationItem.rightBarButtonItem?.title = "Demander"
            case .noSpeech:
                self.navigationItem.rightBarButtonItem?.title = "Demander"
                self.showAssistant("Aucune parole détectée. Touchez « Demander » et réessayez.")
            case .unavailable(let failure):
                self.navigationItem.rightBarButtonItem?.title = "Demander"
                self.showAssistant(failure.message)
            }
        }
        voiceInput.onPartialTranscript = { [weak self] text in
            guard let self, !text.isEmpty else { return }
            self.showAssistant(text)
        }
        voiceInput.onInputLevel = nil
        voiceInput.onFinalTranscript = { [weak self] text in
            guard let self else { return }
            let response = self.assistant.decide(text).response
            let speech = JarvisSpeechService.shared
            if JarvisLifeActionPerformer.handles(response) {
                self.showAssistant(response.displayResponse)
                JarvisLifeActionPerformer.perform(response) { [weak self] final in
                    self?.showAssistant(final.displayResponse)
                    if final.shouldSpeak, speech.isEnabled, final.status == .ok {
                        speech.speak(final.spokenResponse)
                    }
                }
                return
            }
            if response.data["action"] == "local_brain", let question = response.data["question"],
               JarvisLocalBrain.shared.availability != .unsupported {
                self.showAssistant("Je réfléchis…")
                JarvisLocalBrain.shared.answerOpenQuestion(question, onPartial: { [weak self] partial in
                    self?.showAssistant(partial)
                }, completion: { [weak self] answer in
                    self?.showAssistant(answer.displayResponse)
                    if answer.shouldSpeak, speech.isEnabled, answer.status == .ok {
                        speech.speak(answer.spokenResponse)
                    }
                })
                return
            }
            self.showAssistant(response.displayResponse)
            if response.shouldSpeak, speech.isEnabled, response.status == .ok || response.status == .confirmationRequired {
                speech.speak(response.spokenResponse)
            }
        }
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

        let contextualHint = textLabel(
            "Touchez une option, puis « Demander » et dites « À quoi sert cette option ? ».",
            style: .footnote,
            color: JarvisTheme.mutedText
        )
        contextualHint.accessibilityIdentifier = "jarvis.settings.assistantHint"
        stackView.addArrangedSubview(contextualHint)
        assistantLabel.font = UIFont.preferredFont(forTextStyle: .body)
        assistantLabel.adjustsFontForContentSizeCategory = true
        assistantLabel.textColor = JarvisTheme.accentHot
        assistantLabel.numberOfLines = 0
        assistantLabel.isHidden = true
        assistantLabel.accessibilityIdentifier = "jarvis.settings.assistant"
        assistantLabel.accessibilityTraits.insert(.updatesFrequently)
        stackView.addArrangedSubview(assistantLabel)

        configureSwitch(
            speechSwitch,
            label: "Sortie vocale",
            hint: "Énonce les résultats de JARVIS et Vision.",
            identifier: "jarvis.settings.speechSwitch",
            action: #selector(speechChanged)
        )
        stackView.addArrangedSubview(settingRow(title: "Sortie vocale", control: speechSwitch, identifier: "jarvis.settings.speechLabel"))

        let wakeExplanation = "Quand JARVIS est ouvert sur l'accueil, dites « Jarvis » puis votre demande, sans toucher l'écran. La reconnaissance reste sur l'iPhone et rien n'est enregistré ; le micro reste actif (point orange) et la batterie s'use un peu plus."
        wakeWordSwitch.addTarget(self, action: #selector(wakeWordChanged), for: .valueChanged)
        wakeWordSwitch.accessibilityLabel = "Réveil par la voix"
        wakeWordSwitch.accessibilityHint = wakeExplanation
        wakeWordSwitch.accessibilityIdentifier = "jarvis.settings.wakeWord"
        stackView.addArrangedSubview(settingPanel(title: "Réveil par la voix (« Jarvis »)", detail: wakeExplanation, control: wakeWordSwitch))
        configureSwitch(
            clapSwitch,
            label: "Aussi deux clappements de mains",
            hint: "Pendant le réveil par la voix, deux clappements rapprochés appellent aussi Jarvis. Seul le niveau sonore est mesuré, sur l'iPhone ; rien n'est enregistré.",
            identifier: "jarvis.settings.wakeClaps",
            action: #selector(clapSwitchChanged)
        )
        stackView.addArrangedSubview(settingRow(title: "Aussi deux clappements de mains", control: clapSwitch))

        configureSegmented(voiceProfileControl, identifier: "jarvis.settings.voiceProfile", action: #selector(profileChanged))
        stackView.addArrangedSubview(settingPanel(title: "Profil vocal", detail: "Modifie le débit, la tonalité et le volume de la voix système locale.", control: voiceProfileControl))

        buildVoiceSection()

        buildBrainSection()

        buildPCSection()

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
        wakeWordSwitch.isOn = JarvisWakeWordSettings.isEnabled
        clapSwitch.isOn = JarvisWakeWordSettings.clapsEnabled
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
        registerOption(control, title: label, explanation: hint)
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
        linkPanel(panel, to: control)
        return panel
    }

    private func settingPanel(title: String, detail: String, control: UIView) -> UIView {
        let heading = textLabel(title, style: .headline, color: JarvisTheme.text)
        heading.accessibilityTraits.insert(.header)
        let detailLabel = textLabel(detail, style: .footnote, color: JarvisTheme.mutedText)
        let stack = UIStackView(arrangedSubviews: [heading, detailLabel, control])
        stack.axis = .vertical
        stack.spacing = 8
        let panel = wrapInPanel(stack)
        registerOption(control, title: title, explanation: detail)
        linkPanel(panel, to: control)
        return panel
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

    @objc private func clapSwitchChanged() {
        JarvisWakeWordSettings.clapsEnabled = clapSwitch.isOn
    }

    @objc private func wakeWordChanged() {
        JarvisWakeWordSettings.isEnabled = wakeWordSwitch.isOn
        if wakeWordSwitch.isOn {
            showAssistant("Réveil par la voix activé : revenez à l'accueil et dites « Jarvis », puis votre demande.")
        }
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
        case 1: JarvisSpeechService.shared.profile = .natural
        case 2: JarvisSpeechService.shared.profile = .friendly
        case 3: JarvisSpeechService.shared.profile = .crisp
        case 4: JarvisSpeechService.shared.profile = .quiet
        case 5: JarvisSpeechService.shared.profile = .formal
        default: JarvisSpeechService.shared.profile = .jarvis
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
        case .jarvis: return 0
        case .natural: return 1
        case .friendly: return 2
        case .crisp: return 3
        case .quiet: return 4
        case .formal: return 5
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
