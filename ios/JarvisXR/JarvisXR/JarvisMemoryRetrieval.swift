import Foundation
import NaturalLanguage

/// French words reduced to what they mean for Jarvis's memory, with what iOS already has on
/// the iPhone, free and offline: lemmas (« bois », « boit » → « boire ») and the meaning of a
/// sentence (Apple's French sentence embedding). They find a memory said in other words
/// (docs/VISION_JARVIS.md §8.4, §8.5). Thread-safe.
enum JarvisLanguageTools {
    private static let lock = NSLock()
    private static let tagger = NLTagger(tagSchemes: [.lemma])
    /// nil when iOS has no French sentence model: the words alone are compared.
    private static let embedding: NLEmbedding? = NLEmbedding.sentenceEmbedding(for: .french)

    static var hasMeaning: Bool { embedding != nil }

    /// The lemma of each word of `text`, in order (the word itself when iOS has none).
    static func lemmas(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        tagger.string = text
        tagger.setLanguage(.french, range: text.startIndex..<text.endIndex)
        var words: [String] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma,
                             options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, range in
            if let lemma = tag?.rawValue, !lemma.isEmpty {
                words.append(lemma)
            } else {
                words.append(String(text[range]))
            }
            return true
        }
        return words
    }

    /// The meaning of a sentence as a vector, nil without French sentence model.
    static func meaning(_ text: String) -> [Double]? {
        guard let embedding, !text.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return embedding.vector(for: text)
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot = 0.0, left = 0.0, right = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            left += a[index] * a[index]
            right += b[index] * b[index]
        }
        guard left > 0, right > 0 else { return 0 }
        return dot / (left.squareRoot() * right.squareRoot())
    }
}

/// Every exchange with Jarvis, kept by default in the memory folder as one Markdown page per
/// day (« Mémoire Jarvis/Conversations/2026-11-27.md »), readable in Files and Obsidian
/// (§8.1). Stays on the iPhone; never in the public repository. Off with
/// « Ne garde plus nos conversations », erased with « Efface l'historique des conversations ».
/// Message bodies are never written (the same rule as the general history).
final class JarvisConversationJournal {
    static let shared = JarvisConversationJournal()
    static let enabledKey = "JarvisXR.conversationJournal"
    static let folderName = "Conversations"

    let folder: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "jarvis.conversation-journal", qos: .utility)

    init(memoryFolder: URL? = nil, defaults: UserDefaults = .standard) {
        let base = memoryFolder ?? JarvisKnowledgeStore.shared.folder
        folder = base.appendingPathComponent(Self.folderName, isDirectory: true)
        self.defaults = defaults
    }

    /// On by default (the person asked Jarvis to keep its conversations, §8.1).
    var isEnabled: Bool {
        get { defaults.object(forKey: Self.enabledKey) == nil ? true : defaults.bool(forKey: Self.enabledKey) }
        set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    private static let dayFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    func file(for day: Date) -> URL {
        folder.appendingPathComponent(Self.dayFormat.string(from: day) + ".md")
    }

    /// Adds one exchange to today's page. `channel`: « voix » or « clavier ».
    func record(user: String, jarvis: String, channel: String, at date: Date = Date(), completion: (() -> Void)? = nil) {
        let said = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = jarvis.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isEnabled, !said.isEmpty else {
            completion?()
            return
        }
        let url = file(for: date)
        let folder = self.folder
        let header = "# Conversations du \(Self.dayFormat.string(from: date))\n\nJournal local de Jarvis (iPhone). [[Mémoire Jarvis]]\n"
        let entry = "\n## \(Self.timeFormat.string(from: date)) · \(channel)\n**Vous :** \(said)\n\n**Jarvis :** \(answer.isEmpty ? "(sans réponse parlée)" : answer)\n"
        queue.async {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data(entry.utf8))
                try? handle.close()
            } else {
                try? (header + entry).write(to: url, atomically: true, encoding: .utf8)
            }
            completion?()
        }
    }

    /// Days kept, most recent first.
    func days() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Erases every page; returns how many there were.
    @discardableResult
    func eraseAll() -> Int {
        queue.sync {
            let pages = days()
            pages.forEach { try? FileManager.default.removeItem(at: $0) }
            return pages.count
        }
    }
}
