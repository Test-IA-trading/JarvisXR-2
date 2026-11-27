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
        /// When a kept answer stops being reused (ISO 8601, as on the PC); nil: durable.
        var expires: String? = nil
        /// How a kept answer was obtained: « source » (Wikipédia…) or « genere » (a model's own words).
        var verification: String? = nil
    }

    /// « reponse »: an answer kept to answer the same question at once (§8.3), with its
    /// provenance, date and validity; never synchronized as a fact.
    static let labels = ["preference": "préférence", "habitude": "habitude", "fait": "fait", "correction": "correction", "reponse": "réponse mémorisée"]
    static let durableKinds: Set<String> = ["preference", "habitude", "fait", "correction"]
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
                    source: header["source"] ?? "iphone", question: question, expires: header["expires"], verification: header["verification"])
    }

    static func render(_ note: Note) -> String {
        var header = ["id: \(note.id)", "kind: \(note.kind)", "created: \(note.created)", "updated: \(note.updated)", "uses: 0", "source: \(note.source)"]
        if let question = note.question, let data = try? JSONSerialization.data(withJSONObject: question, options: .fragmentsAllowed),
           let json = String(data: data, encoding: .utf8) {
            header.append("question: \(json)")
        }
        if let expires = note.expires { header.append("expires: \(expires)") }
        if let verification = note.verification { header.append("verification: \(verification)") }
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
            // An answer kept for that question was just contradicted: it is not reused any more.
            dropKeptAnswer(for: previousQuestion)
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
        // Kept answers stay on the iPhone: the PC checks and keeps its own (knowledge.py).
        var items: [[String: Any]] = notes.filter { Self.durableKinds.contains($0.kind) }.map { note in
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

    /// Words of a text for the search: its own words and their French lemmas (« boit » and
    /// « bois » share « boire »), folded, without the little words.
    static func words(of text: String) -> Set<String> {
        Set(tokens(text)).union(tokens(JarvisLanguageTools.lemmas(text).joined(separator: " ")))
    }

    /// Below this closeness of meaning, a memory that shares no word is not given. To calibrate
    /// on the iPhone (Apple's French sentence model, docs/BENCHMARKS.md).
    static let meaningThreshold = 0.85

    private var wordCache: [String: (version: String, words: Set<String>)] = [:]
    private var meaningCache: [String: (version: String, vector: [Double]?)] = [:]

    /// Under `lock`.
    private func cachedWords(_ note: Note) -> Set<String> {
        if let known = wordCache[note.id], known.version == note.updated + note.text { return known.words }
        let words = Self.words(of: note.text + " " + (note.question ?? ""))
        wordCache[note.id] = (note.updated + note.text, words)
        return words
    }

    /// Under `lock`.
    private func cachedMeaning(_ note: Note) -> [Double]? {
        if let known = meaningCache[note.id], known.version == note.updated + note.text { return known.vector }
        let vector = JarvisLanguageTools.meaning(note.question ?? note.text)
        meaningCache[note.id] = (note.updated + note.text, vector)
        return vector
    }

    static func isExpired(_ note: Note, now: Date = Date()) -> Bool {
        guard let expires = note.expires, let end = stamp.date(from: expires) ?? ISO8601DateFormatter().date(from: expires) else { return false }
        return end < now
    }

    /// The memories that answer `question`, best first: the words and lemmas they share,
    /// rare ones counting more; then, with no shared word, a very close meaning (the same
    /// thing said otherwise). Kept answers only when `kinds` asks for them.
    func relevant(to question: String, limit: Int = 4, kinds: Set<String> = JarvisKnowledgeStore.durableKinds) -> [Note] {
        let asked = Self.words(of: question)
        let askedMeaning = JarvisLanguageTools.meaning(question)
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        let candidates = byID.values.filter { kinds.contains($0.kind) && !Self.isExpired($0, now: now) }
        guard !candidates.isEmpty, !asked.isEmpty || askedMeaning != nil else { return [] }
        let noteWords = candidates.map { cachedWords($0) }
        var frequency: [String: Int] = [:]
        noteWords.forEach { $0.forEach { frequency[$0, default: 0] += 1 } }
        let count = Double(candidates.count)
        var scored: [(note: Note, score: Double)] = []
        for (index, note) in candidates.enumerated() {
            var score = noteWords[index].intersection(asked).reduce(0.0) { $0 + log(1 + count / Double(frequency[$1] ?? 1)) }
            if let askedMeaning, let vector = cachedMeaning(note) {
                let closeness = JarvisLanguageTools.cosine(askedMeaning, vector)
                if score > 0 {
                    score += 0.5 * max(0, closeness)
                } else if closeness >= Self.meaningThreshold {
                    score = closeness
                }
            }
            if score > 0 { scored.append((note, score)) }
        }
        let ranked = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.note.updated > $1.note.updated }
        lastConsulted = min(limit, ranked.count)
        return ranked.prefix(limit).map { $0.note }
    }

    /// Computes the words and meanings of every memory once, off the main queue at launch.
    func warmUp() {
        _ = relevant(to: "préférences et habitudes", limit: 1)
    }

    /// How many memories the last search gave (Diagnostics: the memory really consulted).
    private(set) var lastConsulted = 0

    /// The few memories relevant to `question`, in the PC's format, with their date.
    func contextLines(for question: String, limit: Int = 4) -> [String] {
        let found = relevant(to: question, limit: limit)
        guard !found.isEmpty else { return [] }
        return ["Mémoire de Jarvis (dossier « Mémoire Jarvis » de l'iPhone), à utiliser seulement si c'est pertinent :"]
            + found.map { "Souvenir (\(Self.labels[$0.kind] ?? $0.kind), \(Self.day($0.updated))) : \($0.text)" }
    }

    static func day(_ stampText: String) -> String {
        guard let date = stamp.date(from: stampText) else { return String(stampText.prefix(10)) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    // MARK: Kept answers (a question asked again is answered at once, §8.3)

    /// Words of a request, not of its meaning: « Explique-moi » and « C'est quoi » ask the same.
    static let requestWords: Set<String> = [
        "explique", "expliquer", "dire", "parle", "parler", "definis", "definir", "definition", "savoir", "sai", "sais", "connais",
        "connaitre", "pouvoir", "pourrai", "pourrais", "vouloir", "voudrai", "voudrais", "etre", "avoir", "est-ce", "estce", "ceci",
        "donc", "alor", "alors", "stp", "svp", "plait", "merci", "rapidement", "simplement", "exactement", "vraiment",
    ]

    /// What the person, the conversation or the moment changes: such a question is never
    /// answered from memory (« mon », « celle-là », « hier »…; the weather is in `volatile`).
    static let personalOrContextual = [
        " je ", " j'", " mon ", " ma ", " mes ", " nous ", " notre ", " nos ", " on ", " sur moi", " de moi", " pour moi", " chez moi",
        " a moi", " avec moi", " ca ", " cela", " ceci", " celui", " celle", " ceux", " autre", " le premier", " la premiere",
        " le deuxieme", " le second", " le dernier", " la derniere", " hier", " recemment", " dernierement", " cette annee", " ce mois",
        " ici", " encore", " plus simple", " plus court", " en anglais", " resume", " traduis", " continue", " reprends",
    ]

    /// A question made of these alone (« Pourquoi ? », « Combien ? ») follows the conversation.
    static let interrogatives: Set<String> = ["pourquoi", "combien", "quand", "lequel", "laquelle", "lesquels", "lesquelles", "dont"]

    /// Meaningful words of a question, sorted: two wordings of the same question share them.
    static func questionKey(_ question: String) -> String {
        words(of: question).subtracting(requestWords).sorted().joined(separator: " ")
    }

    static func isReusable(_ question: String) -> Bool {
        var folded = fold(question).folded
        for mark in ["-", "?", "!", ",", ".", ";", ":", "«", "»"] { folded = folded.replacingOccurrences(of: mark, with: " ") }
        folded = " " + folded + " "
        guard question.count >= 12, !JarvisMemoryRules.volatile.contains(where: { folded.contains($0) }),
              !personalOrContextual.contains(where: { folded.contains($0) }) else { return false }
        return !words(of: question).subtracting(requestWords).subtracting(interrogatives).isEmpty
    }

    /// The answer kept for the same question, still valid (nil for what changes quickly).
    func keptAnswer(for question: String) -> Note? {
        guard Self.isReusable(question) else { return nil }
        let key = Self.questionKey(question)
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        return byID.values.filter { $0.kind == "reponse" && !Self.isExpired($0, now: now) }
            .sorted { $0.updated > $1.updated }
            .first { Self.questionKey($0.question ?? "") == key }
    }

    /// Keeps the answer to an open question so the same question is answered at once next
    /// time; `verified`: it comes from a source (Wikipédia…), kept 30 days, otherwise 7.
    @discardableResult
    func keepAnswer(question: String, answer: String, source: String, verified: Bool, now: Date = Date()) -> Note? {
        let clean = answer.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard Self.isReusable(question), clean.count >= 20, clean.count <= 1_500 else { return nil }
        let key = Self.questionKey(question)
        let days = verified ? Double(JarvisMemoryRules.answerLifetimeDays) : 7
        let stampText = Self.stamp.string(from: now)
        lock.lock()
        defer { lock.unlock() }
        var note = byID.values.first { $0.kind == "reponse" && Self.questionKey($0.question ?? "") == key }
            ?? Note(id: UUID().uuidString.lowercased(), kind: "reponse", text: clean, created: stampText, updated: stampText, source: source, question: question)
        note.text = clean
        note.updated = stampText
        note.source = source
        note.question = question
        note.expires = Self.stamp.string(from: now.addingTimeInterval(days * 86_400))
        note.verification = verified ? "source" : "genere"
        byID[note.id] = note
        save(note)
        return note
    }

    /// Where a kept answer comes from, for the screen (§8.4: provenance, date, verification).
    static func provenance(of note: Note) -> String {
        let how = note.verification == "source" ? "vérifiée (\(note.source))" : "écrite par \(note.source), non vérifiée"
        return "Réponse mémorisée le \(day(note.updated)), \(how)."
    }

    private func dropKeptAnswer(for question: String) {
        let key = Self.questionKey(question)
        guard !key.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        for note in byID.values where note.kind == "reponse" && Self.questionKey(note.question ?? "") == key {
            remove(note)
        }
    }

    // MARK: What Jarvis says about its memory

    /// A memory said to the person (« L'utilisateur aime le jazz. » → « vous aimez le jazz »).
    static func spokenToUser(_ text: String) -> String {
        var value = text.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if let range = value.range(of: #"^(.+?) de l'utilisateur : "#, options: .regularExpression), !value.hasPrefix("Habitude") {
            let subject = value[range].replacingOccurrences(of: " de l'utilisateur : ", with: "")
            value = "votre \(subject.prefix(1).lowercased())\(subject.dropFirst()) : \(value[range.upperBound...])"
        }
        let replacements = [
            ("L'utilisateur n'aime pas", "vous n'aimez pas"), ("L'utilisateur préfère", "vous préférez"), ("L'utilisateur aime", "vous aimez"),
            ("L'utilisateur veut être appelé", "vous voulez être appelé"), ("L'utilisateur veut des réponses", "vous voulez des réponses"),
            ("L'utilisateur habite", "vous habitez"), ("L'utilisateur travaille", "vous travaillez"), ("L'utilisateur est né", "vous êtes né"),
            ("L'anniversaire de l'utilisateur est", "votre anniversaire est"), ("Habitude de l'utilisateur :", "votre habitude :"),
            ("la bonne réponse selon l'utilisateur", "la bonne réponse selon vous"),
        ]
        for (from, to) in replacements where value.contains(from) {
            value = value.replacingOccurrences(of: from, with: to)
        }
        return value
    }

    /// How many durable memories of each kind, in words (« 3 préférences, 2 faits »).
    func inventory() -> (count: Int, words: String, kept: Int) {
        let all = notes
        let durable = all.filter { Self.durableKinds.contains($0.kind) }
        let plural = ["preference": "préférences", "habitude": "habitudes", "fait": "faits", "correction": "corrections"]
        let parts = ["preference", "fait", "habitude", "correction"].compactMap { kind -> String? in
            let number = durable.filter { $0.kind == kind }.count
            guard number > 0 else { return nil }
            return "\(number) \(number == 1 ? (Self.labels[kind] ?? kind) : (plural[kind] ?? kind))"
        }
        let words = parts.count <= 1 ? parts.joined() : parts.dropLast().joined(separator: ", ") + " et " + (parts.last ?? "")
        let now = Date()
        return (durable.count, words, all.filter { $0.kind == "reponse" && !Self.isExpired($0, now: now) }.count)
    }

    // MARK: Erasing everything (« Réinitialise ta mémoire », after confirmation)

    /// Deletes every note of the folder and the deletions waiting for the PC; returns how
    /// many notes there were. The PC's own copy is erased by its own command (docs).
    @discardableResult
    func eraseAll() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let count = byID.count
        for note in Array(byID.values) { remove(note) }
        wordCache = [:]
        meaningCache = [:]
        deletedIDs = []
        defaults.set(deletedIDs, forKey: deletedKey)
        return count
    }
}
