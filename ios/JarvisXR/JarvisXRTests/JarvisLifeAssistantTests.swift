import XCTest
@testable import JarvisXR

/// Lot 6 — timers, reminders, agenda and briefing, without touching the real
/// notification centre or calendars (those run only on the iPhone, after permission).
final class JarvisLifeAssistantTests: XCTestCase {
    private var timers: JarvisTimerStore!
    private var router: JarvisFrenchCommandRouter!
    /// Wednesday 25 November 2026, 10:00.
    private var now: Date!

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults(suiteName: "JarvisLifeAssistantTests.\(UUID().uuidString)")!
        timers = JarvisTimerStore(defaults: defaults)
        router = JarvisFrenchCommandRouter(
            memory: JarvisMemoryStore(defaults: defaults),
            scene: JarvisSpatialSceneMemory(),
            context: JarvisConversationContext(),
            screen: JarvisScreenContext(),
            timers: timers
        )
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 25; components.hour = 10; components.minute = 0
        now = Calendar.current.date(from: components)!
    }

    private func tokens(_ text: String) -> [String] {
        JarvisFrenchCommandRouter.normalize(text).split(separator: " ").map(String.init)
    }

    private func answer(_ phrase: String) -> JarvisResponse? {
        guard case .answer(let response) = router.route(phrase, now: now) else { return nil }
        return response
    }

    // MARK: Durations and days

    func testFrenchDurationsAreParsed() {
        func seconds(_ text: String) -> TimeInterval? { JarvisFrenchDurationParser.durations(in: tokens(text)).first?.seconds }
        XCTAssertEqual(seconds("10 minutes"), 600)
        XCTAssertEqual(seconds("une heure et demie"), 5_400)
        XCTAssertEqual(seconds("1 h 30"), 5_400)
        XCTAssertEqual(seconds("1h30"), 5_400)
        XCTAssertEqual(seconds("45 secondes"), 45)
        XCTAssertEqual(seconds("un quart d'heure"), 900)
        XCTAssertEqual(seconds("une demi-heure"), 1_800)
        XCTAssertEqual(seconds("2 heures 15"), 8_100)
        XCTAssertEqual(seconds("10 minutes 30 secondes"), 630)
        XCTAssertNil(seconds("le train part à 9 h"), "A clock time is not a duration.")
    }

    func testDurationsAreSpokenInFrench() {
        XCTAssertEqual(JarvisFrenchDurationParser.spoken(600), "10 minutes")
        XCTAssertEqual(JarvisFrenchDurationParser.spoken(5_400), "1 heure 30")
        XCTAssertEqual(JarvisFrenchDurationParser.spoken(3_600), "1 heure")
        XCTAssertEqual(JarvisFrenchDurationParser.spoken(45), "45 secondes")
        XCTAssertEqual(JarvisFrenchDurationParser.spoken(125), "2 minutes 5")
    }

    func testDaysAreResolvedFromWednesday() {
        func offset(_ text: String) -> Int? { JarvisFrenchDayParser.day(in: tokens(text), now: now)?.dayOffset }
        XCTAssertEqual(offset("aujourd'hui"), 0)
        XCTAssertEqual(offset("demain"), 1)
        XCTAssertEqual(offset("après-demain"), 2)
        XCTAssertEqual(offset("vendredi"), 2)
        XCTAssertEqual(offset("mercredi"), 7, "Naming today's weekday means next week.")
        XCTAssertEqual(offset("lundi prochain"), 5)
    }

    // MARK: Timers

    func testNamedTimerStartsAndReportsWhatIsLeft() throws {
        let start = try XCTUnwrap(answer("Mets un minuteur de 10 minutes pour les pâtes"))
        XCTAssertEqual(start.data["action"], "timer_start")
        XCTAssertEqual(start.data["seconds"], "600")
        XCTAssertEqual(start.data["name"], "pâtes")
        XCTAssertEqual(start.spokenResponse, "Minuteur « pâtes » lancé : 10 minutes.")
        XCTAssertEqual(timers.active(at: now).count, 1)

        let status = try XCTUnwrap(answer("Il reste combien pour les pâtes ?"))
        XCTAssertEqual(status.spokenResponse, "Il reste 10 minutes pour « pâtes ».")

        let cancel = try XCTUnwrap(answer("Annule le minuteur des pâtes"))
        XCTAssertEqual(cancel.data["action"], "timer_cancel")
        XCTAssertEqual(cancel.spokenResponse, "Minuteur « pâtes » annulé.")
        XCTAssertTrue(timers.active(at: now).isEmpty)
        XCTAssertEqual(answer("Combien de temps reste-t-il sur le minuteur ?")?.spokenResponse, "Aucun minuteur en cours.")
    }

    func testShortTimerCommandsAndWakeUp() throws {
        XCTAssertEqual(try XCTUnwrap(answer("Minuteur pâtes 8 minutes")).data["name"], "pâtes")
        let wake = try XCTUnwrap(answer("Réveille-moi dans 20 minutes"))
        XCTAssertEqual(wake.data["action"], "timer_start")
        XCTAssertEqual(wake.data["seconds"], "1200")
        XCTAssertEqual(wake.spokenResponse, "Minuteur lancé : 20 minutes.")
        XCTAssertEqual(timers.active(at: now).count, 2)
        XCTAssertEqual(answer("Annule le minuteur")?.spokenResponse, "2 minuteurs annulés.")
    }

    func testTimersSurviveARelaunch() {
        let defaults = UserDefaults(suiteName: "JarvisLifeAssistantTests.persist.\(UUID().uuidString)")!
        JarvisTimerStore(defaults: defaults).add(name: "four", duration: 1_800, now: now)
        let reopened = JarvisTimerStore(defaults: defaults)
        XCTAssertEqual(reopened.active(at: now).map(\.name), ["four"])
        XCTAssertTrue(reopened.active(at: now.addingTimeInterval(1_801)).isEmpty, "An ended timer is no longer active.")
    }

    // MARK: Reminders

    func testReminderWithDayAndTime() throws {
        let response = try XCTUnwrap(answer("Rappelle-moi d'appeler maman demain à 18 h"))
        XCTAssertEqual(response.data["action"], "reminder_create")
        XCTAssertEqual(response.data["reminder_title"], "Appeler maman")
        XCTAssertEqual(response.data["reminder_spoken_due"], "demain à 18 h")
        let due = Date(timeIntervalSince1970: try XCTUnwrap(TimeInterval(try XCTUnwrap(response.data["reminder_due"]))))
        let calendar = Calendar.current
        XCTAssertEqual(calendar.component(.day, from: due), 26)
        XCTAssertEqual(calendar.component(.hour, from: due), 18)
    }

    func testReminderInSomeMinutes() throws {
        let response = try XCTUnwrap(answer("Rappelle-moi de sortir le linge dans 20 minutes"))
        XCTAssertEqual(response.data["reminder_title"], "Sortir le linge")
        XCTAssertEqual(response.data["reminder_spoken_due"], "dans 20 minutes")
        XCTAssertEqual(TimeInterval(try XCTUnwrap(response.data["reminder_due"])), now.addingTimeInterval(1_200).timeIntervalSince1970)
    }

    func testReminderWithoutContentAsksWhat() {
        XCTAssertEqual(answer("Rappelle-moi")?.status, .refused)
    }

    // MARK: Agenda and briefing

    func testAgendaQuestionsReadTheRightDay() throws {
        let tomorrow = try XCTUnwrap(answer("Qu'est-ce que j'ai demain ?"))
        XCTAssertEqual(tomorrow.data["action"], "agenda_read")
        XCTAssertEqual(tomorrow.data["day_offset"], "1")
        XCTAssertEqual(answer("Mon agenda de vendredi")?.data["day_offset"], "2")
        XCTAssertEqual(answer("Est-ce que je suis libre aujourd'hui ?")?.data["day_offset"], "0")
    }

    func testOtherQuestionsAreNotMistakenForTheAgenda() {
        XCTAssertNotEqual(answer("Qu'est-ce que je viens de déplacer ?")?.data["action"], "agenda_read")
        XCTAssertNotEqual(answer("Qu'est-ce que j'ai déplacé ?")?.data["action"], "agenda_read")
        XCTAssertNotEqual(answer("Combien de notes ai-je prises ces sept derniers jours ?")?.data["action"], "agenda_read")
    }

    func testBriefingStartsWithTheDateAndTime() throws {
        let response = try XCTUnwrap(answer("Fais-moi le point"))
        XCTAssertEqual(response.data["action"], "briefing")
        XCTAssertTrue(response.spokenResponse.contains("mercredi 25 novembre"))
        XCTAssertTrue(response.spokenResponse.contains("10 h 00"))
    }

    func testAgendaSummaryIsSpokenInFrench() {
        let calendar = Calendar.current
        let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: now)!
        let afternoon = calendar.date(bySettingHour: 14, minute: 30, second: 0, of: now)!
        let text = JarvisAgendaSummary.spoken([
            .init(start: nine, title: "Réunion", isAllDay: false),
            .init(start: afternoon, title: "Dentiste", isAllDay: false)
        ], dayLabel: "demain")
        XCTAssertEqual(text, "Demain, vous avez 2 rendez-vous : 9 h, Réunion ; 14 h 30, Dentiste.")
        XCTAssertEqual(JarvisAgendaSummary.spoken([], dayLabel: "demain"), "Rien n'est prévu demain dans votre calendrier.")
    }

    func testLifeActionsAreRecognisedAndStrippedForRendering() {
        let response = JarvisResponse.ok("Je regarde votre agenda.", data: ["action": "agenda_read"])
        XCTAssertTrue(JarvisLifeActionPerformer.handles(response))
        XCTAssertNil(JarvisLifeActionPerformer.withoutAction(response).data["action"])
        XCTAssertFalse(JarvisLifeActionPerformer.handles(.ok("Bonjour")))
    }
}
