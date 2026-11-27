import Foundation

// The rhythm of a spoken conversation, as pure rules the tests check: when the user has
// finished speaking, what Jarvis says while it thinks, when the user speaks over Jarvis,
// and the brain's rewording of a free request into a command.

/// How long a silence ends the user's turn, from what was said so far. A sentence that
/// sounds finished (« Quelle heure est-il ? ») ends quickly; one that stops on « et »,
/// « de », « parce que » or on a bare verb (« Appelle… ») waits for the rest.
enum JarvisTurnEndDetector {
    // The owner's first complaint was a listening cut too early (docs/VISION_JARVIS.md §2, §10):
    // the shorter values of docs/specs/voix.md §4 (0,55 s after « ? ») ended turns on the
    // recognizer's own punctuation, which it writes before the real end of an idea. Longer
    // waits, punctuation trusted only after a real sentence, hesitations kept, and the voice
    // still heard on the microphone (`deadline`) push the end back. To calibrate on the
    // iPhone: the recognizer's own delay (≈ 0,2–0,3 s) comes on top of these silences.
    static let finished: TimeInterval = 0.8
    static let ordinary: TimeInterval = 1.2
    static let shortStart: TimeInterval = 1.5
    static let unfinished: TimeInterval = 2.2
    /// After « euh », « attends », « enfin »: the person is looking for their words.
    static let hesitation: TimeInterval = 2.6
    /// How much longer the voice alone (no new words written) may keep the turn open.
    static let maximumVoiceExtension: TimeInterval = 2.5

    /// Sounds and words of someone who has not finished (« Je voudrais… euh… »).
    static let hesitationWords: Set<String> = ["euh", "heu", "hum", "hmm", "mmh", "bah", "ben", "enfin", "genre", "attends", "attend"]

    /// Words after which French goes on: articles, prepositions, conjunctions, possessives.
    static let continuationWords: Set<String> = [
        "et", "ou", "mais", "donc", "car", "ni", "or", "que", "qu'", "qui", "dont", "si", "comme", "quand", "lorsque",
        "parce", "puisque", "pendant", "depuis", "avant", "apres", "de", "d'", "du", "des", "le", "la", "les", "l'",
        "un", "une", "au", "aux", "a", "pour", "par", "avec", "sans", "sur", "sous", "dans", "en", "chez", "vers",
        "entre", "contre", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos",
        "leur", "leurs", "ce", "cet", "cette", "ces", "quel", "quelle", "quels", "quelles", "je", "j'", "tu", "il",
        "elle", "on", "nous", "vous", "ils", "elles", "me", "m'", "te", "se", "ne", "n'", "tres", "euh", "heu", "hum",
        "bah", "ben", "alors", "puis", "ensuite", "genre", "enfin", "c'est",
    ]
    /// Commands that are not finished without what follows (« Appelle… », « Envoie un message à… »).
    static let openingVerbs: Set<String> = [
        "appelle", "envoie", "ecris", "dis", "ouvre", "lance", "mets", "montre", "cherche", "joue", "rappelle",
        "donne", "fais", "prends", "note", "trouve", "affiche", "calcule", "traduis", "convertis", "explique",
        "raconte", "parle", "previens", "demande", "rappelle-moi", "montre-moi", "dis-moi", "donne-moi", "fais-moi",
        "parle-moi", "explique-moi", "mets-moi", "ouvre-moi", "trouve-moi", "lis-moi",
    ]
    /// Complete on their own, said in one or two words.
    static let shortAnswers: Set<String> = [
        "oui", "non", "stop", "merci", "ok", "d'accord", "pause", "continue", "arrete", "bonjour", "salut", "bonsoir",
        "c'est tout", "ca suffit", "tais-toi", "chut", "jarvis", "merci beaucoup", "non merci", "oui merci", "parfait",
        "super", "genial", "encore", "pardon", "quoi", "suivant", "annule",
    ]

    /// The silence that ends the turn after `transcript` (the recognizer's text so far).
    static func silence(after transcript: String) -> TimeInterval {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return unfinished }
        if trimmed.hasSuffix("…") || trimmed.hasSuffix(",") || trimmed.hasSuffix(":") || trimmed.hasSuffix(";") { return unfinished }
        let words = JarvisFrenchCommandRouter.normalize(trimmed.replacingOccurrences(of: "-", with: "_"))
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: " ").map(String.init)
        guard let last = words.last else { return unfinished }
        // The words decide before the punctuation: « Je voudrais que ? » is not finished.
        if hesitationWords.contains(last) { return hesitation }
        if continuationWords.contains(last) || (words.count >= 2 && continuationWords.contains(words.suffix(2).joined(separator: " "))) {
            return unfinished
        }
        let joined = words.joined(separator: " ")
        if shortAnswers.contains(joined) { return finished }
        // « Appelle », « Envoie un message à » (handled above), « Rappelle-moi »: the request goes on.
        if words.count <= 2, openingVerbs.contains(words[0]), words.count == 1 || openingVerbs.contains(last) {
            return unfinished
        }
        if words.count <= 2 { return shortStart }
        // The recognizer's « ? », « ! » or « . » after a real sentence.
        if trimmed.hasSuffix("?") || trimmed.hasSuffix("!") || trimmed.hasSuffix(".") { return finished }
        return ordinary
    }

    /// When the turn ends: `needed` seconds after the last new words, pushed back while the
    /// microphone still hears the user's voice (a long « euuuh » the recognizer does not
    /// write, a breath before the rest), by at most `maximumVoiceExtension`.
    static func deadline(needed: TimeInterval, lastWords: Date, lastVoice: Date?) -> Date {
        let afterWords = lastWords.addingTimeInterval(needed)
        guard let lastVoice, lastVoice > lastWords else { return afterWords }
        return max(afterWords, min(lastVoice.addingTimeInterval(needed), afterWords.addingTimeInterval(maximumVoiceExtension)))
    }

    /// Text of successive recognitions of one turn: Apple's recognizer may close its text at
    /// a pause, the turn goes on in a new one; its own final period is not the end of the idea.
    static func joined(_ committed: String, _ segment: String) -> String {
        let head = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !head.isEmpty else { return tail }
        guard !tail.isEmpty else { return head }
        let open = head.hasSuffix(".") && !head.hasSuffix("...") ? String(head.dropLast()) : head
        return open + " " + tail
    }
}

/// The user's voice on the microphone while they hold the floor, from its level over the
/// room's (as JarvisBargeInDetector): what keeps a turn open during a hesitation the
/// recognizer does not write. A click or a short noise does not count. Main queue.
struct JarvisVoiceActivity {
    var minimumLevel: Float = -48
    var marginOverFloor: Float = 10
    var requiredSpeech: TimeInterval = 0.12

    private(set) var floor: Float?
    private(set) var voiced: TimeInterval = 0
    /// Last moment the voice was heard, nil before any.
    private(set) var lastVoice: Date?
    private var lastBuffer: Date?

    var threshold: Float { max(minimumLevel, (floor ?? -65) + marginOverFloor) }

    /// `level`: peak dBFS of the microphone buffer received at `now`.
    mutating func ingest(level: Float, at now: Date) {
        let duration = min(0.2, max(0, now.timeIntervalSince(lastBuffer ?? now)))
        lastBuffer = now
        guard let current = floor else {
            floor = level
            return
        }
        if level < current {
            floor = 0.7 * current + 0.3 * level
        } else if level < threshold {
            floor = current + 0.02 * (level - current)
        }
        if level >= threshold {
            voiced += duration
            if voiced >= requiredSpeech { lastVoice = now }
        } else {
            voiced = max(0, voiced - duration * 0.5)
        }
    }
}

/// A few words said when an answer takes time, as a person would (« Voyons voir. »),
/// never the same twice in a row.
struct JarvisThinkingFiller {
    /// Silence after which Jarvis says something while it thinks.
    static let delay: TimeInterval = 0.9

    static let general = ["Voyons voir.", "Laissez-moi réfléchir un instant.", "Bonne question.", "Alors, voyons.", "Un instant, je réfléchis."]
    static let lookup = ["Je regarde ça.", "Un instant, je cherche.", "Voyons ce que j'en sais.", "Je vérifie."]
    static let calculation = ["Je calcule.", "Un instant, je fais le calcul."]

    private(set) var last: String?
    private var turn = 0

    static func phrases(for question: String) -> [String] {
        let request = JarvisFrenchCommandRouter.normalize(question)
        let lookupWords = ["qui est", "qui etait", "qu'est ce", "c'est quoi", "parle moi", "explique moi", "wikipedia", "definition",
                           "que veut dire", "que signifie", "meteo", "quel temps", "actualite", "les infos", "les titres"]
        if lookupWords.contains(where: { request.contains($0) }) { return lookup }
        let calculationWords = ["combien font", "combien fait", "calcule", "integrale", "derivee", "racine", "pourcentage", "equation"]
        if calculationWords.contains(where: { request.contains($0) }) || request.contains(where: \.isNumber) { return calculation }
        return general
    }

    mutating func next(for question: String) -> String {
        let options = Self.phrases(for: question)
        turn += 1
        var phrase = options[turn % options.count]
        if phrase == last, options.count > 1 { phrase = options[(turn + 1) % options.count] }
        last = phrase
        return phrase
    }
}

/// Hears the user start speaking over Jarvis, from the microphone level once Apple's echo
/// cancellation has removed most of Jarvis's own voice. The level must stay above the
/// room's for a quarter of a second, so a click or a breath does not count; the words
/// heard then confirm it (JarvisEchoFilter).
struct JarvisBargeInDetector {
    /// The echo cancellation needs a moment each time Jarvis starts speaking.
    var settleTime: TimeInterval = 0.35
    var minimumLevel: Float = -42
    var marginOverFloor: Float = 12
    var requiredSpeech: TimeInterval = 0.24

    private(set) var elapsed: TimeInterval = 0
    private(set) var floor: Float = -65
    private(set) var voiced: TimeInterval = 0
    private(set) var fired = false

    var threshold: Float { max(minimumLevel, floor + marginOverFloor) }

    mutating func reset() {
        elapsed = 0
        floor = -65
        voiced = 0
        fired = false
    }

    /// `level` in dBFS for a buffer of `duration` seconds. True once, when the user likely
    /// started to speak; false afterwards until `reset()`.
    mutating func ingest(level: Float, duration: TimeInterval) -> Bool {
        elapsed += duration
        if elapsed <= settleTime {
            floor = elapsed <= duration ? level : max(floor, level)
            return false
        }
        if level < floor {
            floor = 0.7 * floor + 0.3 * level
        } else if level < threshold {
            floor += 0.02 * (level - floor)
        }
        if level >= threshold {
            voiced += duration
        } else {
            voiced = max(0, voiced - duration * 0.5)
        }
        guard !fired, voiced >= requiredSpeech else { return false }
        fired = true
        return true
    }
}

/// Words heard while Jarvis speaks: Jarvis's own (what the echo cancellation let through)
/// or the user's.
enum JarvisEchoFilter {
    static let interruptionWords: Set<String> = ["stop", "attends", "attend", "arrete", "chut", "non", "pardon", "jarvis", "pause", "silence", "tais"]

    static func words(_ text: String) -> [String] {
        JarvisFrenchCommandRouter.normalize(text).split(separator: " ").map(String.init)
    }

    /// True when most of the words heard are in what Jarvis is saying.
    static func isLikelyEcho(_ heard: String, spoken: String) -> Bool {
        let heardWords = words(heard)
        guard !heardWords.isEmpty else { return true }
        let spokenWords = Set(words(spoken))
        guard !spokenWords.isEmpty else { return false }
        let shared = heardWords.filter { spokenWords.contains($0) }.count
        return Double(shared) / Double(heardWords.count) >= 0.6
    }

    /// What people say to take the floor back, normalized. They stop Jarvis even when its
    /// reply has the same words (« non » in « Non, il ne pleut pas »), but not when the
    /// reply itself says the whole phrase.
    static let stopPhrases = [
        "non non", "attends", "attend", "stop", "arrete", "chut", "tais toi", "laisse moi finir", "laisse moi parler",
        "c'est pas ca", "ce n'est pas ca", "pas ca", "mais non", "attention", "excuse moi", "jarvis",
    ]

    /// The user speaks over Jarvis: a phrase that takes the floor back, two words of their
    /// own, or one that interrupts (« Stop »).
    static func isInterruption(_ heard: String, spoken: String) -> Bool {
        let heardWords = words(heard)
        guard let first = heardWords.first else { return false }
        let heardText = " " + heardWords.joined(separator: " ") + " "
        let spokenText = " " + words(spoken).joined(separator: " ") + " "
        if stopPhrases.contains(where: { heardText.contains(" \($0) ") && !spokenText.contains(" \($0) ") }) {
            return true
        }
        guard !isLikelyEcho(heard, spoken: spoken) else { return false }
        return heardWords.count >= 2 || interruptionWords.contains(first) || first.count >= 5
    }
}

/// The PC brain's rewording of a free request into a command the iPhone knows:
/// « Préviens Marie que je serai en retard » → « COMMANDE: envoie un message à Marie… ».
enum JarvisBrainCommand {
    static func parse(_ answer: String) -> String? {
        let text = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.uppercased().hasPrefix("COMMANDE") else { return nil }
        var rest = String(text.dropFirst("COMMANDE".count))
        rest = String(rest.drop { $0 == " " || $0 == ":" })
        let line = rest.components(separatedBy: .newlines).first ?? ""
        let command = line.trimmingCharacters(in: CharacterSet(charactersIn: " «»\"'").union(.whitespaces))
        return command.isEmpty ? nil : command
    }

    /// True while the text written so far could still become « COMMANDE: … » (never spoken).
    static func mayBeCommand(_ partial: String) -> Bool {
        let head = String(partial.drop { $0.isWhitespace }.prefix(9)).uppercased()
        return "COMMANDE:".hasPrefix(head) || head.hasPrefix("COMMANDE")
    }
}
