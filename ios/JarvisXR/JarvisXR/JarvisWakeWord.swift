import Foundation

/// « Réveil par la voix » (Réglages): while Jarvis is open on its home screen and idle,
/// the microphone waits for « Jarvis… ». Off by default; recognition stays on the iPhone.
enum JarvisWakeWordSettings {
    static let enabledKey = "JarvisXR.wakeWordEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static let clapsKey = "JarvisXR.wakeClapsEnabled"

    /// Two hand claps also call Jarvis while it waits for « Jarvis ». On by default; it
    /// only works when the wake word option is on.
    static var clapsEnabled: Bool {
        get { UserDefaults.standard.object(forKey: clapsKey) == nil ? true : UserDefaults.standard.bool(forKey: clapsKey) }
        set { UserDefaults.standard.set(newValue, forKey: clapsKey) }
    }
}

/// Finds the request addressed to Jarvis in what the microphone heard.
enum JarvisWakeWord {
    /// How the French recognizer writes « Jarvis », lowercased and without accents.
    static let spellings: Set<String> = ["jarvis", "jarvisse", "jarviss", "jarvice", "djarvis", "jarvys"]

    /// Words that only call Jarvis: « Hey Jarvis », « Dis Jarvis », « Bonjour Jarvis ».
    private static let callWords: Set<String> = [
        "hey", "he", "eh", "ok", "okay", "dis", "dites", "bonjour", "salut", "allo", "alors", "bon", "euh", "oh", "ah", "allez", "coucou", "yo",
    ]

    /// « Dis Jarvis » is sometimes written as one word (« Dijarvis »).
    private static let callPrefixes = ["dis", "di", "hey", "he", "eh", "ok"]

    /// Punctuation the recognizer writes at a pause.
    private static let pauseMarks = CharacterSet(charactersIn: ".,;:!?…—–")

    /// One letter away from « jarvis », yet a French word.
    private static let notJarvis: Set<String> = ["parvis"]

    /// « jarvis », a letter off (« jardvis »), or run together with « dis » (« dijarvis »).
    /// The same rule as Jarvis PC (pc/jarvis_pc/wake.py).
    static func isJarvis(_ folded: String) -> Bool {
        if spellings.contains(folded) || looksLikeJarvis(folded) { return true }
        for prefix in callPrefixes where folded.hasPrefix(prefix) {
            let rest = String(folded.dropFirst(prefix.count))
            if spellings.contains(rest) || looksLikeJarvis(rest) { return true }
        }
        return false
    }

    private static func looksLikeJarvis(_ word: String) -> Bool {
        (5...8).contains(word.count) && !notJarvis.contains(word) && distance(word, "jarvis") <= 1
    }

    /// Edit distance: letters added, removed or changed.
    static func distance(_ a: String, _ b: String) -> Int {
        let left = Array(a)
        let right = Array(b)
        guard !left.isEmpty else { return right.count }
        guard !right.isEmpty else { return left.count }
        var previous = Array(0...right.count)
        for i in 1...left.count {
            var current = [i] + Array(repeating: 0, count: right.count)
            for j in 1...right.count {
                let change = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + change)
            }
            previous = current
        }
        return previous[right.count]
    }

    /// The request in a transcript: the words after the last « Jarvis » (« Jarvis, quelle
    /// heure est-il ? »), or the words before it when nothing follows (« Quelle heure
    /// est-il, Jarvis ? »). "" when Jarvis is only called (« Jarvis ? »), nil when the
    /// transcript never says « Jarvis ».
    ///
    /// « Jarvis » only counts when it is addressed: at the start, after a pause (the
    /// recognizer's punctuation) or after a call word. « J'en ai parlé à Jarvis hier » is
    /// about Jarvis, not to it, and runs nothing.
    static func command(in transcript: String) -> String? {
        var lastRange: Range<String.Index>?
        var previousEnd: String.Index?
        var previousWord = ""
        transcript.enumerateSubstrings(in: transcript.startIndex..<transcript.endIndex, options: .byWords) { word, range, _, _ in
            guard let word else { return }
            let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
            if isJarvis(folded) {
                let gap = previousEnd.map { String(transcript[$0..<range.lowerBound]) } ?? ""
                let afterPause = previousEnd == nil || gap.rangeOfCharacter(from: pauseMarks) != nil
                if afterPause || callWords.contains(previousWord) {
                    lastRange = range
                }
            }
            previousEnd = range.upperBound
            previousWord = folded
        }
        guard let lastRange else { return nil }
        let trimSet = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        let after = transcript[lastRange.upperBound...].trimmingCharacters(in: trimSet)
        guard after.isEmpty else { return after }
        let before = transcript[..<lastRange.lowerBound].trimmingCharacters(in: trimSet)
        let beforeWords = before
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }
        if beforeWords.isEmpty || beforeWords.allSatisfy({ callWords.contains($0) }) {
            return ""
        }
        return before
    }
}
