import Foundation

/// Jarvis's long-term memory on the iPhone, its main home: one Markdown note per thing worth
/// keeping (a preference, a habit, a fact, a correction), in the « Mémoire Jarvis » folder of
/// the app's documents, visible in the Files app (Sur mon iPhone › JARVIS) and readable as an
/// Obsidian vault. The iPhone learns by itself, even without the PC, with the same rules as
/// Jarvis PC (JarvisMemoryRules, written from pc/jarvis_pc/knowledge.py), and the two keep
/// the same memory over the home Wi-Fi: additions, changes and deletions travel both ways at
/// each synchronization (JarvisPCLink.synchronize). Only the notes relevant to a question are
/// given to the brain, never the whole memory.
final class JarvisKnowledgeStore {
    static let shared = JarvisKnowledgeStore()

    struct Note: Equatable {
        var id: String
        var kind: String
        var text: String
        var created: String
        var updated: String
        var source: String
        var question: String?
    }

    static let labels = ["preference": "préférence", "habitude": "habitude", "fait": "fait", "correction": "correction"]
    static let folderName = "Mémoire Jarvis"

    let folder: URL
    private let lock = NSLock()
    private var byID: [String: Note] = [:]
    /// Notes deleted here, told to the PC at the next synchronization.
    private(set) var deletedIDs: [String] = []
    private let deletedKey: String

    var notes: [Note] {
        lock.lock()
        defer { lock.unlock() }
        return byID.values.sorted { $0.updated > $1.updated }
    }

    init(folder: URL? = nil, defaults: UserDefaults = .standard) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.folder = folder ?? documents.appendingPathComponent(Self.folderName, isDirectory: true)
        deletedKey = "JarvisXR.knowledge.deleted." + self.folder.lastPathComponent
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        deletedIDs = defaults.stringArray(forKey: deletedKey) ?? []
        self.defaults = defaults
        load()
    }

    private let defaults: UserDefaults

    // MARK: Markdown files, as on the PC

    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func now() -> String { stamp.string(from: Date()) }

    private func url(for note: Note) -> URL {
        folder.appendingPathComponent("\(note.kind)-\(note.id.prefix(8)).md")
    }

    private func load() {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "md" {
            guard let text = try? String(contentsOf: file, encoding: .utf8), let note = Self.parse(text) else { continue }
            byID[note.id] = note
        }
    }

    static func parse(_ text: String) -> Note? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard normalized.hasPrefix("---\n"), let end = normalized.range(of: "\n---\n", range: normalized.index(normalized.startIndex, offsetBy: 4)..<normalized.endIndex) else { return nil }
        var header: [String: String] = [:]
        for line in normalized[normalized.index(normalized.startIndex, offsetBy: 4)..<end.lowerBound].split(separator: "\n") {
            guard let colon = line.range(of: ": ") else { continue }
            header[String(line[..<colon.lowerBound])] = String(line[colon.upperBound...])
        }
        var body = String(normalized[end.upperBound...])
        if let links = body.range(of: "\n\nLiens : ") { body = String(body[..<links.lowerBound]) }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let id = header["id"], let kind = header["kind"], labels[kind] != nil, !body.isEmpty else { return nil }
        var question: String?
        if let raw = header["question"], let data = raw.data(using: .utf8) {
            question = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) as? String
        }
        return Note(id: id, kind: kind, text: body, created: header["created"] ?? now(), updated: header["updated"] ?? now(),
                    source: header["source"] ?? "iphone", question: question)
    }

    static func render(_ note: Note) -> String {
        var header = ["id: \(note.id)", "kind: \(note.kind)", "created: \(note.created)", "updated: \(note.updated)", "uses: 0", "source: \(note.source)"]
        if let question = note.question, let data = try? JSONSerialization.data(withJSONObject: question, options: .fragmentsAllowed),
           let json = String(data: data, encoding: .utf8) {
            header.append("question: \(json)")
        }
        let links = entities(note.text).map { "[[\($0)]]" }.joined(separator: " ")
        return "---\n" + header.joined(separator: "\n") + "\n---\n" + note.text + (links.isEmpty ? "" : "\n\nLiens : " + links) + "\n"
    }

    private func save(_ note: Note) {
        try? Self.render(note).write(to: url(for: note), atomically: true, encoding: .utf8)
    }

    private func remove(_ note: Note) {
        byID[note.id] = nil
        try? FileManager.default.removeItem(at: url(for: note))
    }

    /// Names in a note: [[links]] and capitalized words that do not start a sentence.
    static func entities(_ text: String) -> [String] {
        var found: [String] = []
        if let regex = try? NSRegularExpression(pattern: "\\[\\[([^\\]]+)\\]\\]") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { found.append(String(text[range])) }
            }
        }
        if let regex = try? NSRegularExpression(pattern: "\\b([A-ZÀ-Ý][a-zà-ÿ]+(?:[ -][A-ZÀ-Ý][a-zà-ÿ]+)*)") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range(at: 1), in: text), range.lowerBound > text.startIndex else { continue }
                let before = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                if let last = before.last, ".!?".contains(last) { continue }
                let name = String(text[range])
                if !found.contains(name), !["Jarvis", "Monsieur", "JARVIS"].contains(name) { found.append(name) }
            }
        }
        return Array(found.prefix(8))
    }

    // MARK: Words

    /// Lowercase, no accents, « œ » → « oe », with each folded character mapped to the original.
    static func fold(_ text: String) -> (folded: String, origin: [Int], characters: [Character]) {
        let characters = Array(text)
        var folded = ""
        var origin: [Int] = []
        for (index, character) in characters.enumerated() {
            let piece = String(character).lowercased().replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
                .replacingOccurrences(of: "’", with: "'")
                .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            folded += piece
            origin.append(contentsOf: Array(repeating: index, count: piece.utf16.count))
        }
        return (folded, origin, characters)
    }

    static func tokens(_ text: String) -> [String] {
        let folded = fold(text).folded.replacingOccurrences(of: "'", with: " ")
        return folded.components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted)
            .filter { $0.count > 1 && !JarvisMemoryRules.stopwords.contains($0) }
            .map { $0.count > 4 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        let left = Set(tokens(a)), right = Set(tokens(b))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        return Double(left.intersection(right).count) / Double(left.union(right).count)
    }

    // MARK: Writing

    /// The note that already says the same thing, or the same subject with another value
    /// (« habite Paris » / « habite Lyon »): it is updated instead of duplicated.
    private func same(_ text: String, kind: String) -> Note? {
        var best: Note?
        var bestScore = 0.0
        let left = Self.tokens(text)
        for note in byID.values {
            guard note.kind == kind || (Set([note.kind, kind]).isSubset(of: ["fait", "correction"])) else { continue }
            var score = Self.similarity(text, note.text)
            let key = kind == "fait" || kind == "correction" ? 2 : 4
            let right = Self.tokens(note.text)
            if left.count > key, right.count > key, Array(left.prefix(key)) == Array(right.prefix(key)) { score = max(score, 0.7) }
            if score > bestScore { best = note; bestScore = score }
        }
        return bestScore >= 0.6 ? best : nil
    }

    @discardableResult
    func remember(_ text: String, kind: String, source: String = "iphone", question: String? = nil) -> Note {
        let clean = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        lock.lock()
        defer { lock.unlock() }
        let stamp = Self.now()
        var note = same(clean, kind: kind) ?? Note(id: UUID().uuidString.lowercased(), kind: kind, text: clean, created: stamp, updated: stamp,
                                                    source: source, question: question)
        note.text = clean
        note.updated = stamp
        note.source = source
        if let question { note.question = question }
        byID[note.id] = note
        save(note)
        return note
    }

    /// What the user just said about themselves, or a correction of the previous answer.
    @discardableResult
    func learn(said: String, previousQuestion: String? = nil) -> [Note] {
        let mapped = Self.fold(said)
        let folded = mapped.folded as NSString
        let whole = NSRange(location: 0, length: folded.length)
        func original(_ range: NSRange) -> String {
            guard range.location != NSNotFound, range.length > 0, range.location + range.length <= mapped.origin.count else { return "" }
            let start = mapped.origin[range.location], end = mapped.origin[range.location + range.length - 1] + 1
            return String(mapped.characters[start..<end]).trimmingCharacters(in: CharacterSet(charactersIn: " .!,?"))
        }
        var learned: [Note] = []
        if let previousQuestion, let regex = try? NSRegularExpression(pattern: JarvisMemoryRules.correction),
           let match = regex.firstMatch(in: mapped.folded, range: whole) {
            let right = original(match.range(at: 1))
            if right.count > 3 {
                learned.append(remember("À la question « \(previousQuestion) », la bonne réponse selon l'utilisateur : \(right).", kind: "correction",
                                        question: previousQuestion))
            }
        }
        guard !said.contains("?") else { return learned }
        for rule in JarvisMemoryRules.learning {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern), let match = regex.firstMatch(in: mapped.folded, range: whole) else { continue }
            let parts = (1..<match.numberOfRanges).map { original(match.range(at: $0)) }
            guard parts.allSatisfy({ $0.count >= 2 && $0.count <= 120 }) else { continue }
            var sentence = rule.template
            for (index, part) in parts.enumerated() { sentence = sentence.replacingOccurrences(of: "{\(index)}", with: part) }
            sentence = sentence.prefix(1).uppercased() + sentence.dropFirst()
            learned.append(remember(sentence, kind: rule.kind))
            break
        }
        return learned
    }

    /// « Oublie que j'aime le café »: the best matching note is deleted, here and on the PC.
    @discardableResult
    func forget(_ request: String) -> Note? {
        lock.lock()
        defer { lock.unlock() }
        let asked = Set(Self.tokens(request))
        guard let best = byID.values.max(by: { Set(Self.tokens($0.text)).intersection(asked).count < Set(Self.tokens($1.text)).intersection(asked).count }),
              !Set(Self.tokens(best.text)).intersection(asked).isEmpty else { return nil }
        remove(best)
        deletedIDs = Array((deletedIDs + [best.id]).suffix(200))
        defaults.set(deletedIDs, forKey: deletedKey)
        return best
    }

    // MARK: Wi-Fi synchronization with Jarvis PC

    /// Everything the PC must know: the notes (the most recent version wins there) and the deletions.
    func syncPayload() -> [[String: Any]] {
        var items: [[String: Any]] = notes.map { note in
            var item: [String: Any] = ["id": note.id, "kind": note.kind, "text": note.text, "updated": note.updated]
            if let question = note.question { item["question"] = question }
            return item
        }
        items += deletedIDs.map { ["id": $0, "deleted": true] }
        return items
    }

    /// The PC's merged memory: newer versions replace older ones, deletions are applied, and
    /// the deletions made here are forgotten once the PC has them.
    func adopt(_ items: [[String: Any]]) {
        lock.lock()
        defer { lock.unlock() }
        for item in items {
            guard let id = item["id"] as? String else { continue }
            if item["deleted"] as? Bool == true {
                if let known = byID[id] { remove(known) }
                continue
            }
            guard let kind = item["kind"] as? String, Self.labels[kind] != nil, let text = item["text"] as? String, !text.isEmpty else { continue }
            let updated = item["updated"] as? String ?? Self.now()
            if let known = byID[id], known.updated >= updated { continue }
            // The same memory learned on both devices (two ids): the most recent one is kept, once.
            if byID[id] == nil, let duplicate = same(text, kind: kind) {
                if duplicate.updated >= updated { continue }
                remove(duplicate)
            }
            let note = Note(id: id, kind: kind, text: text, created: byID[id]?.created ?? updated, updated: updated, source: "pc",
                            question: item["question"] as? String)
            byID[id] = note
            save(note)
        }
        deletedIDs = []
        defaults.set(deletedIDs, forKey: deletedKey)
    }

    // MARK: Reading

    /// The few memories that share words with `question`, in the PC's format.
    func contextLines(for question: String, limit: Int = 4) -> [String] {
        let asked = Set(Self.tokens(question))
        guard !asked.isEmpty else { return [] }
        let ranked = notes
            .map { note in (note, Set(Self.tokens(note.text)).intersection(asked).count) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
        guard !ranked.isEmpty else { return [] }
        return ["Mémoire de Jarvis, à utiliser seulement si c'est pertinent :"] + ranked.map { "Souvenir (\(Self.labels[$0.0.kind] ?? $0.0.kind)) : \($0.0.text)" }
    }
}
