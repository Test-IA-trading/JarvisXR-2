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
    private let locale = Locale(identifier: "fr_FR")

    /// Prefix of the notes created by « prépare l'essai du bilan ».
    static let trialNotePrefix = "[essai]"

    init(
        memory: JarvisMemoryStore = .shared,
        scene: JarvisSpatialSceneMemory = .shared,
        context: JarvisConversationContext = .shared,
        screen: JarvisScreenContext = .shared,
        timers: JarvisTimerStore = .shared
    ) {
        self.memory = memory
        self.scene = scene
        self.context = context
        self.screen = screen
        self.timers = timers
    }

    func route(_ raw: String, now: Date = Date()) -> Outcome {
        let original = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = Self.normalize(original)
        guard !text.isEmpty else { return .notHandled }

        // "Bonjour Jarvis, est-ce que tu m'entends ?" — the first sentence of the field test.
        if containsAny(text, ["tu m'entends", "vous m'entendez", "tu m'ecoutes", "tu me recois", "est ce que ca marche", "test micro", "test du micro"]) {
            return .answer(.ok(
                "Oui, je vous entends bien.",
                display: "Oui, je vous entends bien. J'ai compris : « \(original) »"
            ))
        }

        let withoutWakeWord = Self.stripWakeWord(text)
        if Self.greetings.contains(where: { withoutWakeWord == $0 || withoutWakeWord.hasPrefix($0 + " ") }) &&
            withoutWakeWord.split(separator: " ").count <= 3 {
            return .answer(.ok("Bonjour ! Je vous écoute."))
        }
        let request = withoutWakeWord

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
                "Je peux lancer des minuteurs, créer des rappels, lire votre agenda, faire le point, retenir des horaires, compter vos notes, poser un cube ou un bilan en réalité augmentée, et répondre à vos questions avec le cerveau local.",
                display: "Essayez : « Minuteur pâtes 10 minutes », « Rappelle-moi d'appeler maman demain à 18 h », « Qu'est-ce que j'ai demain ? », « Fais-moi le point », « Le train part à 9 h et le bus à 11 h. Lequel part en premier ? », « Combien de notes ai-je prises ces sept derniers jours ? », « Montre-les-moi », « Pose ce bilan sur la table », « Ouvre le cube », « Qu'est-ce que je viens de déplacer ? », « Quelle heure est-il ? », « Prends une note… », « Lis ce texte », « C'est tout »."
            ))
        }

        // Notes, answered natively so the reply stays French.
        for prefix in Self.notePrefixes {
            if let body = Self.argument(in: original, normalized: request, after: prefix) {
                guard !body.isEmpty else {
                    return .answer(JarvisResponse(status: .refused, spokenResponse: "Que dois-je noter ?", displayResponse: "Dites par exemple : « Prends une note acheter du pain ».", shouldSpeak: true))
                }
                let note = memory.saveNote(body)
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
        return .openQuestion(original)
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
