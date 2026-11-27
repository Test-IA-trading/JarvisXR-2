import XCTest
@testable import JarvisXR

/// The connected mode's logic, without any network: what is asked, the weather sentence
/// from Open-Meteo's JSON, Wikipédia's subject and extract, franceinfo's titles. The
/// answers below are shortened copies of real ones (25/11/2026).
final class JarvisInternetAnswersTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "JarvisInternetAnswersTests.\(UUID().uuidString)")
        JarvisInternetSettings.defaults = defaults
    }

    override func tearDown() {
        JarvisInternetSettings.defaults = .standard
        super.tearDown()
    }

    private func parse(_ phrase: String) -> JarvisInternetRequest? {
        let normalized = JarvisFrenchCommandRouter.normalize(phrase)
        return JarvisInternetRequest.parse(original: phrase, normalized: normalized, request: JarvisFrenchCommandRouter.stripWakeWord(normalized))
    }

    private func json(_ text: String) -> [String: Any] {
        ((try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any]) ?? [:]
    }

    func testWeatherRequestsAndTheirPlace() {
        XCTAssertEqual(parse("Quel temps fait-il ?"), .weather(city: nil, dayOffset: 0))
        XCTAssertEqual(parse("Jarvis, quel temps fait-il à Lyon demain ?"), .weather(city: "lyon", dayOffset: 1))
        XCTAssertEqual(parse("Quel temps fera-t-il après-demain à Saint-Étienne ?"), .weather(city: "saint etienne", dayOffset: 2))
        XCTAssertEqual(parse("Quel temps fait-il à Rio de Janeiro ?"), .weather(city: "rio de janeiro", dayOffset: 0))
        XCTAssertEqual(parse("Météo pour demain à Marseille"), .weather(city: "marseille", dayOffset: 1))
        XCTAssertEqual(parse("La météo de demain"), .weather(city: nil, dayOffset: 1))
        XCTAssertEqual(parse("Quel temps fait-il en ce moment à Paris ?"), .weather(city: "paris", dayOffset: 0))
        XCTAssertEqual(parse("Dois-je prendre un parapluie pour aller à Lyon ?"), .weather(city: "lyon", dayOffset: 0))
        XCTAssertEqual(parse("Quel temps fait-il à la maison ?"), .weather(city: nil, dayOffset: 0))
        XCTAssertNil(parse("Quelle température pour cuire un poulet ?"))
        XCTAssertNil(parse("Combien de temps reste-t-il ?"))
    }

    func testNewsPositionAndCity() {
        XCTAssertEqual(parse("Quelles sont les actualités ?"), .news)
        XCTAssertEqual(parse("Donne-moi les titres du jour"), .news)
        XCTAssertEqual(parse("Où suis-je ?"), .whereAmI)
        XCTAssertEqual(parse("Ma ville est Lyon"), .setCity("Lyon"))
        XCTAssertEqual(parse("J'habite à Saint-Étienne"), .setCity("Saint-Étienne"))
        XCTAssertNil(parse("J'habite à côté de la gare"))
        XCTAssertNil(parse("Fais-moi le point"))
        XCTAssertNil(parse("Qu'est-ce que j'ai demain ?"))
    }

    func testTheWeatherIsSaidInFrench() {
        let forecast = json(#"{"current": {"temperature_2m": 5.2, "apparent_temperature": 2.6, "weather_code": 80, "wind_speed_10m": 7.6}, "daily": {"weather_code": [80, 80, 3], "temperature_2m_max": [5.7, 6.0, 2.7], "temperature_2m_min": [4.0, 1.1, -0.7], "precipitation_probability_max": [100, 15, 0]}}"#)
        XCTAssertEqual(JarvisWeatherReport.sentence(place: "Paris", forecast: forecast, dayOffset: 0), "À Paris, il fait 5 degrés, averses. Aujourd'hui, entre 4 et 6 degrés, 100 % de risque de pluie.")
        XCTAssertEqual(JarvisWeatherReport.sentence(place: "Paris", forecast: forecast, dayOffset: 1), "Demain à Paris : averses, entre 1 et 6 degrés, 15 % de risque de pluie.")
        XCTAssertEqual(JarvisWeatherReport.sentence(place: "Paris", forecast: forecast, dayOffset: 2), "Après-demain à Paris : ciel couvert, entre moins 1 et 3 degrés, sans pluie prévue.")
        XCTAssertEqual(JarvisWeatherReport.sentence(place: nil, forecast: forecast, dayOffset: 0)?.hasPrefix("Ici, il fait 5 degrés"), true)
        XCTAssertNil(JarvisWeatherReport.sentence(place: "Paris", forecast: [:], dayOffset: 0))

        let cold = json(#"{"current": {"temperature_2m": -2.4, "apparent_temperature": -7.9, "weather_code": 71, "wind_speed_10m": 45}, "daily": {"weather_code": [71], "temperature_2m_max": [0.8], "temperature_2m_min": [-4.2], "precipitation_probability_max": [null]}}"#)
        XCTAssertEqual(JarvisWeatherReport.sentence(place: "Chamonix", forecast: cold, dayOffset: 0), "À Chamonix, il fait moins 2 degrés, neige faible, ressenti moins 8 degrés, vent fort à 45 kilomètres-heure. Aujourd'hui, entre moins 4 et 1 degré.")

        XCTAssertEqual(JarvisWeatherReport.degrees(-0.4), "0 degré")
        XCTAssertEqual(JarvisWeatherReport.degrees(-3.5), "moins 4 degrés")
        XCTAssertEqual(JarvisWeatherReport.rounded(48.8566), "48.86")
        let place = JarvisWeatherReport.place(fromGeocoding: json(#"{"results": [{"name": "Saint-Étienne", "latitude": 45.43389, "longitude": 4.39}]}"#))
        XCTAssertEqual(place?.name, "Saint-Étienne")
        XCTAssertNil(JarvisWeatherReport.place(fromGeocoding: json(#"{"generationtime_ms": 0.5}"#)))
    }

    func testWikipediaSubjects() {
        XCTAssertEqual(JarvisWikipediaAnswer.subject(in: "Qui est Marie Curie ?"), "Marie Curie")
        XCTAssertEqual(JarvisWikipediaAnswer.subject(in: "Jarvis, qui était Napoléon ?"), "Napoléon")
        XCTAssertEqual(JarvisWikipediaAnswer.subject(in: "C'est quoi un trou noir ?"), "un trou noir")
        XCTAssertEqual(JarvisWikipediaAnswer.subject(in: "Qu'est-ce que la photosynthèse ?"), "la photosynthèse")
        XCTAssertEqual(JarvisWikipediaAnswer.subject(in: "Parle-moi d'Einstein"), "Einstein")
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "Qui est-ce ?"))
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "C'est quoi ton prénom ?"))
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "Qu'est-ce que j'ai demain ?"))
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "Qui est le plus fort ?"))
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "C'est quoi 2 plus 2 ?"))
        XCTAssertNil(JarvisWikipediaAnswer.subject(in: "Pourquoi le ciel est-il bleu ?"))
    }

    func testWikipediaExtractsAreSaidCleanly() {
        let answer = json(#"{"batchcomplete": true, "query": {"pages": [{"pageid": 1, "ns": 0, "title": "AC/DC", "index": 1, "extract": "AC/DC [ˌæɪsiːˈdiːsiː] est un groupe australo-britannique de hard rock (fondé en 1973). Son premier concert a eu lieu le 31 décembre 1973."}]}}"#)
        let article = JarvisWikipediaAnswer.article(from: answer)
        XCTAssertEqual(article?.title, "AC/DC")
        XCTAssertEqual(article.map { JarvisWikipediaAnswer.spoken($0.extract) }, "AC/DC est un groupe australo-britannique de hard rock. Son premier concert a eu lieu le 31 décembre 1973.")
        let ambiguous = json(#"{"query": {"pages": [{"title": "Mercure", "pageprops": {"disambiguation": ""}, "extract": "Mercure peut désigner :"}]}}"#)
        XCTAssertNil(JarvisWikipediaAnswer.article(from: ambiguous), "A disambiguation page is no answer")
        XCTAssertNil(JarvisWikipediaAnswer.article(from: json(#"{"batchcomplete": true}"#)))
        XCTAssertEqual(JarvisWikipediaAnswer.firstSentence(of: "Né en 384 av. J.-C. à Stagire. Il fut le maître d'Alexandre."), "Né en 384 av. J.-C. à Stagire.")
    }

    func testNewsTitlesAreRead() {
        let feed = """
        <?xml version="1.0"?>
        <rss version="2.0"><channel><title>franceinfo - Les Titres</title>
        <item><title>Pr&#xE9;sidentielle 2027 : un d&#xE9;bat</title><description>Un r&#xE9;sum&#xE9;.</description></item>
        <item><title><![CDATA[Les Etats-Unis annoncent de nouveaux droits de douane]]></title></item>
        <item><title>Inondations dans le Var</title></item>
        <item><title>Quatrième titre</title></item>
        </channel></rss>
        """
        let titles = JarvisNewsFeedParser.titles(from: Data(feed.utf8))
        XCTAssertEqual(titles, ["Présidentielle 2027 : un débat", "Les Etats-Unis annoncent de nouveaux droits de douane", "Inondations dans le Var", "Quatrième titre"])
        let answer = JarvisNewsFeedParser.answer(titles)
        XCTAssertEqual(answer.spoken, "Voici les titres de franceinfo : Présidentielle 2027 : un débat ; Les Etats-Unis annoncent de nouveaux droits de douane ; Inondations dans le Var.")
        XCTAssertTrue(answer.display.contains("• Quatrième titre"))
    }

    func testWhereAmIIsSaid() {
        let answer = JarvisWhereAmI.answer(number: "12", street: "Rue de la République", postalCode: "69002", town: "Lyon", country: "France")
        XCTAssertEqual(answer?.spoken, "Vous êtes à Lyon, 12 Rue de la République.")
        XCTAssertEqual(answer?.display, "12 Rue de la République, 69002 Lyon, France")
        XCTAssertEqual(JarvisWhereAmI.answer(number: nil, street: nil, postalCode: nil, town: "Lyon", country: "France")?.spoken, "Vous êtes à Lyon.")
        XCTAssertNil(JarvisWhereAmI.answer(number: nil, street: " ", postalCode: nil, town: nil, country: nil))
    }

    private func route(_ phrase: String) -> JarvisResponse? {
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: defaults), scene: JarvisSpatialSceneMemory(), context: JarvisConversationContext(), profile: JarvisUserProfile(defaults: defaults))
        guard case .answer(let response) = router.route(phrase) else { return nil }
        return response
    }

    func testTheRouterUsesTheInternetOnlyInConnectedMode() {
        JarvisInternetSettings.isEnabled = true
        let weather = route("Quel temps fait-il à Lyon demain ?")
        XCTAssertEqual(weather?.data["action"], "web_weather")
        XCTAssertEqual(weather?.data["city"], "lyon")
        XCTAssertEqual(weather?.data["day_offset"], "1")
        XCTAssertTrue(weather.map(JarvisLifeActionPerformer.handles) == true)
        XCTAssertEqual(route("Les titres du jour")?.data["action"], "web_news")
        XCTAssertEqual(route("Où suis-je ?")?.data["action"], "where_am_i")
        XCTAssertEqual(route("Ma ville est Lyon")?.spokenResponse, "C'est noté : je donnerai la météo de Lyon.")
        XCTAssertEqual(JarvisInternetSettings.city, "Lyon")
        XCTAssertNotEqual(route("Qu'est-ce que j'ai demain ?")?.data["action"], "web_weather")

        JarvisInternetSettings.isEnabled = false
        guard !JarvisPCLink.shared.isConfigured else { return }
        let off = route("Quel temps fait-il ?")
        XCTAssertEqual(off?.status, .unavailable)
        XCTAssertTrue(off?.spokenResponse.contains("Réglages › Internet") == true)
        XCTAssertNil(off?.data["action"], "Nothing is asked of the Internet while the mode is off")
    }
}
