import XCTest
@testable import JarvisXR

/// Conversions and date questions, answered exactly without a network. The expected
/// strings were replayed in a Python replica first (no Swift compiler on the Windows PC).
final class JarvisEverydayAnswersTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    /// Wednesday 25 November 2026, noon in Paris.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 12))!
    }

    private func assertConversion(_ phrase: String, spoken: String, display: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let answer = JarvisUnitConverter.answer(to: phrase) else {
            return XCTFail("No conversion found in « \(phrase) »", file: file, line: line)
        }
        XCTAssertEqual(answer.spoken, spoken, file: file, line: line)
        XCTAssertEqual(answer.display, display, file: file, line: line)
    }

    private func assertDate(_ phrase: String, spoken: String, display: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let answer = JarvisDateAnswers.answer(to: phrase, now: now, calendar: calendar) else {
            return XCTFail("No date question found in « \(phrase) »", file: file, line: line)
        }
        XCTAssertEqual(answer.spoken, spoken, file: file, line: line)
        XCTAssertEqual(answer.display, display, file: file, line: line)
    }

    // MARK: Conversions

    func testLengthsMassesSpeedsAndDurations() {
        assertConversion("Convertis 10 miles en kilomètres", spoken: "10 miles font 16,09 kilomètres.", display: "10 mi = 16,0934 km")
        assertConversion("Combien de mètres dans un mile ?", spoken: "1 mile fait 1609 mètres.", display: "1 mi = 1609,344 m")
        assertConversion("5 kilos en livres", spoken: "5 kilogrammes font 11,02 livres.", display: "5 kg = 11,0231 lb")
        assertConversion("90 km/h en miles par heure", spoken: "90 kilomètres par heure font 55,92 miles par heure.", display: "90 km/h = 55,9234 mph")
        assertConversion("Combien de secondes dans 3 heures ?", spoken: "3 heures font 10800 secondes.", display: "3 heures = 10800 secondes")
        assertConversion("2 ans en jours", spoken: "2 ans font 730,5 jours.", display: "2 ans = 730,5 jours")
    }

    func testTemperatures() {
        assertConversion("100 degrés Fahrenheit en Celsius", spoken: "100 degrés Fahrenheit font 37,78 degrés Celsius.", display: "100 °F = 37,7778 °C")
        assertConversion("Combien font 30 degrés en Fahrenheit ?", spoken: "30 degrés Celsius font 86 degrés Fahrenheit.", display: "30 °C = 86 °F")
        assertConversion("Convertis moins 40 degrés en Fahrenheit", spoken: "−40 degrés Celsius font −40 degrés Fahrenheit.", display: "−40 °C = −40 °F")
    }

    func testSentencesThatAreNotConversions() {
        for phrase in [
            "Quel jour serons-nous dans 100 jours ?",
            "Mets un minuteur de 10 minutes",
            "Combien de jours avant Noël ?",
            "J'ai couru 10 kilomètres ce matin",
            "Combien font 128 fois 46 ?",
        ] {
            XCTAssertNil(JarvisUnitConverter.answer(to: phrase), phrase)
        }
    }

    // MARK: Dates

    func testDaysFromNowAndAgo() {
        assertDate("Quel jour serons-nous dans 100 jours ?", spoken: "Dans 100 jours, nous serons le vendredi 5 mars 2027.", display: "Dans 100 jours : vendredi 5 mars 2027")
        assertDate("Quel jour étions-nous il y a 30 jours ?", spoken: "Il y a 30 jours, nous étions le lundi 26 octobre 2026.", display: "Il y a 30 jours : lundi 26 octobre 2026")
        assertDate("Dans 2 semaines, on sera quel jour ?", spoken: "Dans 2 semaines, nous serons le mercredi 9 décembre 2026.", display: "Dans 2 semaines : mercredi 9 décembre 2026")
    }

    func testDaysUntilANamedOrWrittenDate() {
        assertDate("Combien de jours avant Noël ?", spoken: "Noël est dans 30 jours, le vendredi 25 décembre 2026.", display: "Noël : dans 30 jours, vendredi 25 décembre 2026")
        assertDate("Dans combien de jours est le 14 juillet ?", spoken: "Le 14 juillet est dans 231 jours, le mercredi 14 juillet 2027.", display: "Le 14 juillet : dans 231 jours, mercredi 14 juillet 2027")
        assertDate("Combien de jours jusqu'au jour de l'an ?", spoken: "Le jour de l'an est dans 37 jours, le vendredi 1er janvier 2027.", display: "Le jour de l'an : dans 37 jours, vendredi 1er janvier 2027")
    }

    func testTheWeekdayOfADate() {
        assertDate("Quel jour tombe le 1er janvier 2027 ?", spoken: "Le 1er janvier 2027 tombera un vendredi : le vendredi 1er janvier 2027.", display: "Le 1er janvier 2027 : vendredi 1er janvier 2027")
        assertDate("Le 25 novembre, c'est quel jour ?", spoken: "Le 25 novembre tombe un mercredi : le mercredi 25 novembre 2026.", display: "Le 25 novembre : mercredi 25 novembre 2026")
    }

    func testOtherSentencesAreLeftAlone() {
        for phrase in ["Quel jour sommes-nous ?", "Quelle heure est-il ?", "Rappelle-moi le 14 juillet d'acheter du pain", "Le train part à 9 h et le bus à 11 h"] {
            XCTAssertNil(JarvisDateAnswers.answer(to: phrase, now: now, calendar: calendar), phrase)
        }
    }

    func testTheRouterNoLongerAnswersTodayForAFutureDay() {
        let router = JarvisFrenchCommandRouter(
            memory: JarvisMemoryStore(defaults: UserDefaults(suiteName: "JarvisEverydayAnswersTests.\(UUID().uuidString)")!),
            scene: JarvisSpatialSceneMemory(),
            context: JarvisConversationContext()
        )
        guard case .answer(let response) = router.route("Quel jour serons-nous dans 100 jours ?", now: now) else {
            return XCTFail("A date question is answered natively")
        }
        XCTAssertTrue(response.spokenResponse.hasPrefix("Dans 100 jours, nous serons le"), response.spokenResponse)
        guard case .answer(let conversion) = router.route("Convertis 10 miles en kilomètres", now: now) else {
            return XCTFail("A conversion is answered natively")
        }
        XCTAssertEqual(conversion.displayResponse, "10 mi = 16,0934 km")
    }
}
