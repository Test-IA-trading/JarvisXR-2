import XCTest
@testable import JarvisXR

/// Lot 3 — conversation that follows corrections, notes summary and its AR card,
/// hands-free conversation controls and the « Parler à JARVIS » route.
final class JarvisConversationBilanTests: XCTestCase {
    private var defaults: UserDefaults!
    private var memory: JarvisMemoryStore!
    private var context: JarvisConversationContext!
    private var router: JarvisFrenchCommandRouter!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "JarvisConversationBilanTests.\(UUID().uuidString)")
        memory = JarvisMemoryStore(defaults: defaults)
        context = JarvisConversationContext()
        router = JarvisFrenchCommandRouter(memory: memory, scene: JarvisSpatialSceneMemory(), context: context)
    }

    private func spoken(_ phrase: String, now: Date = Date()) -> String {
        guard case .answer(let response) = router.route(phrase, now: now) else {
            XCTFail("Expected a native answer for « \(phrase) »")
            return ""
        }
        return response.spokenResponse
    }

    private func answer(_ phrase: String, now: Date = Date()) -> JarvisResponse? {
        guard case .answer(let response) = router.route(phrase, now: now) else { return nil }
        return response
    }

    private func time(_ text: String) -> JarvisClockTime? {
        let tokens = JarvisFrenchCommandRouter.normalize(text).split(separator: " ").map(String.init)
        return JarvisFrenchTimeParser.times(in: tokens).first?.time
    }

    // MARK: French clock times

    func testFrenchClockTimesAreParsed() {
        XCTAssertEqual(time("neuf heures"), JarvisClockTime(hour: 9, minute: 0))
        XCTAssertEqual(time("9 h 30"), JarvisClockTime(hour: 9, minute: 30))
        XCTAssertEqual(time("à 21h15"), JarvisClockTime(hour: 21, minute: 15))
        XCTAssertEqual(time("à 21:15"), JarvisClockTime(hour: 21, minute: 15))
        XCTAssertEqual(time("midi"), JarvisClockTime(hour: 12, minute: 0))
        XCTAssertEqual(time("minuit"), JarvisClockTime(hour: 0, minute: 0))
        XCTAssertEqual(time("onze heures et demie"), JarvisClockTime(hour: 11, minute: 30))
        XCTAssertEqual(time("dix heures moins le quart"), JarvisClockTime(hour: 9, minute: 45))
        XCTAssertEqual(time("huit heures du soir"), JarvisClockTime(hour: 20, minute: 0))
        XCTAssertEqual(time("dix-sept heures quinze"), JarvisClockTime(hour: 17, minute: 15))
        XCTAssertEqual(time("vingt et une heures"), JarvisClockTime(hour: 21, minute: 0))
        XCTAssertNil(time("un téléphone neuf"))
    }

    func testClockTimesAreSpokenInFrench() {
        XCTAssertEqual(JarvisClockTime(hour: 12, minute: 0)?.spoken, "midi")
        XCTAssertEqual(JarvisClockTime(hour: 0, minute: 0)?.spoken, "minuit")
        XCTAssertEqual(JarvisClockTime(hour: 9, minute: 0)?.spoken, "9 h")
        XCTAssertEqual(JarvisClockTime(hour: 11, minute: 5)?.spoken, "11 h 05")
    }

    // MARK: Conversation that follows corrections

    func testTrainAndBusDialogueFollowsTheCorrection() {
        let first = spoken("Le train part à neuf heures et le bus à onze heures. Lequel part en premier ?")
        XCTAssertTrue(first.hasPrefix("Le train part en premier"), first)

        let second = spoken("En fait, le train part à midi. Et maintenant ?")
        XCTAssertTrue(second.contains("le bus qui part en premier"), second)
        XCTAssertTrue(second.contains("11 h"), second)

        XCTAssertEqual(spoken("Attends, juste l'heure du train"), "Midi.")
    }

    func testExplanationComparesBothDepartures() {
        _ = spoken("Le train part à 9 h et le bus à 11 h.")
        _ = spoken("Lequel part en premier ?")
        let explained = spoken("En fait, le train part à midi. Et maintenant ? Explique-moi pourquoi.")
        XCTAssertTrue(explained.contains("bus"), explained)
        XCTAssertTrue(explained.contains("avant le train à midi"), explained)
    }

    func testOtherObjectsAndTimesAreNotScripted() {
        XCTAssertEqual(spoken("La navette part à 7 h 45 et le car à 7 h 15. Lequel part en premier ?"), "Le car part en premier, à 7 h 15.")
        XCTAssertEqual(spoken("Et lequel part en dernier ?"), "La navette part en dernier, à 7 h 45.")
        let corrected = spoken("En fait, la navette part à 6 h 50. Et maintenant ?")
        XCTAssertEqual(corrected, "Maintenant, c'est le car qui part en dernier, à 7 h 15.")
        XCTAssertEqual(spoken("À quelle heure part la navette ?"), "6 h 50.")
    }

    func testPlaneWithElidedArticleAndEveningTime() {
        let reply = spoken("L'avion décolle à huit heures du soir et le train à 19 h 30. Lequel part en premier ?")
        XCTAssertEqual(reply, "Le train part en premier, à 19 h 30.")
    }

    func testSameTimeIsReportedAsATie() {
        XCTAssertEqual(spoken("Le car part à 8 h et le tram à huit heures. Lequel part en premier ?"), "Ils partent en même temps, à 8 h.")
    }

    func testClockStillAnswersWhenDeparturesAreKnown() {
        _ = spoken("Le train part à 9 h et le bus à 11 h.")
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 25; components.hour = 14; components.minute = 7
        let now = Calendar.current.date(from: components)!
        XCTAssertEqual(spoken("Quelle heure est-il ?", now: now), "Il est 14 h 07.")
    }

    // MARK: Notes summary

    private func seedThreeNotes(now: Date) {
        memory.saveNote("Note du matin", createdAt: now.addingTimeInterval(-3 * 3600))
        memory.saveNote("Note de midi", createdAt: now.addingTimeInterval(-20 * 60))
        memory.saveNote("Note ancienne", createdAt: now.addingTimeInterval(-8 * 86_400))
    }

    func testSevenDaySummaryCountsOnlyRecentNotesAndShowsThem() throws {
        let now = Date()
        seedThreeNotes(now: now)
        XCTAssertEqual(spoken("Combien de notes ai-je prises ces sept derniers jours ?", now: now), "Vous avez pris 2 notes ces 7 derniers jours.")

        let list = try XCTUnwrap(answer("Montre-les-moi", now: now))
        XCTAssertEqual(list.spokenResponse, "Voici les 2 notes ces 7 derniers jours.")
        XCTAssertTrue(list.displayResponse.contains("Note du matin"))
        XCTAssertTrue(list.displayResponse.contains("Note de midi"))
        XCTAssertFalse(list.displayResponse.contains("Note ancienne"), "The note from eight days ago is outside the period.")

        let card = try XCTUnwrap(answer("Pose ce bilan sur la table", now: now))
        XCTAssertEqual(card.data["action"], "ar_summary")
        XCTAssertEqual(card.data["summary_value"], "2", "The card shows the same total as the spoken answer.")
        XCTAssertEqual(JarvisARSummaryCard(data: card.data)?.value, "2")
    }

    func testDigitsAndZeroNotes() {
        let now = Date()
        XCTAssertEqual(spoken("Combien de notes ces 7 derniers jours ?", now: now), "Vous n'avez pris aucune note ces 7 derniers jours.")
        memory.saveNote("Aujourd'hui", createdAt: now.addingTimeInterval(-60))
        XCTAssertEqual(spoken("Combien de notes aujourd'hui ?", now: now), "Vous avez pris une note aujourd'hui.")
    }

    func testTrialNotesReproduceTheFieldScenario() {
        let now = Date()
        XCTAssertTrue(spoken("Prépare l'essai du bilan", now: now).contains("Trois notes d'essai"))
        XCTAssertEqual(memory.loadNotes().count, 3)
        XCTAssertEqual(spoken("Combien de notes ai-je prises ces sept derniers jours ?", now: now), "Vous avez pris 2 notes ces 7 derniers jours.")
        _ = spoken("Efface les notes d'essai", now: now)
        XCTAssertTrue(memory.loadNotes().isEmpty)
    }

    func testMissingDataIsStatedInsteadOfInvented() {
        let reply = spoken("Combien de téléchargements a eu mon application cette semaine ?")
        XCTAssertTrue(reply.contains("pas accès"), reply)
    }

    func testClosingTheSummaryCard() {
        XCTAssertEqual(answer("Ferme la fiche du bilan")?.data["action"], "ar_summary_close")
    }

    // MARK: Conversation controls and shortcuts

    func testConversationCanBeEndedAndToggled() {
        let original = JarvisConversationSettings.isContinuous
        defer { JarvisConversationSettings.isContinuous = original }
        XCTAssertEqual(answer("Merci, c'est tout")?.data["mode"], "conversation_end")
        _ = answer("Désactive la conversation continue")
        XCTAssertFalse(JarvisConversationSettings.isContinuous)
        _ = answer("Active la conversation continue")
        XCTAssertTrue(JarvisConversationSettings.isContinuous)
    }

    func testListenRouteOpensTheMicrophone() throws {
        let url = try XCTUnwrap(URL(string: "jarvis://listen"))
        guard case .listen = JarvisDeepLinkRouter.action(from: url) else {
            return XCTFail("jarvis://listen must open the microphone")
        }
    }

    func testHomeStateLabelsAreFrench() {
        XCTAssertEqual(JarvisInteractionState.ready.displayName, "Prêt")
        XCTAssertEqual(JarvisInteractionState.listening.displayName, "À l'écoute")
        XCTAssertEqual(JarvisInteractionState.ready.rawValue, "Ready", "The technical identifier stays stable.")
    }
}
