import Foundation

// The person's control over Jarvis (docs/VISION_JARVIS.md §7, §14, §17), kept apart from the
// brain and the orchestration: no model output, page or file can trigger, skip or switch off
// these checks; only the person's own words or gestures, read by the app's code, do.

/// A deletion Jarvis asked the person to confirm: it runs only after « Je confirme » said
/// within a minute (the French router), never from a model's words or a page's text.
final class JarvisConfirmations {
    static let shared = JarvisConfirmations()
    static let delay: TimeInterval = 60

    private struct Pending {
        let summary: String
        let expires: Date
        let run: () -> String
    }

    private var pending: Pending?

    var isWaiting: Bool { pending != nil }
    var waitingSummary: String? { pending?.summary }

    /// Asks to confirm `summary` (« effacer toute ma mémoire »); `run` does it and says what was done.
    func ask(_ summary: String, now: Date = Date(), run: @escaping () -> String) -> JarvisResponse {
        pending = Pending(summary: summary, expires: now.addingTimeInterval(Self.delay), run: run)
        let spoken = "Voulez-vous vraiment \(summary) ? Cela ne pourra pas être annulé. Dites « Je confirme » pour le faire, ou « non »."
        return JarvisResponse(status: .confirmationRequired, spokenResponse: spoken, displayResponse: spoken, data: ["confirmation": "asked"])
    }

    /// Runs the confirmed deletion; nil when nothing waits or the minute has passed.
    func confirm(now: Date = Date()) -> String? {
        guard let waiting = pending else { return nil }
        pending = nil
        guard waiting.expires > now else { return nil }
        return waiting.run()
    }

    func cancel() {
        pending = nil
    }
}

/// The emergency stop (§17.1), independent of the brain: « Jarvis, arrêt d'urgence » (heard
/// before any routing) or a shake of the iPhone stops the listening, the voice, the reasoning,
/// the searches and network calls, the background watch and the confirmations waiting, and
/// keeps anything new from starting until « Jarvis, reprends » or a tap on « Reprendre ».
/// An action already done outside the iPhone (a message sent) cannot be undone: Jarvis says so.
final class JarvisEmergencyStop {
    static let shared = JarvisEmergencyStop()
    static let didChange = Notification.Name("JarvisEmergencyStop.didChange")

    private let lock = NSLock()
    private var engaged = false
    private(set) var engagedAt: Date?

    var isEngaged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return engaged
    }

    static let stopPhrases = [
        "arret d'urgence", "arret urgence", "stop d'urgence", "stop urgence", "urgence arrete tout", "arrete tout d'urgence",
        "arrete tout immediatement", "arret total", "stop total",
    ]
    static let releasePhrases = [
        "reprends", "reprend", "tu peux reprendre", "vous pouvez reprendre", "reprise", "fin de l'arret d'urgence",
        "leve l'arret d'urgence", "annule l'arret d'urgence", "reprends tout", "c'est bon tu peux reprendre",
    ]

    private static func request(_ text: String) -> String {
        JarvisFrenchCommandRouter.stripWakeWord(JarvisFrenchCommandRouter.normalize(text))
    }

    static func isStopRequest(_ text: String) -> Bool {
        let said = request(text)
        return stopPhrases.contains { said == $0 || said.hasPrefix($0 + " ") || said.hasSuffix(" " + $0) }
    }

    static func isReleaseRequest(_ text: String) -> Bool {
        releasePhrases.contains(request(text))
    }

    func engage(now: Date = Date()) {
        lock.lock()
        let changed = !engaged
        engaged = true
        if changed { engagedAt = now }
        lock.unlock()
        JarvisConfirmations.shared.cancel()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func release() {
        lock.lock()
        engaged = false
        engagedAt = nil
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}

/// The financial guard (§7), independent of the brain and of the orchestration: a request
/// leaves the iPhone only for a service whose use by Jarvis is free, without account, key or
/// subscription; any other host is refused before anything is sent. A new free service is
/// added here with the reason its use costs nothing (and in docs/IA_EXTERNES.md).
enum JarvisCostGuard {
    /// Host → why its use by Jarvis costs nothing.
    static let freeHosts: [String: String] = [
        "api.open-meteo.com": "Open-Meteo : prévisions gratuites sans clé pour un usage non commercial",
        "geocoding-api.open-meteo.com": "Open-Meteo : recherche de ville gratuite sans clé",
        "fr.wikipedia.org": "Wikipédia : API publique gratuite",
        "en.wikipedia.org": "Wikipedia : API publique gratuite",
        "www.francetvinfo.fr": "franceinfo : flux RSS public des titres",
    ]

    private static let lock = NSLock()
    private static var refusals: [String] = []

    /// True when `url` goes to a free service over HTTPS.
    static func permits(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return freeHosts[host] != nil
    }

    /// Records a refused host for Diagnostics (no path, no query: nothing personal).
    static func noteRefusal(_ url: URL?) {
        lock.lock()
        refusals = Array((refusals + [url?.host ?? "adresse illisible"]).suffix(10))
        lock.unlock()
    }

    static var lastRefusals: [String] {
        lock.lock()
        defer { lock.unlock() }
        return refusals
    }
}

/// « Réinitialise complètement ta mémoire » (§17.2), after confirmation: everything Jarvis
/// learned on this iPhone is erased (its notes, kept answers, conversations, notes and
/// history, first name, the brain's recent context). Returns what was done, in French,
/// with what it cannot erase (the PC's own copy, iCloud or computer backups).
enum JarvisReset {
    static func eraseEverythingLearned(
        knowledge: JarvisKnowledgeStore = .shared,
        journal: JarvisConversationJournal = .shared,
        memory: JarvisMemoryStore = .shared,
        profile: JarvisUserProfile = .shared,
        conversation: JarvisConversationContext = .shared
    ) -> String {
        let notes = knowledge.eraseAll()
        let days = journal.eraseAll()
        let dictated = memory.loadNotes().count
        memory.clearNotes()
        memory.clearHistory()
        profile.name = nil
        conversation.reset()
        return "C'est fait, Monsieur : ma mémoire est vide (\(notes) souvenir\(notes > 1 ? "s" : ""), \(dictated) note\(dictated > 1 ? "s" : ""), \(days) jour\(days > 1 ? "s" : "") de conversations, votre prénom). Je repars de zéro. La copie de ma mémoire sur Jarvis PC s'efface sur le PC lui-même, et les sauvegardes iCloud ou de l'ordinateur suivent leurs propres règles."
    }
}
