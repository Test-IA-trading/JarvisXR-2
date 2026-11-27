import UIKit

final class JarvisVisionOnboardingViewController: UIViewController {
    var onOpenVision: (() -> Void)?
    var onContinue: (() -> Void)?

    private let stackView = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Bienvenue dans Jarvis Vision"
        view.backgroundColor = JarvisTheme.background
        buildInterface()
    }

    private func buildInterface() {
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "jarvis.vision.onboarding.scroll"
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.spacing = 16

        view.addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 18),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -18),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])

        let heading = label("Des yeux pratiques, grâce à la caméra de l'iPhone", style: .largeTitle, color: JarvisTheme.text)
        heading.accessibilityTraits.insert(.header)
        heading.accessibilityIdentifier = "jarvis.vision.onboarding.header"
        stackView.addArrangedSubview(heading)

        let intro = label(
            "Jarvis Vision décrit les objets visibles, suit ce qui change, retrouve les objets reconnus, lit les textes imprimés et scanne les codes-barres.",
            style: .body,
            color: JarvisTheme.mutedText
        )
        stackView.addArrangedSubview(intro)

        addPoint(
            title: "Privé par défaut",
            text: "L'analyse de la caméra se fait sur l'iPhone. Jarvis n'enregistre pas automatiquement les photos, les vidéos, les textes reconnus ni les codes-barres."
        )
        addPoint(
            title: "Utile, pas infaillible",
            text: "Les résultats de la caméra et du modèle peuvent être faux ou incomplets. Jarvis dit quand il doute et peut demander plus de lumière ou une image plus stable."
        )
        addPoint(
            title: "Gardez vos repères de déplacement",
            text: "Jarvis Vision ne remplace ni une canne, ni un chien guide, ni l'aide d'une personne, ni les précautions de déplacement. Un résultat de la caméra n'est jamais une autorisation de traverser ou d'avancer."
        )
        addPoint(
            title: "Vous gardez la main",
            text: "Choisissez une grande action pour commencer. Le bouton rouge Stop reste visible : il coupe l'analyse de la caméra, les annonces, les vibrations et l'écoute."
        )
        addPoint(
            title: "Des autorisations au bon moment",
            text: "L'accès à la caméra n'est demandé qu'au lancement d'une action Vision. Le micro et la reconnaissance vocale ne le sont qu'à la première commande vocale."
        )

        let hapticButton = actionButton("Essayer les vibrations", identifier: "jarvis.vision.onboarding.haptics", action: #selector(hapticTutorialTapped))
        hapticButton.accessibilityHint = "Fait sentir les vibrations gauche, centre, droite et objet trouvé."
        stackView.addArrangedSubview(hapticButton)

        let openButton = actionButton("Ouvrir Jarvis Vision", identifier: "jarvis.vision.onboarding.open", action: #selector(openVisionTapped))
        openButton.backgroundColor = JarvisTheme.accentHot
        openButton.setTitleColor(JarvisTheme.background, for: .normal)
        stackView.addArrangedSubview(openButton)

        let continueButton = actionButton("Continue to JARVIS", identifier: "jarvis.vision.onboarding.continue", action: #selector(continueTapped))
        let skipButton = actionButton("Plus tard", identifier: "jarvis.vision.onboarding.skip", action: #selector(continueTapped))
        stackView.addArrangedSubview(horizontalRow([continueButton, skipButton]))
    }

    private func addPoint(title: String, text: String) {
        let heading = label(title, style: .headline, color: JarvisTheme.accentHot)
        heading.accessibilityTraits.insert(.header)
        let body = label(text, style: .body, color: JarvisTheme.text)
        let stack = UIStackView(arrangedSubviews: [heading, body])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        let panel = JarvisPanelView()
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
        ])
        stackView.addArrangedSubview(panel)
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

    private func actionButton(_ title: String, identifier: String, action: Selector) -> UIButton {
        let button = JarvisTheme.button(title: title)
        button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func horizontalRow(_ views: [UIView]) -> UIStackView {
        let row = UIStackView(arrangedSubviews: views)
        row.axis = .horizontal
        row.spacing = 8
        row.distribution = .fillEqually
        return row
    }

    @objc private func hapticTutorialTapped() {
        let service = VisionHapticsService.shared
        guard service.backend != .unavailable else {
            let alert = UIAlertController(title: "Vibrations indisponibles", message: "Cet appareil donnera les directions à voix haute.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: !UIAccessibility.isReduceMotionEnabled)
            return
        }
        let sessionID = service.beginSession()
        let cues: [(VisionHapticCue, String)] = [
            (.directionLeft, "Gauche"),
            (.directionCenter, "Centre"),
            (.directionRight, "Droite"),
            (.targetAcquired, "Objet trouvé"),
        ]
        for (index, cue) in cues.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.8) {
                UIAccessibility.post(notification: .announcement, argument: cue.1)
                service.play(cue.0, intensity: .standard, sessionID: sessionID)
                if index == cues.count - 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { service.endSession(sessionID) }
                }
            }
        }
    }

    @objc private func openVisionTapped() {
        JarvisVisionFirstRunStore.shared.markCompleted()
        let completion = onOpenVision
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { completion?() }
    }

    @objc private func continueTapped() {
        JarvisVisionFirstRunStore.shared.markCompleted()
        let completion = onContinue
        dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { completion?() }
    }
}
