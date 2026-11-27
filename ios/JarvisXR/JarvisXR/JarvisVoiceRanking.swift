import AVFoundation

/// What the voice choice needs to know about an installed voice. Kept apart from
/// AVSpeechSynthesisVoice so the ranking can be tested with any list of voices.
struct JarvisVoiceCandidate: Equatable {
    let identifier: String
    let name: String
    let language: String
    /// 3 premium, 2 enhanced (« Améliorée » in iOS Settings), 1 standard.
    let quality: Int
    let isMale: Bool
    let isNovelty: Bool
    let isPersonal: Bool

    init(identifier: String, name: String, language: String, quality: Int, isMale: Bool, isNovelty: Bool = false, isPersonal: Bool = false) {
        self.identifier = identifier
        self.name = name
        self.language = language
        self.quality = quality
        self.isMale = isMale
        self.isNovelty = isNovelty
        self.isPersonal = isPersonal
    }

    init(_ voice: AVSpeechSynthesisVoice) {
        let quality: Int
        switch voice.quality {
        case .premium: quality = 3
        case .enhanced: quality = 2
        default: quality = 1
        }
        self.init(
            identifier: voice.identifier,
            name: voice.name,
            language: voice.language,
            quality: quality,
            isMale: voice.gender == .male,
            isNovelty: voice.voiceTraits.contains(.isNoveltyVoice),
            isPersonal: voice.voiceTraits.contains(.isPersonalVoice)
        )
    }

    /// Eloquence voices (Eddy, Flo, Jacques, Grand-père, Rocko…) come from an old formant
    /// synthesizer: understandable, but robotic. They are never a default when another
    /// French voice is installed.
    var isSynthetic: Bool { identifier.lowercased().contains("eloquence") }

    var qualityLabel: String {
        switch quality {
        case 3: return "premium"
        case 2: return "améliorée"
        default: return "standard"
        }
    }

    /// Line of the voice menu in Settings, for example « Thomas · améliorée · homme ».
    var menuTitle: String {
        var parts = [name, qualityLabel]
        if isMale { parts.append("homme") }
        if language != JarvisVoiceRanking.preferredLanguage {
            parts.append(JarvisVoiceRanking.regionName(of: language))
        }
        return parts.joined(separator: " · ")
    }
}

enum JarvisVoiceRanking {
    static let preferredLanguage = "fr-FR"

    /// French voices Jarvis may speak with, best first: France before the other French
    /// variants, then premium > enhanced > standard, then a male voice (closer to the
    /// Jarvis of the films), then the identifier, so the choice never changes between
    /// launches. Novelty and personal voices are never offered; the robotic Eloquence
    /// voices only when no other voice speaks French.
    static func ranked(_ voices: [JarvisVoiceCandidate], language: String = preferredLanguage) -> [JarvisVoiceCandidate] {
        let prefix = String(language.prefix(2))
        let french = voices.filter { $0.language.hasPrefix(prefix) && !$0.isNovelty && !$0.isPersonal }
        let natural = french.filter { !$0.isSynthetic }
        let pool = natural.isEmpty ? french : natural
        return pool.sorted { lhs, rhs in
            let left = key(lhs, language: language)
            let right = key(rhs, language: language)
            if left != right { return left > right }
            return lhs.identifier < rhs.identifier
        }
    }

    private static func key(_ voice: JarvisVoiceCandidate, language: String) -> (Int, Int, Int) {
        (voice.language == language ? 1 : 0, voice.quality, voice.isMale ? 1 : 0)
    }

    static func regionName(of language: String) -> String {
        switch language {
        case "fr-FR": return "France"
        case "fr-CA": return "Canada"
        case "fr-BE": return "Belgique"
        case "fr-CH": return "Suisse"
        default: return language
        }
    }
}
