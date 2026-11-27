import Foundation

// The connected mode's logic, without any network: what a sentence asks of the Internet,
// and the French answers built from what Open-Meteo, Wikipédia and franceinfo return.
// The only network path is JarvisInternetClient.swift.

// MARK: - Settings

/// Connected mode (Réglages › Internet), off until the user turns it on: the weather
/// (Open-Meteo), the news (franceinfo) and « Qui est… ? » (Wikipédia), free services that
/// need no account. While it is off, none of them is asked anything.
enum JarvisInternetSettings {
    /// Swapped by the tests.
    static var defaults: UserDefaults = .standard
    static let enabledKey = "JarvisXR.internetEnabled"
    static let locationKey = "JarvisXR.internetUsesLocation"
    static let cityKey = "JarvisXR.internetCity"

    static var isEnabled: Bool {
        get { defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// The weather of where the iPhone is (iOS asks once) rather than of the saved city.
    static var usesLocation: Bool {
        get { defaults.object(forKey: locationKey) == nil ? true : defaults.bool(forKey: locationKey) }
        set { defaults.set(newValue, forKey: locationKey) }
    }

    /// « Ma ville est Lyon »: the weather's city when the position is not used or not known.
    static var city: String? {
        get {
            let value = defaults.string(forKey: cityKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? nil : value
        }
        set {
            let value = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if value.isEmpty {
                defaults.removeObject(forKey: cityKey)
            } else {
                defaults.set(value, forKey: cityKey)
            }
        }
    }
}

// MARK: - Failures

enum JarvisInternetFailure: Error, Equatable {
    case disabled
    case unreachable
    case unreadable
    case noPlace
    case noPosition
    case unknownCity(String)
    case notFound

    var message: String {
        switch self {
        case .disabled:
            return "Le mode connecté est désactivé : activez-le dans Réglages › Internet pour la météo, les actualités et Wikipédia."
        case .unreachable:
            return "Je n'arrive pas à joindre le service en ligne : vérifiez la connexion Internet de l'iPhone."
        case .unreadable:
            return "Le service en ligne a répondu quelque chose d'illisible. Réessayez dans un moment."
        case .noPlace:
            return "Pour quelle ville ? Dites par exemple « Ma ville est Lyon », ou autorisez la position de JARVIS dans les Réglages iOS."
        case .noPosition:
            return "Je n'ai pas accès à la position : autorisez-la pour JARVIS dans Réglages iOS › Confidentialité et sécurité › Service de localisation."
        case .unknownCity(let city):
            return "Je ne trouve pas la ville « \(city) »."
        case .notFound:
            return "Je ne trouve rien à ce sujet."
        }
    }
}

// MARK: - What is asked

/// What a sentence asks of the Internet, read from the French router's normalized words
/// (no accents, no capitals, hyphens as spaces).
enum JarvisInternetRequest: Equatable {
    case weather(city: String?, dayOffset: Int)
    case news
    case whereAmI
    case setCity(String)

    static let weatherPhrases = [
        "meteo", "quel temps", "il fait beau", "fait il beau", "fera t il beau", "faire beau", "pleuvoir", "pleut il",
        "est ce qu'il pleut", "risque de pluie", "parapluie", "quelle temperature fait", "quelle temperature il fait",
        "quelle temperature fera", "quelle temperature dehors", "quelle temperature exterieure", "quelle temperature va t il faire",
        "fait il froid", "fait il chaud", "est ce qu'il fait froid", "est ce qu'il fait chaud", "neiger", "neige t il",
    ]
    static let newsPhrases = [
        "actualite", "actualites", "l'actualite", "l'actu", "les actus", "les infos", "infos du jour", "les nouvelles",
        "dernieres nouvelles", "les titres", "titres du jour", "quoi de neuf dans le monde", "a la une", "flash info",
    ]
    static let wherePhrases = [
        "ou suis je", "ou est ce que je suis", "dis moi ou je suis", "ou sommes nous", "on est ou", "ou est ce qu'on est",
        "quelle est ma position", "ma position actuelle", "donne moi ma position", "dans quelle ville je suis",
        "dans quelle ville suis je", "dans quelle ville on est", "dans quelle ville sommes nous", "quelle ville suis je",
        "dans quelle rue je suis", "dans quelle rue suis je", "quelle est mon adresse",
    ]
    static let cityPrefixes = ["ma ville est", "ma ville c'est", "j'habite a", "j'habite au", "j'habite aux", "j'habite en"]

    /// Words before a city: « à Lyon », « au Japon », « en Bretagne », « de Lyon », « pour Marseille ».
    static let cityPrepositions: Set<String> = ["a", "au", "aux", "en", "pour", "de", "du", "sur"]
    /// When, not where: « demain », « ce soir », « en ce moment »…
    static let timePhrases: [[String]] = [
        "apres demain", "demain matin", "demain soir", "demain", "aujourd'hui", "ce soir", "cette nuit", "ce matin",
        "cet apres midi", "maintenant", "en ce moment", "ce moment", "ce week end", "le week end", "week end",
        "cette semaine", "la semaine", "semaine", "toute la journee", "la journee", "jour", "ce midi", "midi",
        "la nuit", "matin", "soir", "nuit", "tout a l'heure",
    ].map { $0.split(separator: " ").map(String.init) }
    static let notCities: Set<String> = ["la maison", "ici", "chez moi", "dehors", "l'exterieur", "exterieur", "la", "le", "les", "la bas"]
    /// « … un parapluie pour aller à Lyon »: the place comes after the verb.
    static let verbsBeforePlace: Set<String> = ["aller", "sortir", "partir", "faire", "courir", "marcher", "rentrer", "venir", "voyager", "rouler"]

    static func parse(original: String, normalized: String, request: String) -> JarvisInternetRequest? {
        for prefix in cityPrefixes {
            guard let city = JarvisFrenchCommandRouter.argument(in: original, normalized: normalized, after: prefix) else { continue }
            let cleaned = city.trimmingCharacters(in: CharacterSet(charactersIn: " ?!.,;:«»\""))
            let words = JarvisFrenchCommandRouter.normalize(cleaned).split(separator: " ").map(String.init)
            let notAPlace: Set<String> = ["cote", "pres", "loin", "chez", "rue", "avenue", "boulevard", "etage", "maison", "appartement", "ici"]
            guard !words.isEmpty, words.count <= 4, !words.contains(where: { notAPlace.contains($0) }),
                  !cleaned.contains(where: \.isNumber) else { return nil }
            return .setCity(cleaned)
        }
        if has(request, wherePhrases) { return .whereAmI }
        if has(request, newsPhrases) { return .news }
        guard has(request, weatherPhrases) else { return nil }
        let dayOffset = has(request, ["apres demain"]) ? 2 : (has(request, ["demain"]) ? 1 : 0)
        return .weather(city: city(inWeather: request), dayOffset: dayOffset)
    }

    /// The city after the weather words: « quel temps fait-il à Rio de Janeiro demain ? »
    /// gives « rio de janeiro »; nil when the sentence names no place.
    static func city(inWeather request: String) -> String? {
        // The words after the first weather words: « quel temps | fait il a lyon ».
        let padded = " \(request) "
        var earliest: Range<String.Index>?
        for phrase in weatherPhrases {
            guard let range = padded.range(of: " \(phrase) ") else { continue }
            if let known = earliest, known.lowerBound <= range.lowerBound { continue }
            earliest = range
        }
        guard let found = earliest else { return nil }
        var words = padded[found.upperBound...].split(separator: " ").map(String.init)
        while let index = words.firstIndex(where: { cityPrepositions.contains($0) }) {
            words = Array(words[(index + 1)...])
            if let first = words.first, verbsBeforePlace.contains(first) { continue }
            var candidate: [String] = []
            for position in words.indices {
                if startsWithTime(words[position...]) { break }
                candidate.append(words[position])
            }
            while let last = candidate.last, cityPrepositions.contains(last) {
                candidate.removeLast()
            }
            let city = candidate.joined(separator: " ")
            if !city.isEmpty, !notCities.contains(city) { return city }
        }
        return nil
    }

    private static func startsWithTime(_ words: ArraySlice<String>) -> Bool {
        for phrase in timePhrases where words.count >= phrase.count {
            if Array(words.prefix(phrase.count)) == phrase { return true }
        }
        return false
    }

    /// Whole words, like the router: « quel temps » is in « quel temps fait il ».
    static func has(_ request: String, _ phrases: [String]) -> Bool {
        let padded = " \(request) "
        return phrases.contains { padded.contains(" \($0) ") }
    }
}

// MARK: - Weather (Open-Meteo)

struct JarvisPlace: Equatable {
    let name: String
    let latitude: Double
    let longitude: Double
}

enum JarvisWeatherReport {
    /// Open-Meteo's weather codes (WMO), in French.
    static let skies: [Int: String] = [
        0: "ciel dégagé", 1: "ciel plutôt dégagé", 2: "partiellement nuageux", 3: "ciel couvert",
        45: "brouillard", 48: "brouillard givrant", 51: "bruine légère", 53: "bruine", 55: "bruine dense",
        56: "bruine verglaçante", 57: "bruine verglaçante dense", 61: "pluie faible", 63: "pluie", 65: "forte pluie",
        66: "pluie verglaçante", 67: "forte pluie verglaçante", 71: "neige faible", 73: "neige", 75: "forte neige",
        77: "grains de neige", 80: "averses", 81: "averses", 82: "fortes averses", 85: "averses de neige",
        86: "fortes averses de neige", 95: "orage", 96: "orage avec grêle", 99: "orage avec forte grêle",
    ]

    /// Two decimals, about a kilometre: enough for the weather, and no more is sent.
    static func rounded(_ coordinate: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), coordinate)
    }

    /// The first place of Open-Meteo's geocoding answer.
    static func place(fromGeocoding object: [String: Any]) -> JarvisPlace? {
        guard let first = (object["results"] as? [[String: Any]])?.first,
              let latitude = number(first["latitude"]), let longitude = number(first["longitude"]) else { return nil }
        return JarvisPlace(name: (first["name"] as? String) ?? "", latitude: latitude, longitude: longitude)
    }

    /// « À Lyon, il fait 12 degrés, ciel couvert. Aujourd'hui, entre 8 et 14 degrés… »
    /// from Open-Meteo's forecast; nil when it cannot be read.
    static func sentence(place: String?, forecast: [String: Any], dayOffset: Int) -> String? {
        guard let daily = forecast["daily"] as? [String: Any],
              let low = number(daily["temperature_2m_min"], at: dayOffset),
              let high = number(daily["temperature_2m_max"], at: dayOffset) else { return nil }
        let sky = number(daily["weather_code"], at: dayOffset).flatMap { skies[Int($0)] } ?? "temps variable"
        let rain = number(daily["precipitation_probability_max"], at: dayOffset).map { chance -> String in
            let percent = Int(chance.rounded())
            return percent == 0 ? ", sans pluie prévue" : ", \(percent) % de risque de pluie"
        } ?? ""
        let range = "entre \(degrees(low, withUnit: false)) et \(degrees(high))"
        let town = (place?.isEmpty ?? true) ? nil : place
        if dayOffset > 0 {
            let day = dayOffset == 1 ? "Demain" : "Après-demain"
            return "\(day)\(town.map { " à \($0)" } ?? "") : \(sky), \(range)\(rain)."
        }
        guard let current = forecast["current"] as? [String: Any], let temperature = number(current["temperature_2m"]) else {
            return "Aujourd'hui\(town.map { " à \($0)" } ?? "") : \(sky), \(range)\(rain)."
        }
        let nowSky = number(current["weather_code"]).flatMap { skies[Int($0)] } ?? sky
        var opening = "\(town.map { "À \($0)" } ?? "Ici"), il fait \(degrees(temperature)), \(nowSky)"
        if let felt = number(current["apparent_temperature"]), abs(felt.rounded() - temperature.rounded()) >= 3 {
            opening += ", ressenti \(degrees(felt))"
        }
        if let wind = number(current["wind_speed_10m"]), wind >= 40 {
            opening += ", vent fort à \(Int(wind.rounded())) kilomètres-heure"
        }
        return "\(opening). Aujourd'hui, \(range)\(rain)."
    }

    /// « 12 degrés », « 1 degré », « moins 3 degrés ».
    static func degrees(_ value: Double, withUnit: Bool = true) -> String {
        let whole = Int(value.rounded())
        let figure = whole < 0 ? "moins \(-whole)" : "\(whole)"
        guard withUnit else { return figure }
        return "\(figure) \(abs(whole) < 2 ? "degré" : "degrés")"
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    static func number(_ list: Any?, at index: Int) -> Double? {
        guard let list = list as? [Any], index >= 0, index < list.count else { return nil }
        return number(list[index])
    }
}

// MARK: - Wikipédia

enum JarvisWikipediaAnswer {
    /// « Qui est Marie Curie ? », « C'est quoi un trou noir ? », « Parle-moi de la Révolution française ».
    static let prefixes = [
        "cherche sur wikipedia", "wikipedia", "dis moi qui est", "dis moi qui etait", "sais tu qui est", "tu sais qui est",
        "qui est", "qui etait", "qui sont", "qui etaient", "c'est qui", "qu'est ce que c'est que", "qu'est ce qu'un",
        "qu'est ce qu'une", "qu'est ce que", "c'est quoi", "parle moi de", "parle moi du", "parle moi des", "parle moi",
        "definition de", "definis",
    ]
    /// A question about the person or the conversation, which the brain answers better.
    static let personalWords: Set<String> = [
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles", "ce", "ca", "cela", "ceci", "moi", "toi", "lui",
        "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa", "ses", "notre", "nos", "votre", "vos", "leur", "leurs",
        "jarvis", "que", "quoi", "qui", "y", "l'on",
    ]
    static let personalElisions = ["j'", "t'", "m'", "s'", "c'", "qu'", "n'"]
    static let lonelyWords: Set<String> = ["la", "le", "les", "la bas", "ici", "present", "presente", "dehors"]
    static let superlatives = ["le plus", "la plus", "les plus", "le meilleur", "la meilleure", "les meilleurs", "les meilleures", "le pire", "la pire"]

    /// The subject in the user's own words, or nil when the question is not one for
    /// Wikipédia (« Qui est-ce ? », « C'est quoi ton prénom ? », « Qui est le plus fort ? »).
    static func subject(in question: String) -> String? {
        let normalized = JarvisFrenchCommandRouter.normalize(question)
        for prefix in prefixes {
            guard let raw = JarvisFrenchCommandRouter.argument(in: question, normalized: normalized, after: prefix) else { continue }
            var subject = raw.trimmingCharacters(in: CharacterSet(charactersIn: " ?!.,;:«»\""))
            if prefix == "parle moi" {
                // « Parle-moi d'Einstein »
                subject = subject.replacingOccurrences(of: "^(de |d'|d’)", with: "", options: [.regularExpression, .caseInsensitive])
            }
            let words = JarvisFrenchCommandRouter.normalize(subject).split(separator: " ").map(String.init)
            let joined = words.joined(separator: " ")
            guard let first = words.first, words.count <= 6, !subject.contains(where: \.isNumber),
                  !personalWords.contains(first), !personalElisions.contains(where: { first.hasPrefix($0) }),
                  !lonelyWords.contains(joined), !superlatives.contains(where: { joined == $0 || joined.hasPrefix($0 + " ") }) else { return nil }
            return subject
        }
        return nil
    }

    /// The article of the search-and-extract answer (formatversion 2), unless it is a
    /// disambiguation page or has no text.
    static func article(from object: [String: Any]) -> (title: String, extract: String)? {
        guard let pages = (object["query"] as? [String: Any])?["pages"] as? [[String: Any]], !pages.isEmpty else { return nil }
        let page = pages.min { (($0["index"] as? Int) ?? 0) < (($1["index"] as? Int) ?? 0) } ?? pages[0]
        if let properties = page["pageprops"] as? [String: Any], properties["disambiguation"] != nil { return nil }
        guard let title = page["title"] as? String,
              let extract = (page["extract"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !extract.isEmpty else { return nil }
        return (title, extract)
    }

    /// The extract to say: without brackets or parentheses (pronunciation, dates), and only
    /// its first sentence when the two are long.
    static func spoken(_ extract: String) -> String {
        var text = extract.replacingOccurrences(of: "\n", with: " ")
        var previous = ""
        while previous != text {
            previous = text
            text = text.replacingOccurrences(of: "\\s*\\([^()]*\\)", with: "", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "\\s*\\[[^\\[\\]]*\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: " ,", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 320, let first = firstSentence(of: text) { return first }
        return text
    }

    /// The text up to the end of its first sentence, not cut after « M. » or « av. J.-C. ».
    static func firstSentence(of text: String) -> String? {
        let abbreviations: Set<String> = ["m", "mm", "mme", "mlle", "mgr", "dr", "st", "ste", "av", "apr", "env", "etc", "cf", "ex", "p", "vol", "chap", "art", "j.-c"]
        let characters = Array(text)
        for index in characters.indices where ".!?".contains(characters[index]) {
            let next = index + 1
            guard next + 1 < characters.count, characters[next] == " ", characters[next + 1].isUppercase else { continue }
            if characters[index] == "." {
                let before = String(characters[..<index]).split(separator: " ").last.map { $0.lowercased() } ?? ""
                if before.count <= 1 || abbreviations.contains(before) { continue }
            }
            return String(characters[...index])
        }
        return nil
    }
}

// MARK: - News (franceinfo)

/// The titles of an RSS feed's items (franceinfo's « Les Titres »).
final class JarvisNewsFeedParser: NSObject, XMLParserDelegate {
    private var titles: [String] = []
    private var insideItem = false
    private var title: String?

    static func titles(from data: Data, limit: Int = 5) -> [String] {
        let reader = JarvisNewsFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return Array(reader.titles.prefix(limit))
    }

    /// The first three said, all of them on screen.
    static func answer(_ titles: [String]) -> (spoken: String, display: String) {
        let spoken = "Voici les titres de franceinfo : " + titles.prefix(3).joined(separator: " ; ") + "."
        let display = "franceinfo, à la une :\n" + titles.map { "• \($0)" }.joined(separator: "\n")
        return (spoken, display)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if elementName == "item" {
            insideItem = true
        } else if insideItem, elementName == "title" {
            title = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        title?.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard title != nil, let text = String(data: CDATABlock, encoding: .utf8) else { return }
        title?.append(text)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "title", let text = title {
            let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleaned.isEmpty { titles.append(cleaned) }
            title = nil
        } else if elementName == "item" {
            insideItem = false
        }
    }
}

// MARK: - « Où suis-je ? »

enum JarvisWhereAmI {
    /// « Vous êtes à Lyon, 12 rue de la République. » from the address iOS found.
    static func answer(number: String?, street: String?, postalCode: String?, town: String?, country: String?) -> (spoken: String, display: String)? {
        func filled(_ value: String?) -> String? {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            return value
        }
        let road = [filled(number), filled(street)].compactMap { $0 }.joined(separator: " ")
        let townName = filled(town)
        let spoken: String
        switch (townName, road.isEmpty) {
        case (let name?, false): spoken = "Vous êtes à \(name), \(road)."
        case (let name?, true): spoken = "Vous êtes à \(name)."
        case (nil, false): spoken = "Vous êtes près de \(road)."
        case (nil, true): return nil
        }
        let locality = [filled(postalCode), townName].compactMap { $0 }.joined(separator: " ")
        let display = [road, locality, filled(country) ?? ""].filter { !$0.isEmpty }.joined(separator: ", ")
        return (spoken, display)
    }
}
