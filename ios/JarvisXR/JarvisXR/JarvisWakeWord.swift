import Foundation

/// « Réveil par la voix » (Réglages): while Jarvis is open on its home screen and idle,
/// the microphone waits for « Jarvis… ». Off by default; recognition stays on the iPhone.
enum JarvisWakeWordSettings {
    static let enabledKey = "JarvisXR.wakeWordEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

/// Finds the request addressed to Jarvis in what the microphone heard.
enum JarvisWakeWord {
    /// How the French recognizer writes « Jarvis », lowercased and without accents.
    static let spellings: Set<String> = ["jarvis", "jarvisse", "jarviss", "jarvice", "djarvis", "jarvys"]

    /// Words that only call Jarvis: « Hey Jarvis », « Dis Jarvis », « Bonjour Jarvis ».
    private static let callWords: Set<String> = ["hey", "he", "eh", "ok", "okay", "dis", "dites", "bonjour", "salut", "allo", "alors"]

    /// The request in a transcript: the words after the last « Jarvis » (« Jarvis, quelle
    /// heure est-il ? »), or the words before it when nothing follows (« Quelle heure
    /// est-il, Jarvis ? »). "" when Jarvis is only called (« Jarvis ? »), nil when the
    /// transcript never says « Jarvis ».
    static func command(in transcript: String) -> String? {
        var lastRange: Range<String.Index>?
        transcript.enumerateSubstrings(in: transcript.startIndex..<transcript.endIndex, options: .byWords) { word, range, _, _ in
            guard let word else { return }
            let folded = word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).lowercased()
            if spellings.contains(folded) {
                lastRange = range
            }
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
