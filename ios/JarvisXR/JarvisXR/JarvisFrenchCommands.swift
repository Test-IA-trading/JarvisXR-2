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
    }

    private let memory: JarvisMemoryStore
    private let locale = Locale(identifier: "fr_FR")

    init(memory: JarvisMemoryStore = .shared) {
        self.memory = memory
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

        if containsAny(request, ["merci"]) && request.split(separator: " ").count <= 4 {
            return .answer(.ok("Avec plaisir."))
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
                "Je peux donner l'heure et la date, prendre et lire vos notes, ouvrir la caméra, lire un texte et ouvrir les réglages.",
                display: "Essayez : « Quelle heure est-il ? », « Prends une note acheter du pain », « Mes notes », « Ouvre la caméra », « Lis ce texte », « Ouvre les réglages »."
            ))
        }

        // Notes, answered natively so the reply stays French.
        for prefix in ["prends une note", "prend une note", "prends note", "nouvelle note", "enregistre une note", "note que", "souviens toi que", "retiens que", "rappelle toi que"] {
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

        // Existing actions, executed by the canonical English router.
        if let action = Self.translateAction(request) {
            // On the home screen a bare "stop" means "stop talking".
            let command = action.command == "stop" ? "stop speaking" : action.command
            return .forward(command: command, spoken: action.spoken, display: action.display)
        }

        guard Self.looksFrench(text) else { return .notHandled }
        return .answer(.ok(
            "Je n'ai pas encore de réponse locale à cette demande.",
            display: "J'ai compris : « \(original) ». Je n'ai pas encore de réponse locale à cette demande. Essayez « Aide » pour voir ce que je sais faire."
        ))
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
        if (has(["camera", "vision"]) && has(["ouvre", "lance", "active", "allume", "demarre"])) || request == "camera" {
            return TranslatedAction(command: "open camera", spoken: "J'ouvre la caméra.", display: "Ouverture de la caméra.")
        }
        return nil
    }

    // MARK: - Text helpers

    static let greetings = ["bonjour", "salut", "bonsoir", "coucou", "hello"]

    /// Lowercases, folds accents, turns apostrophes into "'" and punctuation/hyphens into spaces.
    static func normalize(_ text: String) -> String {
        let folded = text
            .replacingOccurrences(of: "’", with: "'")
            .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
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
