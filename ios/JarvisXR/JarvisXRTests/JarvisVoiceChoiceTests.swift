import XCTest
@testable import JarvisXR

/// The voice Jarvis speaks with: never the robotic Eloquence voices when a natural French
/// voice is installed, the best quality first, and a male voice when quality is equal.
final class JarvisVoiceChoiceTests: XCTestCase {
    private func voice(
        _ identifier: String,
        _ name: String,
        language: String = "fr-FR",
        quality: Int = 1,
        male: Bool = false,
        novelty: Bool = false,
        personal: Bool = false
    ) -> JarvisVoiceCandidate {
        JarvisVoiceCandidate(identifier: identifier, name: name, language: language, quality: quality, isMale: male, isNovelty: novelty, isPersonal: personal)
    }

    private var eddy: JarvisVoiceCandidate { voice("com.apple.eloquence.fr-FR.Eddy", "Eddy", male: true) }
    private var jacques: JarvisVoiceCandidate { voice("com.apple.eloquence.fr-FR.Jacques", "Jacques", male: true) }
    private var thomasCompact: JarvisVoiceCandidate { voice("com.apple.voice.compact.fr-FR.Thomas", "Thomas", male: true) }
    private var thomasEnhanced: JarvisVoiceCandidate { voice("com.apple.voice.enhanced.fr-FR.Thomas", "Thomas", quality: 2, male: true) }
    private var audreyEnhanced: JarvisVoiceCandidate { voice("com.apple.voice.enhanced.fr-FR.Audrey", "Audrey", quality: 2) }
    private var audreyPremium: JarvisVoiceCandidate { voice("com.apple.voice.premium.fr-FR.Audrey", "Audrey", quality: 3) }
    private var amelieEnhanced: JarvisVoiceCandidate { voice("com.apple.voice.enhanced.fr-CA.Amelie", "Amélie", language: "fr-CA", quality: 2) }

    func testRoboticEloquenceVoicesAreSkippedWhenANaturalVoiceExists() {
        // The bug behind « cette voix horrible » : equal voices were taken in list order,
        // and the Eloquence voices (Eddy, Jacques…) come first in that list.
        let ranked = JarvisVoiceRanking.ranked([eddy, jacques, thomasCompact])
        XCTAssertEqual(ranked.map(\.identifier), [thomasCompact.identifier])
        XCTAssertTrue(eddy.isSynthetic)
        XCTAssertFalse(thomasCompact.isSynthetic)
    }

    func testOnlyEloquenceVoicesStillSpeakFrench() {
        let ranked = JarvisVoiceRanking.ranked([jacques, eddy])
        XCTAssertEqual(ranked.map(\.name), ["Eddy", "Jacques"], "With nothing else installed, a French voice is still better than silence.")
    }

    func testFranceFirstThenQualityThenAMaleVoice() {
        let ranked = JarvisVoiceRanking.ranked([amelieEnhanced, thomasCompact, audreyEnhanced, thomasEnhanced])
        XCTAssertEqual(ranked.map(\.identifier), [
            thomasEnhanced.identifier,   // fr-FR, enhanced, male
            audreyEnhanced.identifier,   // fr-FR, enhanced
            thomasCompact.identifier,    // fr-FR, standard
            amelieEnhanced.identifier,   // Canada comes after every voice of France
        ])
    }

    func testPremiumBeatsAnEnhancedMaleVoice() {
        let ranked = JarvisVoiceRanking.ranked([thomasEnhanced, audreyPremium])
        XCTAssertEqual(ranked.first, audreyPremium)
    }

    func testNoveltyPersonalAndForeignVoicesAreNeverOffered() {
        let ranked = JarvisVoiceRanking.ranked([
            voice("com.apple.speech.synthesis.voice.Bells", "Bells", novelty: true),
            voice("personal.voice.1", "Ma voix", personal: true),
            voice("com.apple.voice.premium.en-US.Ava", "Ava", language: "en-US", quality: 3),
        ])
        XCTAssertTrue(ranked.isEmpty)
    }

    func testTheChoiceDoesNotDependOnTheListOrder() {
        let voices = [eddy, amelieEnhanced, thomasCompact, audreyEnhanced, thomasEnhanced, jacques]
        let expected = JarvisVoiceRanking.ranked(voices).map(\.identifier)
        XCTAssertEqual(JarvisVoiceRanking.ranked(Array(voices.reversed())).map(\.identifier), expected)
        XCTAssertEqual(JarvisVoiceRanking.ranked(voices.shuffled()).map(\.identifier), expected)
    }

    func testMenuTitlesNameTheQualityTheGenderAndTheRegion() {
        XCTAssertEqual(thomasEnhanced.menuTitle, "Thomas · améliorée · homme")
        XCTAssertEqual(audreyPremium.menuTitle, "Audrey · premium")
        XCTAssertEqual(amelieEnhanced.menuTitle, "Amélie · améliorée · Canada")
    }

    func testChosenVoiceIsRememberedAndAutomaticCanBeRestored() {
        let speech = JarvisSpeechService.shared
        let original = speech.chosenVoiceIdentifier
        defer { speech.chosenVoiceIdentifier = original }
        speech.chosenVoiceIdentifier = "com.apple.voice.enhanced.fr-FR.Thomas"
        XCTAssertEqual(speech.chosenVoiceIdentifier, "com.apple.voice.enhanced.fr-FR.Thomas")
        speech.chosenVoiceIdentifier = nil
        XCTAssertNil(speech.chosenVoiceIdentifier)
    }

    func testInstalledVoicesOfferedInSettingsAreFrenchAndNeverNovelty() {
        for choice in JarvisSpeechService.shared.frenchVoiceChoices() {
            XCTAssertTrue(choice.language.hasPrefix("fr"), choice.identifier)
            XCTAssertFalse(choice.isNovelty, choice.identifier)
            XCTAssertFalse(choice.isPersonal, choice.identifier)
        }
    }

    func testTheHintExplainsWhereToDownloadANaturalVoice() {
        let hint = JarvisSpeechService.betterVoiceHint
        XCTAssertTrue(hint.contains("Contenu énoncé"))
        XCTAssertTrue(hint.contains("Améliorée"))
        XCTAssertTrue(hint.contains("Premium"))
    }

    func testTheDefaultProfileKeepsTheVoicePitch() {
        let speech = JarvisSpeechService.shared
        let original = speech.profile
        defer { speech.profile = original }
        speech.profile = .natural
        XCTAssertEqual(speech.pitch, 1.0, accuracy: 0.0001)
    }
}
