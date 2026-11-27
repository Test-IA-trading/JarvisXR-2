import Foundation

/// The iPhone's copy of Jarvis's long-term memory (pc/jarvis_pc/knowledge.py): the durable
/// notes the PC learned (preferences, habits, facts, corrections), received at each
/// synchronization, so the iPhone's own brain knows them too when the PC is away. Only the
/// few notes relevant to a question are given to the brain, never the whole memory.
final class JarvisKnowledgeStore {
    static let shared = JarvisKnowledgeStore()

    struct Note: Codable, Equatable {
        let id: String
        let kind: String
        let text: String
        let updated: String
    }

    static let labels = ["preference": "préférence", "habitude": "habitude", "fait": "fait", "correction": "correction"]
    private static let stopwords: Set<String> = [
        "a", "au", "aux", "avec", "ce", "ces", "cet", "cette", "ca", "de", "des", "du", "elle", "en", "est", "et", "il", "je", "la", "le",
        "les", "leur", "lui", "ma", "mais", "me", "mes", "moi", "mon", "ne", "nos", "notre", "nous", "on", "ou", "par", "pas", "pour",
        "que", "qui", "sa", "se", "ses", "si", "son", "sont", "sur", "ta", "te", "tes", "toi", "ton", "tu", "un", "une", "vos", "votre",
        "vous", "quoi", "quel", "quelle", "comment", "jarvis", "utilisateur", "dis", "fait", "faire",
    ]

    private let defaults: UserDefaults
    private let key = "JarvisXR.knowledge"
    private(set) var notes: [Note] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let stored = try? JSONDecoder().decode([Note].self, from: data) {
            notes = stored
        }
    }

    /// The PC's merged memory: its notes replace this copy; deleted ones go away.
    func adopt(_ items: [[String: Any]]) {
        var byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        for item in items {
            guard let id = item["id"] as? String else { continue }
            if item["deleted"] as? Bool == true {
                byID[id] = nil
                continue
            }
            guard let kind = item["kind"] as? String, Self.labels[kind] != nil, let text = item["text"] as? String, !text.isEmpty else { continue }
            byID[id] = Note(id: id, kind: kind, text: text, updated: item["updated"] as? String ?? "")
        }
        notes = Array(byID.values).sorted { $0.updated > $1.updated }.prefix(120).map { $0 }
        if let data = try? JSONEncoder().encode(notes) {
            defaults.set(data, forKey: key)
        }
    }

    static func words(_ text: String) -> Set<String> {
        let folded = text.replacingOccurrences(of: "œ", with: "oe")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
        let pieces = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 1 && !stopwords.contains($0) }
        return Set(pieces.map { $0.count > 4 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 })
    }

    /// The few memories that share words with `question`, in the PC's format.
    func contextLines(for question: String, limit: Int = 4) -> [String] {
        let asked = Self.words(question)
        guard !asked.isEmpty else { return [] }
        let ranked = notes
            .map { note in (note, Self.words(note.text).intersection(asked).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
        guard !ranked.isEmpty else { return [] }
        return ["Mémoire de Jarvis, à utiliser seulement si c'est pertinent :"] + ranked.map { "Souvenir (\(Self.labels[$0.0.kind] ?? $0.0.kind)) : \($0.0.text)" }
    }
}
