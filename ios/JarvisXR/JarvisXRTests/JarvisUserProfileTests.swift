import XCTest
@testable import JarvisXR

/// What Jarvis knows about the person: the first name, the notes it was asked to remember,
/// and what the local brain receives. Everything uses private stores, never the app's own.
final class JarvisUserProfileTests: XCTestCase {
    private var defaults: UserDefaults!
    private var memory: JarvisMemoryStore!
    private var profile: JarvisUserProfile!
    private var router: JarvisFrenchCommandRouter!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "JarvisUserProfileTests.\(UUID().uuidString)")
        memory = JarvisMemoryStore(defaults: defaults)
        profile = JarvisUserProfile(defaults: defaults)
        router = JarvisFrenchCommandRouter(memory: memory, scene: JarvisSpatialSceneMemory(), context: JarvisConversationContext(), profile: profile)
    }

    private func spoken(_ phrase: String) -> String? {
        guard case .answer(let response) = router.route(phrase) else { return nil }
        return response.spokenResponse
    }

    func testTheFirstNameIsLearnedRecalledAndForgotten() {
        XCTAssertEqual(spoken("Comment je m'appelle ?"), "Je ne connais pas encore votre prénom. Dites par exemple : « Je m'appelle Tony ».")
        XCTAssertEqual(spoken("Je m'appelle tony"), "Enchanté, Tony. Je m'en souviendrai.")
        XCTAssertEqual(profile.name, "Tony")
        XCTAssertEqual(spoken("Comment je m'appelle ?"), "Vous vous appelez Tony.")
        XCTAssertEqual(spoken("Bonjour Jarvis"), "Bonjour Tony ! Je vous écoute.")
        XCTAssertEqual(spoken("Oublie mon prénom"), "C'est oublié : je ne vous appellerai plus par votre prénom.")
        XCTAssertNil(profile.name)
        XCTAssertEqual(spoken("Bonjour Jarvis"), "Bonjour ! Je vous écoute.")
    }

    func testOtherWaysToGiveTheName() {
        XCTAssertEqual(spoken("Appelle-moi Jean-Marc"), "Enchanté, Jean-Marc. Je m'en souviendrai.")
        XCTAssertEqual(spoken("Jarvis, mon prénom est Tony Stark."), "Enchanté, Tony Stark. Je m'en souviendrai.")
        XCTAssertEqual(spoken("Je m’appelle Pepper"), "Enchanté, Pepper. Je m'en souviendrai.", "The typographic apostrophe of iOS dictation")
        XCTAssertEqual(profile.name, "Pepper")
    }

    func testSentencesThatAreNotNamesAreNotStored() {
        _ = router.route("Appelle-moi un taxi")
        _ = router.route("Appelle-moi dans 5 minutes")
        _ = router.route("Je m'appelle comment déjà ?")
        XCTAssertNil(profile.name)
        XCTAssertNil(JarvisUserProfile.cleanedName("quand tu as fini"))
        XCTAssertNil(JarvisUserProfile.cleanedName("une deux trois quatre"))
        XCTAssertEqual(JarvisUserProfile.cleanedName("jean-marc"), "Jean-Marc")
    }

    func testWhatJarvisKnowsAboutThePerson() {
        XCTAssertEqual(
            spoken("Qu'est-ce que tu sais sur moi ?"),
            "Je ne sais encore rien de vous. Dites « Je m'appelle… » ou « Souviens-toi que… » : je m'en souviendrai, ici sur l'iPhone."
        )
        _ = router.route("Je m'appelle Tony")
        _ = router.route("Souviens-toi que j'aime le café noir")
        _ = router.route("Retiens que ma voiture est au niveau 2")
        let summary = spoken("Que sais-tu de moi ?") ?? ""
        XCTAssertTrue(summary.hasPrefix("Vous vous appelez Tony."), summary)
        XCTAssertTrue(summary.contains("2 choses"), summary)
        XCTAssertTrue(summary.contains("ma voiture est au niveau 2 ; j'aime le café noir"), summary)
    }

    func testAWakeWordIsNotPartOfTheNote() {
        _ = router.route("Jarvis, prends une note acheter du pain")
        XCTAssertEqual(memory.loadNotes().first?.text, "acheter du pain")
    }

    func testTheBrainReceivesTheNameAndTheNotes() {
        XCTAssertTrue(profile.brainContextLines(memory: memory).isEmpty)
        profile.name = "Tony"
        _ = memory.saveNote("j'aime le café noir")
        _ = memory.saveNote("\(JarvisFrenchCommandRouter.trialNotePrefix) note d'essai")
        let lines = profile.brainContextLines(memory: memory)
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("s'appelle Tony"), lines[0])
        XCTAssertTrue(lines[1].contains("j'aime le café noir"), lines[1])
        XCTAssertFalse(lines[1].contains("note d'essai"), "Trial notes of the field scenario stay out of the brain")
        let system = JarvisChatPrompt.systemPrompt(now: Date(), context: lines)
        XCTAssertTrue(system.contains("j'aime le café noir"))
    }

    func testTheBrainContextStaysShort() {
        for index in 0..<20 {
            _ = memory.saveNote("Note numéro \(index) " + String(repeating: "texte ", count: 30))
        }
        let lines = profile.brainContextLines(memory: memory)
        XCTAssertEqual(lines.count, 1)
        XCTAssertLessThan(lines[0].count, 900, "A long list of notes must not crowd the brain's context")
    }
}
