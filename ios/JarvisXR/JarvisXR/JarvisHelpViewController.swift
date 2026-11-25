import UIKit

enum JarvisHelpSection {
    case overview
    case vision
}

final class JarvisHelpViewController: UIViewController {
    private let initialSection: JarvisHelpSection
    private let scrollView = UIScrollView()
    private let stackView = UIStackView()

    init(initialSection: JarvisHelpSection = .overview) {
        self.initialSection = initialSection
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        initialSection = .overview
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = initialSection == .vision ? "Aide Vision" : "Aide"
        view.backgroundColor = JarvisTheme.background
        buildInterface()
    }

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.accessibilityIdentifier = "jarvis.help.scroll"

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
            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            stackView.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -28),
        ])

        let header = label(
            initialSection == .vision ? "Utiliser Jarvis Vision" : "Utiliser JARVIS",
            style: .largeTitle,
            color: JarvisTheme.text
        )
        header.accessibilityTraits.insert(.header)
        header.accessibilityIdentifier = "jarvis.help.header"
        stackView.addArrangedSubview(header)

        let intro = label(
            "Touchez l'orbe ou le bouton Voix et parlez en français, ou passez par Raccourcis et les liens jarvis://. Chaque résultat de la caméra est lu à voix haute et affiché.",
            style: .body,
            color: JarvisTheme.mutedText
        )
        stackView.addArrangedSubview(intro)

        addCallout(
            "La sécurité d'abord",
            "Jarvis peut rater ou mal reconnaître des choses. Il ne remplace ni une canne, ni un chien guide, ni l'aide d'une personne, ni les précautions de déplacement. Un résultat de la caméra n'est jamais une autorisation de traverser ou d'avancer."
        )

        addSection("Décrire ce qui vous entoure", [
            "Choisissez Décrire, orientez le téléphone, puis touchez « Décrire ce qui est là ».",
            "Dites : « Qu'est-ce que tu vois ? » ou « Décris ».",
            "« Plus de détails » développe le dernier résultat sans reprendre de photo.",
        ])
        addSection("Guide en direct", [
            "Choisissez Guide en direct, puis « Lancer le guide en direct ». Jarvis annonce une fois chaque objet qui apparaît, se déplace ou disparaît, tant que l'app reste ouverte.",
            "Touchez Voix et demandez : « Elle est où maintenant ? », « Qu'est-ce qui a bougé ? » ou « Qu'est-ce que tu vois ? ».",
            "Quand c'est le téléphone qui bouge, Jarvis ne l'annonce pas comme un déplacement de l'objet. Le guide s'arrête quand Jarvis passe en arrière-plan. C'est une aide d'information, pas un outil de navigation certifié.",
        ])
        addSection("Trouver un objet", [
            "Choisissez Trouver, nommez un objet reconnu (tasse, chaise, bouteille, téléphone…) et balayez lentement.",
            "Dites : « Trouve la tasse » ou « Cherche mon téléphone ».",
            "Jarvis indique gauche, centre ou droite, et dit honnêtement quand l'objet n'est pas reconnu ou a été perdu.",
        ])
        addSection("Lire un texte", [
            "Choisissez Lire, tenez le texte imprimé immobile, puis « Capturer et lire ».",
            "Dites : « Lis ce texte ». Pause lecture, Ligne précédente et Ligne suivante permettent de naviguer.",
            "Le texte reconnu ne reste que pendant la session et n'entre pas dans l'historique des commandes.",
        ])
        addSection("Scanner un code-barres", [
            "Choisissez Code-barres et passez lentement sur l'emballage ou le code.",
            "Dites : « Scanne le code-barres ». Jarvis lit la valeur et n'ouvre jamais un lien tout seul.",
        ])
        addSection("Couleur et qualité de l'image", [
            "Le mode Couleur nomme approximativement la couleur au centre de l'image ; elle change avec la lumière.",
            "Si l'image est trop sombre, floue ou masquée, Jarvis le dit et propose plus de lumière, moins de mouvement ou un autre cadrage.",
        ])
        addSection("Lampe", [
            "Touchez Lampe pour l'allumer ou l'éteindre.",
            "La lampe s'éteint quand Vision s'arrête ou quand l'app passe en arrière-plan.",
        ])
        addSection("Préparer un message", [
            "Le choix du contact passe par le sélecteur d'iOS, et Jarvis vous relit le destinataire et le brouillon.",
            "L'envoi ou l'annulation se fait dans la fenêtre de message d'iOS : Jarvis n'envoie rien sans vous et n'envoie ni vos contacts ni vos messages en ligne.",
        ])
        addSection("Stop, répéter et voix", [
            "Le bouton rouge Stop reste visible en bas de Vision : il coupe l'analyse de la caméra, la voix, les vibrations et l'écoute.",
            "Dites : « Stop », « Arrête d'observer » ou « Coupe la caméra ». Le bouton Répéter relit le dernier résultat.",
            "Touchez Voix dans Vision pour donner ces commandes sans revenir à l'accueil.",
        ])
        addSection("Vibrations", [
            "Des vibrations distinctes indiquent gauche, centre et droite, objet trouvé, objet perdu, alerte et fin.",
            "Vous pouvez les réduire ou les couper dans les Réglages Vision ; la voix reste disponible.",
        ])
        addSection("Confidentialité", [
            "L'analyse Vision se fait sur l'iPhone, sans service réseau.",
            "Jarvis n'enregistre pas automatiquement les photos, les vidéos, les textes reconnus ni les codes-barres.",
            "Arrêter Vision efface la mémoire temporaire de la scène : objets vus, positions, capteurs de mouvement.",
        ])
        addSection("Dépannage", [
            "Accès à la caméra coupé : touchez « Ouvrir les Réglages iOS », activez Caméra, revenez, puis « Réessayer ».",
            "Modèle indisponible : Lire et Code-barres peuvent encore fonctionner ; les Diagnostics donnent les détails.",
            "Résultat sombre ou flou : ajoutez de la lumière, rapprochez-vous, stabilisez le téléphone et recommencez.",
            "Pas de voix : vérifiez la sortie vocale dans les Réglages et la sortie audio en cours.",
            "Voix robotique : Réglages › Voix de Jarvis › « Voix plus naturelle » explique comment télécharger gratuitement une voix « Améliorée » ou « Premium ».",
        ])
        addSection("JARVIS et Control Mesh", [
            "Touchez l'orbe et parlez. Jarvis réécoute après chaque réponse ; dites « C'est tout » pour arrêter.",
            "Touchez l'orbe pendant que Jarvis réfléchit ou parle pour l'interrompre.",
            "Maintenez l'orbe appuyé pour remettre Jarvis en veille.",
            "Réveil par la voix (Réglages) : JARVIS ouvert sur l'accueil, dites « Jarvis, quelle heure est-il ? » ou tapez deux fois dans vos mains, sans toucher l'écran.",
            "Posez n'importe quelle question : une fois le cerveau local téléchargé (Réglages › Cerveau local), Jarvis répond même en mode avion.",
            "Dites « Je m'appelle… » et « Souviens-toi que… » : Jarvis s'en sert pour vous répondre. « Qu'est-ce que tu sais sur moi ? » fait le point, tout reste sur l'iPhone.",
            "Calculs, conversions et dates exacts, sans Internet : « Combien font 128 fois 46 ? », « Intégrale de 0 à 1 de x au carré », « 10 miles en kilomètres », « Combien de jours avant Noël ? ».",
            "Dites aussi : « Mets un minuteur de 10 minutes », « Rappelle-moi d'appeler maman demain à 18 h », « Qu'est-ce que j'ai demain ? », « Fais-moi le point », « Ouvre le cube ».",
            "Control Mesh explique les commandes vocales d'iOS, les Raccourcis et les liens pris en charge, sans prétendre contrôler le système.",
        ])

        let done = JarvisTheme.button(title: "Terminé")
        done.titleLabel?.font = UIFont.preferredFont(forTextStyle: .headline)
        done.titleLabel?.adjustsFontForContentSizeCategory = true
        done.accessibilityIdentifier = "jarvis.help.done"
        done.addTarget(self, action: #selector(doneTapped), for: .touchUpInside)
        stackView.addArrangedSubview(done)
    }

    private func addCallout(_ title: String, _ text: String) {
        let panel = makePanel(title: title, rows: [text])
        panel.layer.borderColor = JarvisTheme.warning.cgColor
        panel.accessibilityIdentifier = "jarvis.help.safety"
        stackView.addArrangedSubview(panel)
    }

    private func addSection(_ title: String, _ rows: [String]) {
        stackView.addArrangedSubview(makePanel(title: title, rows: rows))
    }

    private func makePanel(title: String, rows: [String]) -> JarvisPanelView {
        let panel = JarvisPanelView()
        let vertical = UIStackView()
        vertical.translatesAutoresizingMaskIntoConstraints = false
        vertical.axis = .vertical
        vertical.spacing = 9
        panel.addSubview(vertical)

        let titleLabel = label(title, style: .headline, color: JarvisTheme.accentHot)
        titleLabel.accessibilityTraits.insert(.header)
        vertical.addArrangedSubview(titleLabel)
        for row in rows {
            vertical.addArrangedSubview(label(row, style: .body, color: JarvisTheme.text))
        }

        NSLayoutConstraint.activate([
            vertical.topAnchor.constraint(equalTo: panel.topAnchor, constant: 14),
            vertical.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            vertical.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            vertical.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -14),
        ])
        return panel
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

    @objc private func doneTapped() {
        if presentingViewController != nil, navigationController == nil {
            dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        } else if navigationController?.viewControllers.first !== self {
            navigationController?.popViewController(animated: !UIAccessibility.isReduceMotionEnabled)
        } else {
            dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        }
    }
}
