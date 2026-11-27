import XCTest
@testable import JarvisXR

/// The iPhone's own data, without touching it: what is asked (calls, messages, steps,
/// photos), which contact is meant, and the French answers.
final class JarvisDeviceRequestsTests: XCTestCase {
    private func parse(_ phrase: String) -> JarvisDeviceRequest? {
        let normalized = JarvisFrenchCommandRouter.normalize(phrase)
        return JarvisDeviceRequest.parse(original: phrase, normalized: normalized, request: JarvisFrenchCommandRouter.stripWakeWord(normalized))
    }

    func testCallsMessagesAndNumbers() {
        XCTAssertEqual(parse("Appelle Paul"), .call("Paul"))
        XCTAssertEqual(parse("Jarvis, appelle maman"), .call("maman"))
        XCTAssertEqual(parse("Appelle le 06 12 34 56 78"), .call("le 06 12 34 56 78"))
        XCTAssertEqual(parse("Passe un coup de fil à Marie Dupont"), .call("Marie Dupont"))
        XCTAssertNil(parse("Appelle-moi"))
        XCTAssertNil(parse("Rappelle-moi d'appeler maman demain à 18 h"))
        XCTAssertEqual(parse("Écris à Paul que j'arrive dans 10 minutes"), .message(to: "Paul", body: "j'arrive dans 10 minutes"))
        XCTAssertEqual(parse("Envoie un message à Marie Dupont pour lui dire que le dîner est prêt"), .message(to: "Marie Dupont", body: "le dîner est prêt"))
        XCTAssertEqual(parse("Envoie un SMS à papa"), .message(to: "papa", body: nil))
        XCTAssertEqual(parse("Écris à Paul : on se voit demain"), .message(to: "Paul", body: "on se voit demain"))
        XCTAssertEqual(parse("Dis à Paul que j'arrive"), .message(to: "Paul", body: "j'arrive"))
        XCTAssertNil(parse("Dis à demain"))
        XCTAssertEqual(parse("Quel est le numéro de Paul ?"), .phoneNumber(of: "Paul"))
    }

    func testStepsAndPhotos() {
        XCTAssertEqual(parse("Combien de pas aujourd'hui ?"), .steps(.today))
        XCTAssertEqual(parse("Combien de pas ai-je faits hier ?"), .steps(.yesterday))
        XCTAssertEqual(parse("Quelle distance ai-je parcourue cette semaine ?"), .steps(.week))
        XCTAssertEqual(parse("Combien de photos ai-je prises hier ?"), .photoCount(.yesterday))
        XCTAssertEqual(parse("Montre-moi ma dernière photo"), .showPhotos(.today, latestOnly: true))
        XCTAssertEqual(parse("Montre-moi mes photos d'hier"), .showPhotos(.yesterday, latestOnly: false))
        XCTAssertNil(parse("Quelle distance entre Paris et Lyon ?"))
        XCTAssertNil(parse("Explique-moi la photosynthèse"))
    }

    private let people = [
        JarvisContactCandidate(identifier: "1", displayName: "Paul Dupont", givenName: "Paul", familyName: "Dupont", phones: [
            JarvisPhone(label: "_$!<Home>!$_", number: "01 23 45 67 89"), JarvisPhone(label: "_$!<Mobile>!$_", number: "06 12 34 56 78"),
        ]),
        JarvisContactCandidate(identifier: "2", displayName: "Maman", givenName: "Maman", phones: [JarvisPhone(label: "iPhone", number: "+33 6 11 22 33 44")]),
        JarvisContactCandidate(identifier: "3", displayName: "Marie Martin", givenName: "Marie", familyName: "Martin", phones: [JarvisPhone(label: "_$!<Mobile>!$_", number: "06 00 00 00 01")]),
        JarvisContactCandidate(identifier: "4", displayName: "Marie Dupont", givenName: "Marie", familyName: "Dupont", nickname: "Mimi", phones: [JarvisPhone(label: "_$!<Mobile>!$_", number: "06 00 00 00 02")]),
        JarvisContactCandidate(identifier: "5", displayName: "Garage Renault", organization: "Garage Renault", phones: [JarvisPhone(label: "_$!<Work>!$_", number: "04 00 00 00 03")]),
    ]

    func testTheRightContactIsFound() {
        XCTAssertEqual(JarvisContactMatcher.match("Paul", in: people), .one(people[0]))
        XCTAssertEqual(JarvisContactMatcher.match("ma mère", in: people), .one(people[1]))
        XCTAssertEqual(JarvisContactMatcher.match("maman", in: people), .one(people[1]))
        XCTAssertEqual(JarvisContactMatcher.match("Marie", in: people), .several([people[2], people[3]]))
        XCTAssertEqual(JarvisContactMatcher.match("Marie Dupont", in: people), .one(people[3]))
        XCTAssertEqual(JarvisContactMatcher.match("Mimi", in: people), .one(people[3]))
        XCTAssertEqual(JarvisContactMatcher.match("Renault", in: people), .one(people[4]))
        XCTAssertEqual(JarvisContactMatcher.match("Bruce Wayne", in: people), .nobody)
        XCTAssertEqual(JarvisContactMatcher.preferredPhone(people[0].phones)?.number, "06 12 34 56 78", "The mobile number first")
        XCTAssertEqual(JarvisContactMatcher.preferredPhone(people[4].phones)?.number, "04 00 00 00 03")
        XCTAssertEqual(JarvisContactMatcher.dialable("+33 6 11 22 33 44"), "+33611223344")
        XCTAssertEqual(JarvisContactMatcher.dialable("06 12 34 56 78"), "0612345678")
        XCTAssertEqual(JarvisContactMatcher.choices([people[2], people[3]]), "Marie Martin ou Marie Dupont")
    }

    func testStepsAndPhotosAreSaidInFrench() {
        XCTAssertEqual(JarvisDeviceSentences.steps(8432, meters: 6123.4, floors: 4, period: .today), "Aujourd'hui, vous avez fait 8432 pas, soit 6,1 kilomètres, et monté 4 étages.")
        XCTAssertEqual(JarvisDeviceSentences.steps(512, meters: 380.2, floors: 1, period: .yesterday), "Hier, vous avez fait 512 pas, soit 380 mètres, et monté 1 étage.")
        XCTAssertEqual(JarvisDeviceSentences.steps(52310, meters: 39876, floors: nil, period: .week), "Ces sept derniers jours, vous avez fait 52310 pas, soit 7473 par jour en moyenne, pour 39,9 kilomètres.")
        XCTAssertEqual(JarvisDeviceSentences.steps(0, meters: nil, floors: nil, period: .today), "Aujourd'hui, je ne compte encore aucun pas.")
        XCTAssertEqual(JarvisDeviceSentences.distance(1500), "1,5 kilomètre")
        XCTAssertEqual(JarvisDeviceSentences.distance(2000), "2 kilomètres")
        XCTAssertEqual(JarvisDeviceSentences.photoCount(photos: 12, videos: 2, period: .yesterday), "Hier, vous avez pris 12 photos et 2 vidéos.")
        XCTAssertEqual(JarvisDeviceSentences.photoCount(photos: 1, videos: 0, period: .today), "Aujourd'hui, vous avez pris 1 photo.")
        XCTAssertEqual(JarvisDeviceSentences.photoCount(photos: 0, videos: 0, period: .week), "Ces sept derniers jours, vous n'avez pris aucune photo.")
        XCTAssertEqual(JarvisDeviceSentences.photoCount(photos: 0, videos: 3, period: .today), "Aujourd'hui, vous n'avez pris aucune photo, mais 3 vidéos.")
    }

    func testTheLatestPhotoDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Paris"))
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)))
        }
        let now = try date(2026, 11, 25, 15, 0)
        XCTAssertEqual(JarvisDeviceSentences.latestPhoto(taken: try date(2026, 11, 25, 14, 5), now: now, calendar: calendar), "Votre dernière photo date d'aujourd'hui à 14 h 05.")
        XCTAssertEqual(JarvisDeviceSentences.latestPhoto(taken: try date(2026, 11, 24, 9, 30), now: now, calendar: calendar), "Votre dernière photo date d'hier à 9 h 30.")
        XCTAssertEqual(JarvisDeviceSentences.latestPhoto(taken: try date(2026, 11, 20, 18, 0), now: now, calendar: calendar), "Votre dernière photo date du vendredi 20 novembre à 18 h 00.")
        XCTAssertEqual(JarvisDeviceSentences.latestPhoto(taken: try date(2025, 7, 14, 12, 0), now: now, calendar: calendar), "Votre dernière photo date du lundi 14 juillet 2025 à 12 h 00.")

        let yesterday = JarvisDevicePeriod.yesterday.interval(now: now, calendar: calendar)
        XCTAssertEqual(yesterday.start, try date(2026, 11, 24, 0, 0))
        XCTAssertEqual(yesterday.end, try date(2026, 11, 25, 0, 0))
        XCTAssertEqual(JarvisDevicePeriod.week.interval(now: now, calendar: calendar).start, try date(2026, 11, 19, 0, 0))
    }

    private func route(_ phrase: String) -> JarvisResponse? {
        let defaults = UserDefaults(suiteName: "JarvisDeviceRequestsTests.\(UUID().uuidString)")!
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: defaults), scene: JarvisSpatialSceneMemory(), context: JarvisConversationContext(), profile: JarvisUserProfile(defaults: defaults))
        guard case .answer(let response) = router.route(phrase) else { return nil }
        return response
    }

    func testTheRouterHandsTheseToThePerformer() {
        let call = route("Appelle Paul")
        XCTAssertEqual(call?.data["action"], "phone_call")
        XCTAssertEqual(call?.data["name"], "Paul")
        XCTAssertTrue(call.map(JarvisLifeActionPerformer.handles) == true)
        let message = route("Écris à Paul que j'arrive")
        XCTAssertEqual(message?.data["action"], "phone_message")
        XCTAssertEqual(message?.data["body"], "j'arrive")
        XCTAssertEqual(route("Combien de pas aujourd'hui ?")?.data["period"], "today")
        XCTAssertEqual(route("Montre-moi ma dernière photo")?.data["latest"], "1")
        XCTAssertNotEqual(route("Je m'appelle Tony")?.data["action"], "phone_call", "The first name is not a call")
    }
}
