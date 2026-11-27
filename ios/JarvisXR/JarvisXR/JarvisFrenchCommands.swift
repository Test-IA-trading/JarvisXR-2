import Foundation

/// Deterministic French layer in front of the English command router.
///
/// It answers the simple everyday requests natively in French, translates the French
/// wording of existing actions (camera, settings, notes…) into the canonical English
/// command so the router keeps executing them, and recognises French text it cannot
/// handle so Jarvis says so in French instead of answering with an English hint.
/// Everything runs on the iPhone; no network call is made here.
struct JarvisFrenchCommandRouter {
    enum Outcome {
        /// Jarvis answers directly in French.
        case answer(JarvisResponse)
        /// Run an existing canonical command, replacing its spoken (and optionally
        /// displayed) text with French.
        case forward(command: String, spoken: String, display: String?)
        /// Not French, or an English command: let the existing router decide.
        case notHandled
        /// French question no deterministic route can answer: it goes to the local
        /// brain (language model on the iPhone), which never runs actions.
        case openQuestion(String)
    }

    private let memory: JarvisMemoryStore
    private let scene: JarvisSpatialSceneMemory
    private let context: JarvisConversationContext
    private let screen: JarvisScreenContext
    private let timers: JarvisTimerStore
    private let profile: JarvisUserProfile
    /// Jarvis's long-term memory (the « Mémoire Jarvis » folder).
    private let knowledge: JarvisKnowledgeStore
    private let journal: JarvisConversationJournal
    private let locale = Locale(identifier: "fr_FR")

    /// Prefix of the notes created by « prépare l'essai du bilan ».
    static let trialNotePrefix = "[essai]"

    init(
        memory: JarvisMemoryStore = .shared,
        scene: JarvisSpatialSceneMemory = .shared,
        context: JarvisConversationContext = .shared,
        screen: JarvisScreenContext = .shared,
        timers: JarvisTimerStore = .shared,
        profile: JarvisUserProfile = .shared,
        knowledge: JarvisKnowledgeStore = .shared,
        journal: JarvisConversationJournal = .shared
    ) {
        self.memory = memory
        self.scene = scene
        self.context = context
        self.screen = screen
        self.timers = timers
        self.profile = profile
        self.knowledge = knowledge
        self.journal = journal
    }

    func route(_ raw: String, now: Date = Date()) -> Outcome {
        let spoken = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Free phrasing: « Est-ce que tu pourrais appeler Paul ? » is routed as « appelle Paul ? »
        // (JarvisPhrasing); an open question still reaches the brain in the user's own words.
        let original = JarvisPhrasing.rewrite(spoken)
        let text = Self.normalize(original)
        guard !text.isEmpty else { return .notHandled }

        // "Bonjour Jarvis, est-ce que tu m'entends ?" — the first sentence of the field test.
        if containsAny(text, ["tu m'entends", "vous m'entendez", "tu m'ecoutes", "tu me recois", "est ce que ca marche", "test micro", "test du micro"]) {
            return .answer(.ok(
                "Oui, je vous entends bien.",
                display: "Oui, je vous entends bien. J'ai compris : « \(spoken) »"
            ))
        }

        let withoutWakeWord = Self.stripWakeWord(text)
        if Self.greetings.contains(where: { withoutWakeWord == $0 || withoutWakeWord.hasPrefix($0 + " ") }) &&
            withoutWakeWord.split(separator: " ").count <= 3 {
            return .answer(.ok(profile.name.map { "Bonjour \($0) ! Je vous écoute." } ?? "Bonjour ! Je vous écoute."))
        }
        let request = withoutWakeWord

        // A deletion asked for earlier waits for « Je confirme » (JarvisConfirmations).
        if let reply = confirmationAnswer(request) {
            return .answer(reply)
        }

        // What Jarvis knows about the person: the first name, and a summary of what it remembers.
        if let reply = profileAnswer(original: original, normalized: text, request: request) {
            return .answer(reply)
        }

        // Jarvis's own memory: where it is, what it holds, a search in it, the conversations kept.
        if let reply = memoryAnswer(original: original, normalized: text, request: request) {
            return .answer(reply)
        }

        // « Voix plus grave », « plus aiguë », « voix normale »: Jarvis's own voice (§23).
        if let reply = voicePitchAnswer(request) {
            return .answer(reply)
        }

        // « Lance le raccourci Mode nuit »: the user's Shortcuts do what iOS keeps from apps
        // (Wi-Fi, luminosité, concentration, domotique).
        if let reply = shortcutRequest(original: original, normalized: text) {
            return .answer(reply)
        }

        // Jarvis PC: « Sur le PC, ouvre Spotify », « Dis sur le PC que le dîner est prêt ».
        if let reply = pcRequest(original: original, normalized: text, request: request) {
            return .answer(reply)
        }

        // Which voice speaks: Jarvis's own (on the iPhone), the PC's, or the iPhone's system voice.
        if containsAny(request, ["installe ta voix", "installe la voix de jarvis", "telecharge ta voix", "telecharge la voix de jarvis"]) {
            return .answer(.ok("J'installe ma voix sur l'iPhone : 77 Mo, une seule fois.", data: ["action": "install_voice"]))
        }
        if containsAny(request, ["utilise ta voix", "reprends ta voix", "voix de jarvis", "ta vraie voix"]) {
            JarvisLocalVoice.isEnabled = true
            JarvisPCVoice.isEnabled = true
            return .answer(JarvisLocalVoice.shared.isInstalled
                ? .ok("Très bien, Monsieur. Je reprends ma voix.", data: ["mode": "jarvis_voice"])
                : .ok("Ma voix n'est pas encore installée sur l'iPhone. Je l'installe : 77 Mo, une seule fois.", data: ["action": "install_voice"]))
        }
        if containsAny(request, ["utilise la voix du pc", "prends la voix du pc", "parle avec la voix du pc", "voix du pc"]) {
            JarvisLocalVoice.isEnabled = false
            JarvisPCVoice.isEnabled = true
            return .answer(.ok("Entendu. Je parlerai avec la voix du PC dès qu'il est joignable.", data: ["mode": "pc_voice"]))
        }
        if containsAny(request, ["utilise la voix de l'iphone", "prends la voix de l'iphone", "voix de l'iphone", "voix du telephone", "voix d'apple"]) {
            JarvisLocalVoice.isEnabled = false
            JarvisPCVoice.isEnabled = false
            return .answer(.ok("Très bien. Je parlerai avec la voix de l'iPhone.", data: ["mode": "iphone_voice"]))
        }

        // « Ouvre WhatsApp », « Lance Spotify »: an app of the iPhone, by its public address.
        if let reply = appRequest(request) {
            return .answer(reply)
        }

        // Hands-free conversation controls.
        if containsAny(request, ["c'est tout", "ca sera tout", "ce sera tout", "fin de la conversation", "arrete la conversation", "arrete d'ecouter", "stop conversation", "termine la conversation"]) {
            return .answer(.ok("Très bien. Touchez l'orbe quand vous voudrez reprendre.", data: ["mode": "conversation_end"]))
        }
        if containsAny(request, ["desactive la conversation continue", "coupe la conversation continue", "conversation continue desactivee"]) {
            JarvisConversationSettings.isContinuous = false
            return .answer(.ok("Conversation continue désactivée : touchez l'orbe à chaque question.", data: ["mode": "conversation_off"]))
        }
        if containsAny(request, ["conversation continue", "mode conversation", "active la conversation"]) {
            JarvisConversationSettings.isContinuous = true
            return .answer(.ok("Conversation continue activée : après chaque réponse, je vous écoute à nouveau.", data: ["mode": "conversation_on"]))
        }

        if containsAny(request, ["merci"]) && request.split(separator: " ").count <= 4 {
            return .answer(.ok("Avec plaisir."))
        }

        // Context of the JARVIS screen: the option the user touched last.
        if containsAny(request, ["suspends l'assistance", "suspend l'assistance", "mets l'assistance en pause", "pause de l'assistance", "desactive l'assistance"]) {
            screen.setAssistanceEnabled(false)
            return .answer(.ok("Assistance contextuelle suspendue : je ne suis plus vos sélections.", data: ["mode": "screen_assistance_off"]))
        }
        if containsAny(request, ["reprends l'assistance", "reprend l'assistance", "reactive l'assistance", "active l'assistance"]) {
            screen.setAssistanceEnabled(true)
            return .answer(.ok("Assistance contextuelle reprise : touchez une option puis demandez-moi.", data: ["mode": "screen_assistance_on"]))
        }
        if containsAny(request, [
            "a quoi sert cette option", "a quoi sert ce reglage", "a quoi ca sert", "a quoi sert ce bouton",
            "c'est quoi cette option", "c'est quoi ce reglage", "explique cette option", "explique ce reglage",
            "et celle ci", "et celui ci", "et cette option", "et ce reglage", "et celle la", "et celui la"
        ]) {
            let reply = screen.answerAboutSelection()
            return .answer(.ok(reply))
        }

        // Facts stated during the conversation (« le train part à 9 h… lequel part en
        // premier ? »), corrections and follow-up questions. Checked before the clock so
        // « juste l'heure du train » is not answered with the current time.
        let isNoteDictation = Self.notePrefixes.contains { request == $0 || request.hasPrefix($0 + " ") }

        // Connected mode (Réglages › Internet): weather, news, « Où suis-je ? », « Ma ville est… ».
        if !isNoteDictation, let reply = internetAnswer(original: original, normalized: text, request: request) {
            return .answer(reply)
        }

        // The iPhone's own data: « Appelle Paul », « Combien de pas aujourd'hui ? », « Montre-moi ma dernière photo ».
        if !isNoteDictation, let reply = deviceAnswer(original: original, normalized: text, request: request) {
            return .answer(reply)
        }

        if !isNoteDictation, let reply = context.respond(to: request) {
            return .answer(.ok(reply))
        }

        // Timers, reminders, agenda and briefing (side effects run in JarvisLifeActionPerformer).
        if !isNoteDictation, let life = lifeAnswer(request: request, original: original, now: now) {
            return .answer(life)
        }

        // Activity summary of the notes Jarvis stores.
        if !isNoteDictation, let notesAnswer = notesSummaryAnswer(request, now: now) {
            return .answer(notesAnswer)
        }

        // Calculations get an exact answer instead of a language model's estimate:
        // « Combien font 128 fois 46 ? », « Intégrale de 0 à 1 de x au carré ».
        if !isNoteDictation, let math = JarvisMathSolver.answer(to: original) {
            return .answer(.ok(math.spoken, display: math.display))
        }

        // Conversions and date questions, before « quel jour » takes « Quel jour serons-nous
        // dans 3 jours ? » for today's date.
        if !isNoteDictation, let everyday = JarvisUnitConverter.answer(to: original) ?? JarvisDateAnswers.answer(to: original, now: now) {
            return .answer(.ok(everyday.spoken, display: everyday.display))
        }

        if containsAny(request, ["quelle heure", "l'heure", "il est quelle heure"]) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "H 'h' mm"
            return .answer(.ok("Il est \(formatter.string(from: now))."))
        }

        if containsAny(request, ["quel jour", "quelle date", "on est le combien", "la date", "date d'aujourd'hui"]) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "EEEE d MMMM yyyy"
            return .answer(.ok("Nous sommes le \(formatter.string(from: now))."))
        }

        if request == "aide" || containsAny(request, ["que sais tu faire", "qu'est ce que tu sais faire", "que peux tu faire", "qu'est ce que tu peux faire", "liste des commandes", "quelles commandes"]) {
            return .answer(.ok(
                "Je peux lancer des minuteurs, créer des rappels, lire votre agenda, faire le point, retenir des horaires, compter vos notes, faire des calculs exacts, dérivées et intégrales comprises, poser un cube ou un bilan en réalité augmentée, donner la météo, les titres et des réponses de Wikipédia en mode connecté, appeler ou écrire à vos contacts, compter vos pas et vos photos, piloter votre PC, et répondre à vos questions avec le cerveau local.",
                display: "Essayez : « Minuteur pâtes 10 minutes », « Rappelle-moi d'appeler maman demain à 18 h », « Qu'est-ce que j'ai demain ? », « Fais-moi le point », « Quel temps fait-il demain ? », « Les titres du jour », « Qui est Marie Curie ? », « Appelle Paul », « Combien de pas aujourd'hui ? », « Montre-moi ma dernière photo », « Sur le PC, ouvre Spotify », « Combien font 128 fois 46 ? », « Intégrale de 0 à 1 de x au carré », « Le train part à 9 h et le bus à 11 h. Lequel part en premier ? », « Combien de notes ai-je prises ces sept derniers jours ? », « Montre-les-moi », « Pose ce bilan sur la table », « Ouvre le cube », « Qu'est-ce que je viens de déplacer ? », « Quelle heure est-il ? », « Prends une note… », « Lis ce texte », « C'est tout »."
            ))
        }

        // Notes, answered natively so the reply stays French.
        for prefix in Self.notePrefixes {
            // The full normalized text, so a wake word (« Jarvis, prends une note… ») is skipped.
            if let body = Self.argument(in: original, normalized: text, after: prefix) {
                guard !body.isEmpty else {
                    return .answer(JarvisResponse(status: .refused, spokenResponse: "Que dois-je noter ?", displayResponse: "Dites par exemple : « Prends une note acheter du pain ».", shouldSpeak: true))
                }
                let note = memory.saveNote(body)
                // « Souviens-toi que… » is also a memory of Jarvis: in its folder (Obsidian) and on the PC.
                if ["souviens toi que", "retiens que", "rappelle toi que"].contains(prefix) {
                    let sentence = body.prefix(1).uppercased() + body.dropFirst()
                    knowledge.remember(sentence.hasSuffix(".") ? sentence : sentence + ".", kind: "fait", source: "note")
                }
                return .answer(.ok("C'est noté.", display: "Note enregistrée : \(note.text)"))
            }
        }
        if containsAny(request, ["mes notes", "les notes", "montre les notes", "affiche les notes", "lis mes notes", "liste des notes"]) {
            let notes = memory.loadNotes()
            guard !notes.isEmpty else {
                return .answer(.ok("Vous n'avez aucune note.", display: "Aucune note enregistrée."))
            }
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "d MMM HH:mm"
            let lines = notes.enumerated().map { "\($0.offset + 1). [\(formatter.string(from: $0.element.createdAt))] \($0.element.text)" }
            let count = notes.count == 1 ? "une note" : "\(notes.count) notes"
            return .answer(.ok("Vous avez \(count).", display: lines.joined(separator: "\n")))
        }

        // The scene engine knows which virtual entity was moved: answer from that fact.
        if containsAny(request, [
            "qu'est ce que je viens de deplacer", "qu'est ce que j'ai deplace", "qu'ai je deplace",
            "j'ai deplace quoi", "je viens de deplacer quoi", "quel objet j'ai deplace", "quel objet je viens de deplacer",
            "qu'est ce que je viens de bouger", "qu'est ce que j'ai bouge"
        ]) {
            let answer = scene.answerWhatWasMoved()
            return .answer(.ok(answer.spoken, display: answer.display))
        }

        if containsAny(request, ["realite augmentee", "cube"]) &&
            (containsAny(request, ["ouvre", "lance", "montre", "affiche", "mode", "active", "demarre"]) || request == "cube" || request == "le cube") {
            return .answer(.ok(
                "J'ouvre le cube en réalité augmentée.",
                display: "Cube AR : cadrez une table, puis pincez le cube entre le pouce et l'index pour le déplacer.",
                data: ["action": "ar_cube"]
            ))
        }

        // Existing actions, executed by the canonical English router.
        if let action = Self.translateAction(request) {
            // On the home screen a bare "stop" means "stop talking".
            let command = action.command == "stop" ? "stop speaking" : action.command
            return .forward(command: command, spoken: action.spoken, display: action.display)
        }

        if containsAny(request, ["cerveau local", "cerveau", "modele de langage"]) &&
            containsAny(request, ["installe", "telecharge", "active", "ouvre", "configure"]) {
            return .answer(.ok(
                "J'ouvre les réglages : le cerveau local se télécharge dans la section Cerveau local.",
                display: "Réglages › Cerveau local : téléchargement unique de 1,1 Go, puis réponses aux questions libres sans Internet.",
                data: ["action": "settings"]
            ))
        }

        guard Self.looksFrench(text) else { return .notHandled }
        // The brain hears the user's own words, not the rewording made for the commands.
        return .openQuestion(spoken)
    }

    // MARK: Apps of the iPhone

    /// Apps iOS lets another app open, by their public address (names said, normalized).
    /// iOS opens nothing that is not installed: the screen then says so.
    static let appAddresses: [(names: [String], label: String, url: String)] = [
        (["youtube"], "YouTube", "youtube://"), (["spotify"], "Spotify", "spotify://"), (["deezer"], "Deezer", "deezer://"),
        (["whatsapp", "whats app"], "WhatsApp", "whatsapp://"), (["instagram", "insta"], "Instagram", "instagram://"),
        (["facebook"], "Facebook", "fb://"), (["messenger"], "Messenger", "fb-messenger://"), (["snapchat", "snap"], "Snapchat", "snapchat://"),
        (["tiktok", "tik tok"], "TikTok", "tiktok://"), (["netflix"], "Netflix", "nflx://"), (["telegram"], "Telegram", "tg://"),
        (["twitter", "x"], "X", "twitter://"), (["discord"], "Discord", "discord://"), (["twitch"], "Twitch", "twitch://"),
        (["linkedin"], "LinkedIn", "linkedin://"), (["pinterest"], "Pinterest", "pinterest://"), (["reddit"], "Reddit", "reddit://"),
        (["waze"], "Waze", "waze://"), (["google maps"], "Google Maps", "comgooglemaps://"), (["plans", "apple plans", "cartes"], "Plans", "maps://"),
        (["gmail"], "Gmail", "googlegmail://"), (["mail", "mails", "mes mails", "la messagerie"], "Mail", "message://"),
        (["messages", "imessage"], "Messages", "sms:"), (["calendrier", "agenda"], "Calendrier", "calshow://"),
        (["rappels"], "Rappels", "x-apple-reminderkit://"), (["apple notes", "l'app notes", "application notes"], "Notes", "mobilenotes://"),
        (["musique", "apple music"], "Musique", "music://"), (["podcasts"], "Podcasts", "podcasts://"), (["app store"], "App Store", "itms-apps://"),
        (["photos", "galerie"], "Photos", "photos-redirect://"), (["meteo", "l'app meteo"], "Météo", "weather://"),
        (["horloge", "reveil", "alarmes"], "Horloge", "clock-alarm://"), (["chrome", "google chrome"], "Chrome", "googlechrome://"),
        (["shazam"], "Shazam", "shazam://"), (["uber"], "Uber", "uber://"), (["prime video"], "Prime Video", "aiv://"),
        (["disney", "disney plus", "disney+"], "Disney+", "disneyplus://"), (["raccourcis"], "Raccourcis", "shortcuts://"),
        (["reglages de jarvis", "reglages de l'app"], "Réglages de Jarvis", "app-settings:"),
    ]

    private static let appVerbs = ["ouvre moi", "lance moi", "ouvre", "lance", "demarre", "va sur"]

    func appRequest(_ request: String) -> JarvisResponse? {
        for verb in Self.appVerbs where request.hasPrefix(verb + " ") {
            var name = String(request.dropFirst(verb.count + 1))
            for article in ["l'application ", "l'app ", "application ", "app ", "le ", "la ", "les ", "mon ", "ma ", "mes "] where name.hasPrefix(article) {
                name = String(name.dropFirst(article.count))
                break
            }
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ?!."))
            guard let app = Self.appAddresses.first(where: { $0.names.contains(name) }) else { return nil }
            return .ok("J'ouvre \(app.label).", display: "Ouverture de \(app.label).", data: ["url_scheme": app.url, "action": "open_app"])
        }
        return nil
    }

    // MARK: Shortcuts

    private static let assistantShortcuts: [(String, String)] = [
        ("demande a chatgpt", "ChatGPT"), ("demande a chat gpt", "ChatGPT"), ("demande a claude", "Claude"), ("demande a gemini", "Gemini"),
    ]

    private static let shortcutPrefixes = [
        "lance le raccourci", "execute le raccourci", "demarre le raccourci", "active le raccourci", "ouvre le raccourci",
        "lance mon raccourci", "execute mon raccourci", "lancer le raccourci", "raccourci",
    ]

    /// Runs one of the user's Shortcuts by its name, through the Shortcuts app (iOS asks
    /// the first time). Nothing else is reachable: iOS keeps its settings from apps.
    func shortcutRequest(original: String, normalized: String) -> JarvisResponse? {
        // « Demande à ChatGPT pourquoi… »: the official app's action, in the user's Shortcut
        // « Demander à ChatGPT » (free with their own account; no key, nothing paid here).
        for (prefix, assistant) in Self.assistantShortcuts {
            guard let question = Self.argument(in: original, normalized: normalized, after: prefix)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " «»\"'")), !question.isEmpty else { continue }
            let name = "Demander à \(assistant)"
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: name), URLQueryItem(name: "input", value: "text"), URLQueryItem(name: "text", value: question)]
            guard let url = components.url?.absoluteString else { return nil }
            return .ok("Je pose la question à \(assistant).",
                       display: "Raccourci « \(name) » lancé avec : « \(question) ». Créez-le une fois dans Raccourcis avec l'action de l'app \(assistant), puis « Énoncer le texte ».",
                       data: ["url_scheme": url, "action": "shortcut"])
        }
        for prefix in Self.shortcutPrefixes {
            guard let name = Self.argument(in: original, normalized: normalized, after: prefix)?
                .trimmingCharacters(in: CharacterSet(charactersIn: " «»\"'?!.")), !name.isEmpty else { continue }
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: name)]
            guard let url = components.url?.absoluteString else { return nil }
            return .ok("Je lance le raccourci « \(name) ».", display: "Raccourci « \(name) » lancé dans l'app Raccourcis.", data: ["url_scheme": url, "action": "shortcut"])
        }
        return nil
    }

    // MARK: The iPhone's own data

    /// Calls, messages, numbers, steps and photos, run by JarvisLifeActionPerformer.
    private func deviceAnswer(original: String, normalized: String, request: String) -> JarvisResponse? {
        guard let wanted = JarvisDeviceRequest.parse(original: original, normalized: normalized, request: request) else { return nil }
        switch wanted {
        case .call(let name):
            return .ok("J'appelle \(name).", data: ["action": "phone_call", "name": name])
        case .message(let name, let body):
            var data = ["action": "phone_message", "name": name]
            if let body { data["body"] = body }
            return .ok("Je prépare le message pour \(name).", data: data)
        case .phoneNumber(let name):
            return .ok("Je cherche le numéro de \(name).", data: ["action": "phone_number", "name": name])
        case .steps(let period):
            return .ok("Je compte vos pas.", data: ["action": "steps", "period": period.rawValue])
        case .photoCount(let period):
            return .ok("Je compte vos photos.", data: ["action": "photos_count", "period": period.rawValue])
        case .showPhotos(let period, let latestOnly):
            return .ok("Je cherche vos photos.", data: ["action": "photos_show", "period": period.rawValue, "latest": latestOnly ? "1" : "0"])
        }
    }

    // MARK: Internet (connected mode)

    /// Weather, news and « Où suis-je ? » (run by JarvisLifeActionPerformer), « Ma ville est… ».
    private func internetAnswer(original: String, normalized: String, request: String) -> JarvisResponse? {
        guard let wanted = JarvisInternetRequest.parse(original: original, normalized: normalized, request: request) else { return nil }
        if case .setCity(let city) = wanted {
            JarvisInternetSettings.city = city
            if JarvisInternetSettings.isEnabled {
                return .ok("C'est noté : je donnerai la météo de \(city).")
            }
            return .ok("C'est noté : \(city). Pour la météo, activez le mode connecté dans Réglages › Internet.")
        }
        guard JarvisInternetSettings.isEnabled else {
            // The paired PC has Internet: it gives the weather and the news.
            if wanted != .whereAmI, JarvisPCLink.shared.isConfigured {
                let command = Self.stripWakeWordPrefix(original).trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?"))
                return .ok("Je demande au PC.", display: "Pour le PC : « \(command) »", data: ["action": "pc_command", "text": command])
            }
            let message = JarvisInternetFailure.disabled.message
            return JarvisResponse(status: .unavailable, spokenResponse: message, displayResponse: message)
        }
        switch wanted {
        case .weather(let city, let dayOffset):
            var data = ["action": "web_weather", "day_offset": String(dayOffset)]
            if let city { data["city"] = city }
            return .ok("Je regarde la météo.", data: data)
        case .news:
            return .ok("Je regarde les titres.", data: ["action": "web_news"])
        case .whereAmI:
            return .ok("Je regarde où nous sommes.", data: ["action": "where_am_i"])
        case .setCity:
            return nil
        }
    }

    // MARK: Jarvis PC

    private static let pcSayPrefixes = ["dis sur le pc", "dis sur mon pc", "annonce sur le pc", "annonce sur mon pc"]
    private static let pcCommandPrefixes = [
        "sur le pc", "sur mon pc", "demande au pc de", "demande au pc", "demande a mon pc de", "demande a mon pc",
        "sur l'ordinateur", "sur l'ordi",
    ]

    /// A request for the user's PC, run there by Jarvis PC (JarvisLifeActionPerformer).
    private func pcRequest(original: String, normalized: String, request: String) -> JarvisResponse? {
        for prefix in Self.pcSayPrefixes {
            guard let body = Self.argument(in: original, normalized: normalized, after: prefix) else { continue }
            // « que le dîner est prêt », « qu'il pleut » — but « quelqu'un » stays whole.
            let text = body.replacingOccurrences(of: "^(que\\s+|qu['’]\\s*)", with: "", options: [.regularExpression, .caseInsensitive])
            guard !text.isEmpty else { return .ok("Que dois-je dire sur le PC ?") }
            return .ok("Je le dis sur le PC.", display: "Sur le PC : « \(text) »", data: ["action": "pc_say", "text": text])
        }
        var body: String?
        for prefix in Self.pcCommandPrefixes {
            if let found = Self.argument(in: original, normalized: normalized, after: prefix) {
                body = found
                break
            }
        }
        // « Ouvre Spotify sur le PC »: the same, said the other way round.
        let pcVerbs: Set<String> = ["ouvre", "lance", "demarre", "cherche", "recherche", "mets", "joue", "ferme", "affiche", "montre", "eteins"]
        if body == nil, request.hasSuffix(" sur le pc") || request.hasSuffix(" sur mon pc"),
           let verb = request.split(separator: " ").first, pcVerbs.contains(String(verb)) {
            body = Self.stripWakeWordPrefix(original)
                .replacingOccurrences(of: "\\s+sur\\s+(le|mon)\\s+pc\\s*[.!?]*$", with: "", options: [.regularExpression, .caseInsensitive])
        }
        guard let body else { return nil }
        let command = body.trimmingCharacters(in: CharacterSet(charactersIn: " ,.:;!?"))
        guard !command.isEmpty else { return .ok("Que dois-je demander au PC ?") }
        return .ok("Je demande au PC.", display: "Pour le PC : « \(command) »", data: ["action": "pc_command", "text": command])
    }

    /// The original wording without a leading « Jarvis, ».
    private static func stripWakeWordPrefix(_ original: String) -> String {
        original.replacingOccurrences(of: "^\\s*((dis|hey|ok|okay|eh)\\s+)?jarvis[\\s,.:;!?]*", with: "", options: [.regularExpression, .caseInsensitive])
    }

    // MARK: What Jarvis knows about the person

    private static let namePrefixes = [
        "je m'appelle", "appelle moi", "tu peux m'appeler", "vous pouvez m'appeler",
        "mon prenom est", "mon prenom c'est", "mon nom est", "mon nom c'est",
    ]

    private func profileAnswer(original: String, normalized: String, request: String) -> JarvisResponse? {
        if containsAny(request, [
            "comment je m'appelle", "je m'appelle comment", "quel est mon nom", "quel est mon prenom", "c'est quoi mon nom",
            "c'est quoi mon prenom", "tu connais mon nom", "tu connais mon prenom", "tu sais comment je m'appelle",
        ]) {
            guard let name = profile.name else {
                return .ok("Je ne connais pas encore votre prénom. Dites par exemple : « Je m'appelle Tony ».")
            }
            return .ok("Vous vous appelez \(name).")
        }
        // « Oublie que j'aime le café »: a memory of Jarvis is deleted, here and on the PC.
        for prefix in ["oublie que", "efface de ta memoire que", "oublie ce que je t'ai dit sur"] {
            guard let what = Self.argument(in: original, normalized: normalized, after: prefix), !what.isEmpty else { continue }
            if let removed = JarvisKnowledgeStore.shared.forget(what) {
                return .ok("C'est oublié : \(removed.text)", data: ["mode": "memory_forget"])
            }
            return .ok("Je n'ai rien retenu de tel, Monsieur.", data: ["mode": "memory_forget"])
        }
        if containsAny(request, ["oublie mon nom", "oublie mon prenom", "efface mon nom", "efface mon prenom"]) {
            profile.name = nil
            return .ok("C'est oublié : je ne vous appellerai plus par votre prénom.", data: ["mode": "profile_name_forgotten"])
        }
        if containsAny(request, [
            "qu'est ce que tu sais sur moi", "qu'est ce que tu sais de moi", "que sais tu sur moi", "que sais tu de moi",
            "ce que tu sais sur moi", "ce que tu sais de moi", "tu sais quoi sur moi", "qu'est ce que tu connais de moi",
        ]) {
            return knownFactsAnswer()
        }
        for prefix in Self.namePrefixes {
            guard let raw = Self.argument(in: original, normalized: normalized, after: prefix) else { continue }
            guard let name = JarvisUserProfile.cleanedName(raw) else { return nil }
            profile.name = name
            return .ok("Enchanté, \(name). Je m'en souviendrai.", data: ["mode": "profile_name"])
        }
        return nil
    }

    /// « Qu'est-ce que tu sais sur moi ? »: the name, the latest notes and what Jarvis learned
    /// by itself (its « Mémoire Jarvis » folder), all kept on the iPhone.
    private func knownFactsAnswer() -> JarvisResponse {
        let notes = memory.loadNotes().filter { !$0.text.hasPrefix(Self.trialNotePrefix) }
        // « Souviens-toi que… » copies (source « note ») are already among the notes.
        let learned = knowledge.notes.filter { JarvisKnowledgeStore.durableKinds.contains($0.kind) && $0.source != "note" }
        var spoken: [String] = []
        if let name = profile.name {
            spoken.append("Vous vous appelez \(name).")
        }
        if !learned.isEmpty {
            let items = learned.prefix(4).map { JarvisKnowledgeStore.spokenToUser($0.text) }.joined(separator: " ; ")
            spoken.append("Ce que j'ai appris de vous : \(items).")
        }
        guard !notes.isEmpty else {
            if !learned.isEmpty {
                let list = learned.prefix(10).enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
                return .ok(spoken.joined(separator: " "), display: spoken.joined(separator: " ") + "\n" + list, data: ["memory": "known_facts"])
            }
            spoken.append(profile.name == nil
                ? "Je ne sais encore rien de vous. Dites « Je m'appelle… » ou « Souviens-toi que… » : je m'en souviendrai, ici sur l'iPhone."
                : "Vous ne m'avez encore rien demandé de retenir : dites « Souviens-toi que… ».")
            return .ok(spoken.joined(separator: " "))
        }
        let latest = notes.prefix(3).map(\.text).joined(separator: " ; ")
        if notes.count == 1 {
            spoken.append("Vous m'avez demandé de retenir une chose : \(latest).")
        } else if notes.count <= 3 {
            spoken.append("Vous m'avez demandé de retenir \(notes.count) choses : \(latest).")
        } else {
            spoken.append("Vous m'avez demandé de retenir \(notes.count) choses. Les plus récentes : \(latest).")
        }
        let list = notes.prefix(10).enumerated().map { "\($0.offset + 1). \($0.element.text)" }.joined(separator: "\n")
        return .ok(spoken.joined(separator: " "), display: spoken.joined(separator: " ") + "\n" + list)
    }

    // MARK: Jarvis's memory itself (docs/VISION_JARVIS.md §8: a real memory, not a mention in a prompt)

    private static let memoryOverviewPhrases = [
        "acces a ta memoire", "acces a tes souvenirs", "acces a obsidian", "acces a mon obsidian", "acces a ton obsidian", "acces a ta memoire obsidian",
        "tu as une memoire", "as tu une memoire", "est ce que tu as une memoire", "ou est ta memoire", "ou sont tes souvenirs", "ou est ton obsidian",
        "que contient ta memoire", "qu'y a t il dans ta memoire", "qu'est ce qu'il y a dans ta memoire", "qu'est ce que contient ta memoire",
        "montre ta memoire", "montre moi ta memoire", "affiche ta memoire", "liste tes souvenirs", "montre tes souvenirs", "combien de souvenirs",
        "ta memoire obsidian", "ta memoire fonctionne", "est ce que ta memoire marche", "tu te souviens de quoi", "de quoi tu te souviens",
    ]
    /// Asked of the memory itself: answered even when it holds nothing.
    private static let memorySearchPrefixes = [
        "cherche dans ta memoire", "regarde dans ta memoire", "est ce que tu te souviens de", "est ce que tu te souviens du",
        "tu te souviens de", "tu te souviens du", "te souviens tu de", "te souviens tu du", "qu'as tu retenu sur",
        "qu'est ce que tu as retenu sur", "qu'est ce que tu as retenu de",
    ]
    /// « Que sais-tu de ma sœur ? » (JarvisPhrasing writes it « parle-moi de ma sœur »): about the
    /// person's own world, answered from the memory when it holds something; « parle-moi de la
    /// photosynthèse » stays a question for the brain (which still gets the relevant memories).
    private static let knowledgeSearchPrefixes = ["parle moi de", "parle moi du", "parle moi des"]
    private static let possessives = ["ma ", "mon ", "mes ", "notre ", "nos "]

    private func memoryAnswer(original: String, normalized: String, request: String) -> JarvisResponse? {
        // The complete reset (§17.2), only after « Je confirme ».
        if containsAny(request, ["reinitialise ta memoire", "reinitialise completement ta memoire", "efface toute ta memoire", "vide ta memoire",
                                 "efface tout ce que tu sais", "oublie tout ce que tu sais", "reinitialisation complete", "remets ta memoire a zero",
                                 "remise a zero de ta memoire"]) || request == "oublie tout" {
            let profile = self.profile, memory = self.memory, knowledge = self.knowledge, journal = self.journal, context = self.context
            return JarvisConfirmations.shared.ask("effacer toute ma mémoire sur cet iPhone (souvenirs, réponses mémorisées, conversations, notes et votre prénom)") {
                JarvisReset.eraseEverythingLearned(knowledge: knowledge, journal: journal, memory: memory, profile: profile, conversation: context)
            }
        }
        if containsAny(request, ["ne garde plus nos conversations", "arrete de garder nos conversations", "n'enregistre plus nos conversations",
                                 "arrete d'enregistrer nos conversations", "ne garde pas nos conversations"]) {
            journal.isEnabled = false
            return .ok("Entendu : je ne garde plus nos conversations. Ce qui est déjà gardé reste, jusqu'à ce que vous demandiez de l'effacer.",
                       data: ["memory": "journal_off"])
        }
        if containsAny(request, ["garde nos conversations", "enregistre nos conversations", "garde l'historique des conversations"]) {
            journal.isEnabled = true
            return .ok("Entendu : je garde de nouveau nos conversations, ici sur l'iPhone, dans le dossier « Mémoire Jarvis ».", data: ["memory": "journal_on"])
        }
        if containsAny(request, ["efface l'historique des conversations", "efface nos conversations", "supprime nos conversations",
                                 "efface l'historique de nos conversations", "supprime l'historique des conversations"]) {
            let pages = journal.days().count
            guard pages > 0 else { return .ok("Aucune conversation n'est gardée sur l'iPhone.", data: ["memory": "journal_empty"]) }
            let journal = self.journal
            return JarvisConfirmations.shared.ask(
                "effacer l'historique des conversations (\(pages) jour\(pages > 1 ? "s" : ""))"
            ) {
                let erased = journal.eraseAll()
                return "C'est effacé : \(erased) jour\(erased > 1 ? "s" : "") de conversations."
            }
        }
        if containsAny(request, Self.memoryOverviewPhrases) {
            return memoryOverview()
        }
        for (prefixes, always) in [(Self.memorySearchPrefixes, true), (Self.knowledgeSearchPrefixes, false)] {
            for prefix in prefixes {
                guard let subject = Self.argument(in: original, normalized: normalized, after: prefix), !subject.isEmpty else { continue }
                let folded = Self.normalize(subject)
                // « sur moi » is the profile's answer; « de ça », « de ce que » follow the conversation.
                guard !["moi", "moi meme", "ca", "cela"].contains(folded), !folded.hasPrefix("ce que"), !folded.hasPrefix("ce qu'") else { return nil }
                guard always || Self.possessives.contains(where: { folded.hasPrefix($0) }) else { return nil }
                return memorySearch(subject, always: always)
            }
        }
        return nil
    }

    /// Where the memory is and what it holds, with what was really counted in it.
    private func memoryOverview() -> JarvisResponse {
        let inventory = knowledge.inventory()
        let place = "dans le dossier « Mémoire Jarvis » de l'iPhone (app Fichiers, Sur mon iPhone, JARVIS), une note Markdown par souvenir, lisible dans Obsidian"
        let journalPages = journal.days().count
        let journalLine = journal.isEnabled
            ? (journalPages > 0 ? " Je garde aussi nos conversations : \(journalPages) jour\(journalPages > 1 ? "s" : "")." : " Je garde aussi nos conversations à partir de maintenant.")
            : " Je ne garde pas nos conversations (vous l'avez demandé)."
        guard inventory.count > 0 else {
            let spoken = "Oui, Monsieur : ma mémoire est en place, \(place), mais elle ne contient encore aucun souvenir. Dites par exemple « Je préfère les réponses courtes » ou « Souviens-toi que… »." + journalLine
            return .ok(spoken, data: ["memory": "overview", "memory_count": "0"])
        }
        let kept = inventory.kept > 0 ? ", plus \(inventory.kept) réponse\(inventory.kept > 1 ? "s" : "") mémorisée\(inventory.kept > 1 ? "s" : "") pour répondre plus vite" : ""
        let recent = knowledge.notes.filter { JarvisKnowledgeStore.durableKinds.contains($0.kind) }
        let latest = recent.prefix(2).map { JarvisKnowledgeStore.spokenToUser($0.text) }.joined(separator: " ; ")
        let spoken = "Oui, Monsieur : ma mémoire est \(place). Elle contient \(inventory.count) souvenir\(inventory.count > 1 ? "s" : "") (\(inventory.words))\(kept). Les plus récents : \(latest).\(journalLine)"
        let list = recent.prefix(12).enumerated().map { "\($0.offset + 1). [\(JarvisKnowledgeStore.labels[$0.element.kind] ?? $0.element.kind)] \($0.element.text)" }.joined(separator: "\n")
        return .ok(spoken, display: spoken + "\n" + list, data: ["memory": "overview", "memory_count": "\(inventory.count)"])
    }

    /// « Tu te souviens de ma sœur ? »: a real search in the memory, said with what was found.
    /// `always`: the question is about the memory itself, so « nothing » is the answer too.
    private func memorySearch(_ subject: String, always: Bool) -> JarvisResponse? {
        let kinds = always ? Set(JarvisKnowledgeStore.labels.keys) : JarvisKnowledgeStore.durableKinds
        let found = knowledge.relevant(to: subject, limit: 3, kinds: kinds)
        guard !found.isEmpty else {
            guard always else { return nil }
            return .ok("Ma mémoire ne contient rien sur « \(subject) », Monsieur.", data: ["memory": "search", "memory_found": "0"])
        }
        let items = found.map { $0.kind == "reponse" ? $0.text : JarvisKnowledgeStore.spokenToUser($0.text) }
        let spoken = "Voici ce que ma mémoire contient à ce sujet : " + items.joined(separator: " ; ") + "."
        let display = spoken + "\n" + found.map { "• [\(JarvisKnowledgeStore.labels[$0.kind] ?? $0.kind), \(JarvisKnowledgeStore.day($0.updated))] \($0.text)" }.joined(separator: "\n")
        return .ok(spoken, display: display, data: ["memory": "search", "memory_found": "\(found.count)"])
    }

    /// The pitch of Jarvis's own voice, one semitone at a time, within what keeps it natural.
    private func voicePitchAnswer(_ request: String) -> JarvisResponse? {
        let step: Double
        if containsAny(request, ["voix plus grave", "parle plus grave", "prends une voix plus grave", "voix moins aigue", "parle moins aigu"]) {
            step = -1
        } else if containsAny(request, ["voix plus aigue", "parle plus aigu", "voix moins grave", "parle moins grave"]) {
            step = 1
        } else if containsAny(request, ["voix normale", "reprends ta voix normale", "ta voix par defaut", "ta voix habituelle"]) {
            JarvisLocalVoice.pitchSemitones = JarvisLocalVoice.defaultPitch
            return .ok("Voici ma voix habituelle, Monsieur.", data: ["voice": "pitch"])
        } else {
            return nil
        }
        guard JarvisLocalVoice.shared.isInstalled else {
            return .ok("Ce réglage concerne ma propre voix, qui n'est pas encore installée sur l'iPhone. Dites « installe ta voix ».", data: ["voice": "pitch"])
        }
        let before = JarvisLocalVoice.pitchSemitones
        JarvisLocalVoice.pitchSemitones = before + step
        guard JarvisLocalVoice.pitchSemitones != before else {
            return .ok(step < 0 ? "Plus grave, ma voix perdrait en naturel, Monsieur." : "Plus aiguë, ma voix perdrait en naturel, Monsieur.", data: ["voice": "pitch"])
        }
        return .ok(step < 0 ? "Comme ceci, plus grave ?" : "Comme ceci, un peu plus haut ?", data: ["voice": "pitch"])
    }

    /// « Je confirme » runs the deletion asked for less than a minute ago; « non » cancels it.
    private func confirmationAnswer(_ request: String) -> JarvisResponse? {
        guard JarvisConfirmations.shared.isWaiting else { return nil }
        if ["je confirme", "confirme", "oui je confirme", "oui confirme", "oui efface", "oui efface tout", "confirmer", "c'est confirme"].contains(request) {
            guard let done = JarvisConfirmations.shared.confirm() else {
                return .ok("Le délai de confirmation est passé : rien n'a été effacé. Redemandez si vous le souhaitez.")
            }
            return .ok(done, data: ["confirmation": "done"])
        }
        if ["non", "annule", "non annule", "laisse tomber", "non merci", "surtout pas", "n'efface rien", "non n'efface rien"].contains(request) {
            JarvisConfirmations.shared.cancel()
            return .ok("Entendu, je n'efface rien.", data: ["confirmation": "cancelled"])
        }
        return nil
    }

    private func lifeAnswer(request: String, original: String, now: Date) -> JarvisResponse? {
        let padded = " \(request) "
        func has(_ needles: [String]) -> Bool { needles.contains { padded.contains(" \($0) ") } }
        let tokens = request.split(separator: " ").map(String.init)
        let mentionsTimer = has(JarvisLifeRequestParser.timerWords)

        // Reminders: « Rappelle-moi d'appeler maman demain à 18 h ».
        if has(["rappelle moi", "rappelle nous"]) {
            guard let reminder = JarvisLifeRequestParser.reminder(original: original, normalized: request, now: now), !reminder.title.isEmpty else {
                return JarvisResponse(status: .refused, spokenResponse: "Que dois-je vous rappeler, et quand ?", displayResponse: "Dites par exemple : « Rappelle-moi d'appeler maman demain à 18 h ».")
            }
            var data = ["action": "reminder_create", "reminder_title": reminder.title]
            if let due = reminder.dueDate { data["reminder_due"] = String(due.timeIntervalSince1970) }
            if let spoken = reminder.spokenDue { data["reminder_spoken_due"] = spoken }
            return .ok("Je crée le rappel.", display: "Rappel : « \(reminder.title) »\(reminder.spokenDue.map { ", \($0)" } ?? "").", data: data)
        }

        // Timers.
        let cancelWords = ["annule", "arrete", "stop", "supprime", "efface", "coupe"]
        if mentionsTimer && has(cancelWords) {
            let name = JarvisLifeRequestParser.timerName(fromOriginal: original, normalizedTokens: tokens, excluding: [])
            let words = Set(cancelWords)
            let cleaned = name.split(separator: " ").filter { !words.contains(JarvisFrenchCommandRouter.normalize(String($0))) }.joined(separator: " ")
            let removed = timers.remove(named: cleaned.isEmpty || cleaned == "minuteur" ? nil : cleaned, now: now)
            let ids = removed.map(\.id.uuidString).joined(separator: ",")
            let spoken: String
            switch removed.count {
            case 0: spoken = "Aucun minuteur à annuler."
            case 1: spoken = removed[0].name == "minuteur" ? "Minuteur annulé." : "Minuteur « \(removed[0].name) » annulé."
            default: spoken = "\(removed.count) minuteurs annulés."
            }
            return .ok(spoken, data: ["action": "timer_cancel", "timer_ids": ids])
        }
        if let duration = JarvisFrenchDurationParser.durations(in: tokens).first,
           mentionsTimer || has(["reveille moi dans", "previens moi dans", "dis moi dans"]) {
            let name = JarvisLifeRequestParser.timerName(fromOriginal: original, normalizedTokens: tokens, excluding: [duration.range])
                .split(separator: " ")
                .filter { !["réveille", "previens", "préviens", "dis", "reveille"].contains(String($0).lowercased()) }
                .joined(separator: " ")
            let timerName = name.isEmpty ? "minuteur" : name
            let timer = timers.add(name: timerName, duration: duration.seconds, now: now)
            let length = JarvisFrenchDurationParser.spoken(duration.seconds)
            let spoken = timerName == "minuteur" ? "Minuteur lancé : \(length)." : "Minuteur « \(timerName) » lancé : \(length)."
            return .ok(spoken, data: ["action": "timer_start", "timer_id": timer.id.uuidString, "seconds": String(Int(duration.seconds)), "name": timerName])
        }
        if mentionsTimer || has(["il reste combien", "combien de temps reste", "combien de temps il reste", "temps restant", "il me reste combien"]) {
            let active = timers.active(at: now)
            guard !active.isEmpty else { return .ok("Aucun minuteur en cours.") }
            let parts = active.map { timer -> String in
                let left = JarvisFrenchDurationParser.spoken(timer.remaining(at: now))
                return timer.name == "minuteur" ? "\(left) pour le minuteur" : "\(left) pour « \(timer.name) »"
            }
            return .ok("Il reste \(parts.joined(separator: ", et ")).")
        }

        // Briefing.
        if has(["fais moi le point", "fais le point", "briefing", "mon briefing", "le point du jour", "point du matin", "quoi de neuf aujourd'hui", "resume de ma journee"]) {
            let formatter = DateFormatter()
            formatter.locale = locale
            formatter.dateFormat = "EEEE d MMMM"
            let clock = DateFormatter()
            clock.locale = locale
            clock.dateFormat = "H 'h' mm"
            return .ok("Voici le point : nous sommes le \(formatter.string(from: now)), il est \(clock.string(from: now)).", data: ["action": "briefing"])
        }

        // Agenda: « Qu'est-ce que j'ai demain ? », « Mon agenda de lundi ».
        let day = JarvisFrenchDayParser.day(in: tokens, now: now)
        let asksAgenda = has(["mon agenda", "mon calendrier", "mes rendez vous", "mon programme", "est ce que je suis libre", "j'ai quoi", "qu'est ce que j'ai de prevu", "qu'ai je de prevu", "qu'est ce qui est prevu", "ai je des rendez vous"])
            || (has(["qu'est ce que j'ai", "qu'ai je"]) && day != nil && !has(["deplace", "bouge", "note", "notes", "pris"]))
        if asksAgenda {
            let offset = day?.dayOffset ?? 0
            let label = day?.label ?? "aujourd'hui"
            return .ok("Je regarde votre agenda.", data: ["action": "agenda_read", "day_offset": String(offset), "day_label": label])
        }
        return nil
    }

    /// « Combien de notes ai-je prises ces sept derniers jours ? », « Montre-les-moi »,
    /// « Pose ce bilan sur la table », and data Jarvis does not have (downloads).
    private func notesSummaryAnswer(_ request: String, now: Date) -> JarvisResponse? {
        let padded = " \(request) "
        func has(_ needles: [String]) -> Bool { needles.contains { padded.contains(" \($0) ") } }

        if has(["telechargement", "telechargements", "downloads", "installations"]) &&
            has(["combien", "statistiques", "statistique", "nombre", "stats", "chiffres", "bilan"]) {
            return .ok(
                "Je n'ai pas accès aux statistiques de téléchargement : aucune source de ce type n'est connectée à JARVIS.",
                display: "Statistiques de téléchargement indisponibles : JARVIS ne connaît que ses propres données locales (notes, historique)."
            )
        }

        let prefix = Self.trialNotePrefix
        if has(["notes d'essai", "note d'essai", "essai du bilan"]) && has(["efface", "supprime", "retire", "enleve"]) {
            let removed = memory.removeNotes { $0.text.hasPrefix(prefix) }
            context.lastNotesSummary = nil
            return .ok(removed == 0 ? "Il n'y a aucune note d'essai." : "Notes d'essai supprimées.")
        }
        if has(["prepare l'essai du bilan", "prepare les notes d'essai", "cree les notes d'essai", "cree des notes d'essai", "ajoute les notes d'essai"]) {
            memory.removeNotes { $0.text.hasPrefix(prefix) }
            memory.saveNote("\(prefix) Note d'aujourd'hui n° 1", createdAt: now.addingTimeInterval(-50 * 60))
            memory.saveNote("\(prefix) Note d'aujourd'hui n° 2", createdAt: now.addingTimeInterval(-5 * 60))
            memory.saveNote("\(prefix) Note d'il y a huit jours", createdAt: now.addingTimeInterval(-8 * 86_400))
            context.lastNotesSummary = nil
            return .ok(
                "Trois notes d'essai créées : deux aujourd'hui et une il y a huit jours.",
                display: "Notes d'essai créées (préfixe \(prefix)). Dites « efface les notes d'essai » pour les retirer."
            )
        }

        if has(["combien"]) && has(["note", "notes"]) {
            let summary = JarvisNotesSummary.make(from: memory.loadNotes(), days: JarvisNotesSummary.requestedDays(in: request), now: now)
            context.lastNotesSummary = summary
            return .ok(summary.spokenAnswer, display: summary.displayAnswer)
        }

        if let summary = context.lastNotesSummary,
           has(["montre les moi", "montre les", "affiche les", "lesquelles", "lis les moi", "lis les", "quelles sont elles", "montre moi ces notes", "montre ces notes", "lesquelles sont ce"]),
           !has(["les notes", "mes notes", "toutes"]) {
            let spoken: String
            switch summary.count {
            case 0: spoken = "Il n'y a aucune note \(summary.periodDescription)."
            case 1: spoken = "Voici la note \(summary.periodDescription)."
            default: spoken = "Voici les \(summary.count) notes \(summary.periodDescription)."
            }
            return .ok(spoken, display: summary.listText())
        }

        if has(["bilan", "fiche"]) && has(["ferme", "retire", "enleve", "supprime", "range", "efface"]) {
            return .ok("Je retire la fiche du bilan.", display: "Fiche du bilan retirée.", data: ["action": "ar_summary_close"])
        }
        if has(["bilan", "fiche", "resume"]) && has(["pose", "poser", "place", "mets", "affiche", "montre", "projette"]) {
            let summary = context.lastNotesSummary ?? JarvisNotesSummary.make(from: memory.loadNotes(), days: 7, now: now)
            context.lastNotesSummary = summary
            return .ok(
                "Je pose le bilan sur la table : \(summary.count) \(summary.count == 1 ? "note" : "notes").",
                display: "Fiche du bilan : \(summary.displayAnswer) Pincez son bord pour la déplacer.",
                data: summary.cardData
            )
        }
        return nil
    }

    struct TranslatedAction: Equatable {
        let command: String
        let spoken: String
        let display: String?
    }

    /// Maps the French wording of an existing action to its canonical command, without
    /// side effects. `text` may be raw or already normalized.
    static func translateAction(_ text: String) -> TranslatedAction? {
        let request = stripWakeWord(normalize(text))
        let padded = " \(request) "
        func has(_ needles: [String]) -> Bool { needles.contains { padded.contains(" \($0) ") } }

        if request == "stop" || request == "arrete" || request == "arrete tout" || request == "annule" {
            return TranslatedAction(command: "stop", spoken: "J'arrête.", display: "Arrêt.")
        }
        if has(["tais toi", "arrete de parler", "chut"]) {
            return TranslatedAction(command: "stop speaking", spoken: "D'accord.", display: "Parole arrêtée.")
        }
        if has(["mode silencieux", "coupe le son", "sois silencieux"]) {
            return TranslatedAction(command: "quiet mode", spoken: "Mode silencieux activé.", display: "Mode silencieux activé.")
        }
        if has(["test de la voix", "teste ta voix", "test voix"]) {
            return TranslatedAction(command: "voice test", spoken: JarvisSpeechService.shared.testPhrase(), display: nil)
        }
        if has(["reglages", "parametres", "preferences"]) {
            return TranslatedAction(command: "open settings", spoken: "J'ouvre les réglages.", display: "Ouverture des réglages de JARVIS.")
        }
        if has(["diagnostic", "diagnostics"]) {
            return TranslatedAction(command: "diagnostics", spoken: "J'ouvre les diagnostics.", display: "Ouverture des diagnostics.")
        }
        if has(["batterie"]) {
            return TranslatedAction(command: "battery", spoken: "Voici l'état de la batterie.", display: nil)
        }
        if has(["guide en direct", "guidage en direct", "live guide"]) {
            return TranslatedAction(command: "start live guide", spoken: "Je lance le guide en direct.", display: nil)
        }
        if has(["code barre", "code barres", "codebarre"]) {
            return TranslatedAction(command: "scan barcode", spoken: "Je scanne le code-barres.", display: nil)
        }
        if has(["lis ce texte", "lis le texte", "lis ca", "lis ceci", "qu'est ce qui est ecrit", "lis cette etiquette"]) {
            return TranslatedAction(command: "read this", spoken: "Je lis le texte.", display: nil)
        }
        if has(["qu'est ce que tu vois", "que vois tu", "decris", "decris moi", "qu'est ce qu'il y a devant moi", "qu'y a t il devant moi"]) {
            return TranslatedAction(command: "describe this", spoken: "Je regarde.", display: nil)
        }
        // « Où est ma tasse ? », « Cherche mon téléphone » : the camera's Find mode, with the
        // detector's class name. The local brain cannot see, so it must not get these.
        if let target = VisionFrenchVocabulary.findTarget(inNormalized: request) {
            let noun = VisionFrenchVocabulary.noun(for: target)
            return TranslatedAction(
                command: "find \(target)",
                spoken: "Je cherche \(noun.definite) avec la caméra.",
                display: "Recherche : \(noun.singular). Balayez lentement avec le téléphone."
            )
        }
        if (has(["camera", "vision"]) && has(["ouvre", "lance", "active", "allume", "demarre"])) || request == "camera" {
            return TranslatedAction(command: "open camera", spoken: "J'ouvre la caméra.", display: "Ouverture de la caméra.")
        }
        return nil
    }

    // MARK: - Text helpers

    static let greetings = ["bonjour", "salut", "bonsoir", "coucou", "hello"]

    /// Dictated notes win over every other reading: « prends une note le train part à 9 h ».
    static let notePrefixes = ["prends une note", "prend une note", "prends note", "nouvelle note", "enregistre une note", "note que", "souviens toi que", "retiens que", "rappelle toi que"]

    /// Lowercases, folds accents, turns apostrophes into "'" and punctuation/hyphens into spaces.
    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            // Keep « 21:15 » as one clock token (« 21h15 ») before ':' becomes a separator.
            .replacingOccurrences(of: #"(\d{1,2}):(\d{2})"#, with: "$1h$2", options: .regularExpression)
        let separators = CharacterSet(charactersIn: ",.?;:!\"«»()-–—…")
        return folded
            .components(separatedBy: separators)
            .joined(separator: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func stripWakeWord(_ normalized: String) -> String {
        var value = normalized
        for prefix in ["dis jarvis ", "hey jarvis ", "ok jarvis ", "okay jarvis ", "eh jarvis ", "jarvis "] where value.hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
            break
        }
        for suffix in [" jarvis"] where value.hasSuffix(suffix) {
            value = String(value.dropLast(suffix.count))
        }
        if value.hasPrefix("bonjour jarvis ") { value = String(value.dropFirst("bonjour jarvis ".count)) }
        return value
    }

    static let frenchMarkers: Set<String> = [
        "je", "j'ai", "tu", "vous", "il", "elle", "nous", "est", "c'est", "qu'est", "que", "quoi", "quel", "quelle",
        "le", "la", "les", "des", "du", "un", "une", "mon", "ma", "mes", "moi", "toi", "et", "ou", "pour", "avec",
        "dans", "sur", "pas", "bonjour", "salut", "merci", "ouvre", "montre", "dis", "fais", "peux", "combien",
        "pourquoi", "comment", "quand", "ca", "oui", "non", "s'il", "plait", "aujourd'hui", "demain", "hier"
    ]

    static func looksFrench(_ normalized: String) -> Bool {
        let words = normalized.split(separator: " ").map(String.init)
        let hits = words.filter { frenchMarkers.contains($0) || $0.hasPrefix("l'") || $0.hasPrefix("d'") || $0.hasPrefix("qu'") || $0.hasPrefix("m'") }
        return !hits.isEmpty
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        let padded = " \(text) "
        return needles.contains { padded.contains(" \($0) ") }
    }

    private static let tokenSeparators = CharacterSet(charactersIn: ",.?;:!\"«»()-–—…").union(.whitespacesAndNewlines)

    /// Returns the user's original wording after `prefix` (matched on normalized text),
    /// or nil when the request does not start with that prefix. Tokens are counted with
    /// the same separators as `normalize`, so accents, capitals and hyphens of the note
    /// itself are preserved.
    static func argument(in original: String, normalized: String, after prefix: String) -> String? {
        let request = stripWakeWord(normalized)
        guard request == prefix || request.hasPrefix(prefix + " ") else { return nil }
        let prefixTokens = prefix.split(separator: " ").count
        let wakeTokens = normalized.split(separator: " ").count - request.split(separator: " ").count
        let skip = wakeTokens + prefixTokens

        var tokenStarts: [String.Index] = []
        var insideToken = false
        for index in original.indices {
            let isSeparator = original[index].unicodeScalars.allSatisfy { tokenSeparators.contains($0) }
            if !isSeparator && !insideToken { tokenStarts.append(index) }
            insideToken = !isSeparator
        }
        guard skip < tokenStarts.count else { return "" }
        return String(original[tokenStarts[skip]...])
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ":,.")))
    }
}
