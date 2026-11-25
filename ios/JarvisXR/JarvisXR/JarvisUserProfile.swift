import Foundation

/// What Jarvis knows about the person it serves: the first name to use (« Je m'appelle… »).
/// With the notes (« Souviens-toi que… »), it is given to the local brain so its answers can
/// use it. It leaves the iPhone only for the user's own Jarvis PC, once paired with its code.
final class JarvisUserProfile {
    static let shared = JarvisUserProfile()

    private let defaults: UserDefaults
    private let nameKey = "JarvisXR.userName"
    private let nameUpdatedKey = "JarvisXR.userNameUpdated"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var name: String? {
        get {
            guard let stored = defaults.string(forKey: nameKey), !stored.isEmpty else { return nil }
            return stored
        }
        set {
            store(newValue)
            defaults.set(Date().timeIntervalSince1970, forKey: nameUpdatedKey)
        }
    }

    /// When the first name was last given or forgotten, so the iPhone and Jarvis PC keep
    /// the most recent one.
    var nameUpdated: Date {
        Date(timeIntervalSince1970: defaults.double(forKey: nameUpdatedKey))
    }

    /// The first name known by Jarvis PC, more recent than the iPhone's.
    func adoptName(_ name: String?, updated: Date) {
        store(name)
        defaults.set(updated.timeIntervalSince1970, forKey: nameUpdatedKey)
    }

    private func store(_ name: String?) {
        if let name, !name.isEmpty {
            defaults.set(name, forKey: nameKey)
        } else {
            defaults.removeObject(forKey: nameKey)
        }
    }

    /// Words that start a sentence, not a name: « Appelle-moi un taxi », « … quand tu as fini ».
    private static let refusedFirstWords: Set<String> = [
        "un", "une", "le", "la", "les", "des", "du", "de", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses",
        "quand", "si", "dans", "demain", "ce", "cet", "cette", "vite", "plus", "encore", "moi", "toi", "comment",
        "quoi", "qui", "pas", "jarvis", "maman", "papa",
    ]

    /// « tony » → « Tony », « jean-marc » → « Jean-Marc »; nil when the words are not a name.
    static func cleanedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".,;:!?«»\"")))
        let words = trimmed.split(separator: " ").map(String.init)
        guard (1...3).contains(words.count), let first = words.first, !refusedFirstWords.contains(first.lowercased()) else {
            return nil
        }
        var parts: [String] = []
        for word in words {
            let allowed = word.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) || $0 == "-" || $0 == "'" }
            guard allowed, word.count <= 24 else { return nil }
            let capitalized = word
                .split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: "-")
            parts.append(capitalized)
        }
        return parts.joined(separator: " ")
    }

    /// Lines for the local brain's system prompt: the first name, and what the person
    /// asked Jarvis to remember (latest first, trial notes left out), kept short.
    func brainContextLines(memory: JarvisMemoryStore = .shared, limit: Int = 8, characterBudget: Int = 700) -> [String] {
        var lines: [String] = []
        if let name {
            lines.append("La personne qui te parle s'appelle \(name) ; tu peux utiliser son prénom de temps en temps.")
        }
        let notes = memory.loadNotes()
            .filter { !$0.text.hasPrefix(JarvisFrenchCommandRouter.trialNotePrefix) }
            .prefix(limit)
            .map { String($0.text.prefix(140)) }
        var kept: [String] = []
        var used = 0
        for note in notes where used + note.count <= characterBudget {
            kept.append(note)
            used += note.count
        }
        if !kept.isEmpty {
            lines.append("Ce que cette personne t'a demandé de retenir, de la note la plus récente à la plus ancienne : " + kept.joined(separator: " ; ") + ".")
        }
        return lines
    }
}
