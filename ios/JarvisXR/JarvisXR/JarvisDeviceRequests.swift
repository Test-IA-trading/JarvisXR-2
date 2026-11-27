import Foundation

// What the user asks of the iPhone's own data — contacts, steps, photos — and the French
// answers, without touching any of it: JarvisDeviceServices.swift reads the data, on the
// iPhone only, after iOS has asked the user.

// MARK: - Periods

enum JarvisDevicePeriod: String, Equatable {
    case today
    case yesterday
    case week

    /// From the start of the period to its end (now, for today and the week).
    func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        let startOfToday = calendar.startOfDay(for: now)
        switch self {
        case .today:
            return DateInterval(start: startOfToday, end: max(now, startOfToday))
        case .yesterday:
            let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday.addingTimeInterval(-86_400)
            return DateInterval(start: start, end: startOfToday)
        case .week:
            let start = calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday.addingTimeInterval(-6 * 86_400)
            return DateInterval(start: start, end: max(now, start))
        }
    }

    /// « Aujourd'hui », « Hier », « Ces sept derniers jours ».
    var opening: String {
        switch self {
        case .today: return "Aujourd'hui"
        case .yesterday: return "Hier"
        case .week: return "Ces sept derniers jours"
        }
    }

    static func find(in request: String) -> JarvisDevicePeriod {
        if JarvisInternetRequest.has(request, ["hier", "d'hier"]) { return .yesterday }
        if JarvisInternetRequest.has(request, ["cette semaine", "la semaine", "de la semaine", "7 derniers jours", "sept derniers jours", "depuis une semaine"]) {
            return .week
        }
        return .today
    }
}

// MARK: - What is asked

enum JarvisDeviceRequest: Equatable {
    case call(String)
    case message(to: String, body: String?)
    case phoneNumber(of: String)
    case steps(JarvisDevicePeriod)
    case photoCount(JarvisDevicePeriod)
    case showPhotos(JarvisDevicePeriod, latestOnly: Bool)

    static let callPrefixes = [
        "passe un coup de fil a", "passe un appel a", "lance un appel a", "compose le numero de", "telephone a",
        "telephone au", "appelle", "appeler",
    ]
    static let messagePrefixes = [
        "envoie un message a", "envoie un message au", "envoie un sms a", "envoie un texto a", "envoie un mot a",
        "ecris un message a", "ecris a", "ecris au", "dis a",
    ]
    static let numberPrefixes = [
        "quel est le numero de telephone de", "quel est le numero de", "c'est quoi le numero de", "donne moi le numero de",
        "quel est le numero d'", "numero de telephone de", "le numero de",
    ]
    static let stepPhrases = [
        "combien de pas", "nombre de pas", "mes pas", "combien j'ai marche", "combien ai je marche", "distance parcourue",
        "quelle distance j'ai", "quelle distance ai je", "j'ai parcouru", "combien de kilometres j'ai", "combien d'etages",
        "podometre", "mon podometre",
    ]
    static let photoCountPhrases = ["combien de photos", "nombre de photos", "combien de videos"]
    static let latestPhotoPhrases = ["ma derniere photo", "la derniere photo", "quand ai je pris ma derniere photo"]
    static let photoShowPhrases = [
        "montre moi mes photos", "montre mes photos", "affiche mes photos", "mes dernieres photos", "mes photos d'hier",
        "mes photos d'aujourd'hui", "mes photos de la semaine", "les photos d'aujourd'hui", "les photos d'hier",
    ]

    static func parse(original: String, normalized: String, request: String) -> JarvisDeviceRequest? {
        let has = { (phrases: [String]) in JarvisInternetRequest.has(request, phrases) }
        if has(stepPhrases) { return .steps(JarvisDevicePeriod.find(in: request)) }
        if has(photoCountPhrases) { return .photoCount(JarvisDevicePeriod.find(in: request)) }
        if has(latestPhotoPhrases) { return .showPhotos(.today, latestOnly: true) }
        if has(photoShowPhrases) { return .showPhotos(JarvisDevicePeriod.find(in: request), latestOnly: false) }

        for prefix in numberPrefixes {
            guard let name = JarvisFrenchCommandRouter.argument(in: original, normalized: normalized, after: prefix) else { continue }
            let cleaned = clean(name)
            return cleaned.isEmpty ? nil : .phoneNumber(of: cleaned)
        }
        for prefix in messagePrefixes {
            guard let rest = JarvisFrenchCommandRouter.argument(in: original, normalized: normalized, after: prefix) else { continue }
            let (name, body) = splitRecipient(rest)
            // « Dis à Paul que… » is a message only with what to say.
            if prefix == "dis a", body == nil { return nil }
            guard !name.isEmpty else { return nil }
            return .message(to: name, body: body)
        }
        for prefix in callPrefixes {
            guard let name = JarvisFrenchCommandRouter.argument(in: original, normalized: normalized, after: prefix) else { continue }
            let cleaned = clean(name)
            // « Appelle-moi Tony » gives the first name (handled before); « appelle-le » is no name.
            let first = JarvisFrenchCommandRouter.normalize(cleaned).split(separator: " ").first.map(String.init) ?? ""
            guard !cleaned.isEmpty, !["moi", "le", "la", "les", "lui", "nous", "jarvis"].contains(first) || cleaned.contains(where: \.isNumber) else { return nil }
            return .call(cleaned)
        }
        return nil
    }

    /// « Paul que j'arrive » → (« Paul », « j'arrive »); « Paul » → (« Paul », nil).
    static func splitRecipient(_ text: String) -> (name: String, body: String?) {
        let separators = [" pour lui dire que ", " pour lui dire qu'", " pour dire que ", " que ", " qu'", " qu’", " : ", ", "]
        var best: Range<String.Index>?
        for separator in separators {
            guard let range = text.range(of: separator, options: .caseInsensitive) else { continue }
            if let known = best, known.lowerBound <= range.lowerBound { continue }
            best = range
        }
        guard let split = best else { return (clean(text), nil) }
        let name = clean(String(text[..<split.lowerBound]))
        let body = String(text[split.upperBound...]).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "«»\"")))
        return (name, body.isEmpty ? nil : body)
    }

    static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " ?!.,;:«»\"").union(.whitespacesAndNewlines))
    }
}

// MARK: - Contacts

struct JarvisPhone: Equatable {
    let label: String?
    let number: String
}

/// A contact as Jarvis compares it: its names in the router's normalized form.
struct JarvisContactCandidate: Equatable {
    let identifier: String
    let displayName: String
    let names: [String]
    let phones: [JarvisPhone]

    init(identifier: String, displayName: String, givenName: String = "", familyName: String = "", nickname: String = "", organization: String = "", phones: [JarvisPhone]) {
        self.identifier = identifier
        self.displayName = displayName
        let given = JarvisFrenchCommandRouter.normalize(givenName)
        let family = JarvisFrenchCommandRouter.normalize(familyName)
        let fields = [displayName, nickname, organization].map(JarvisFrenchCommandRouter.normalize) + [
            given, family, "\(given) \(family)", "\(family) \(given)",
        ]
        names = fields.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        self.phones = phones
    }
}

enum JarvisContactMatch: Equatable {
    case one(JarvisContactCandidate)
    case several([JarvisContactCandidate])
    case nobody
}

enum JarvisContactMatcher {
    /// What « maman », « ma mère », « papa » may be called in the contacts.
    static let synonyms: [String: [String]] = [
        "maman": ["maman", "mere", "ma mere", "mom", "mum"],
        "ma mere": ["maman", "mere", "ma mere", "mom", "mum"],
        "papa": ["papa", "pere", "mon pere", "dad"],
        "mon pere": ["papa", "pere", "mon pere", "dad"],
        "mamie": ["mamie", "grand mere", "ma grand mere", "mamy", "meme"],
        "ma grand mere": ["mamie", "grand mere", "mamy", "meme"],
        "papi": ["papi", "grand pere", "mon grand pere", "papy", "pepe"],
        "mon grand pere": ["papi", "grand pere", "papy", "pepe"],
    ]

    /// The contact meant by `spoken`: an exact name first, then a name that starts with it
    /// (« Paul » for « Paul Dupont »), then one that holds all its words.
    static func match(_ spoken: String, in candidates: [JarvisContactCandidate]) -> JarvisContactMatch {
        let target = JarvisFrenchCommandRouter.normalize(spoken)
        guard !target.isEmpty else { return .nobody }
        var targets = [target] + (synonyms[target] ?? [])
        for possessive in ["mon ", "ma ", "mes "] where target.hasPrefix(possessive) {
            targets.append(String(target.dropFirst(possessive.count)))
        }
        for wanted in targets {
            var bestScore = 0
            var best: [JarvisContactCandidate] = []
            for candidate in candidates {
                let value = score(wanted, candidate)
                if value > bestScore {
                    bestScore = value
                    best = [candidate]
                } else if value == bestScore, value > 0 {
                    best.append(candidate)
                }
            }
            guard bestScore > 0 else { continue }
            var seen = Set<String>()
            let distinct = best.filter { seen.insert(JarvisFrenchCommandRouter.normalize($0.displayName)).inserted }
            return distinct.count == 1 ? .one(distinct[0]) : .several(Array(distinct.prefix(4)))
        }
        return .nobody
    }

    static func score(_ wanted: String, _ candidate: JarvisContactCandidate) -> Int {
        if candidate.names.contains(wanted) { return 3 }
        if candidate.names.contains(where: { $0.hasPrefix(wanted + " ") }) { return 2 }
        let words = Set(candidate.names.flatMap { $0.split(separator: " ").map(String.init) })
        let wantedWords = wanted.split(separator: " ").map(String.init)
        if !wantedWords.isEmpty, wantedWords.allSatisfy({ words.contains($0) }) { return 1 }
        return 0
    }

    /// The mobile number when there is one, else the first.
    static func preferredPhone(_ phones: [JarvisPhone]) -> JarvisPhone? {
        phones.first { phone in
            let label = (phone.label ?? "").lowercased()
            return label.contains("mobile") || label.contains("iphone") || label.contains("portable")
        } ?? phones.first
    }

    /// « +33 6 12 34 56 78 » → « +33612345678 », for the phone app.
    static func dialable(_ number: String) -> String {
        var digits = number.filter { $0.isASCII && $0.isNumber }
        if number.trimmingCharacters(in: .whitespaces).hasPrefix("+") { digits = "+" + digits }
        return digits
    }

    /// « Paul Dupont, Paul Martin ou Paul Durand ».
    static func choices(_ candidates: [JarvisContactCandidate]) -> String {
        let names = candidates.map(\.displayName)
        guard names.count > 1 else { return names.first ?? "" }
        return names.dropLast().joined(separator: ", ") + " ou " + names[names.count - 1]
    }
}

// MARK: - Steps and photos, said in French

enum JarvisDeviceSentences {
    /// « Aujourd'hui, vous avez fait 8432 pas, soit 6,1 kilomètres, et monté 4 étages. »
    static func steps(_ steps: Int, meters: Double?, floors: Int?, period: JarvisDevicePeriod) -> String {
        guard steps > 0 else {
            return period == .today ? "Aujourd'hui, je ne compte encore aucun pas." : "\(period.opening), je ne compte aucun pas."
        }
        var sentence = "\(period.opening), vous avez fait \(steps) pas"
        if period == .week {
            sentence += ", soit \(Int((Double(steps) / 7).rounded())) par jour en moyenne"
        }
        if let meters, meters >= 1 {
            sentence += period == .week ? ", pour \(distance(meters))" : ", soit \(distance(meters))"
        }
        if let floors, floors > 0 {
            sentence += ", et monté \(floors) \(floors == 1 ? "étage" : "étages")"
        }
        return sentence + "."
    }

    /// « 850 mètres », « 6,1 kilomètres ».
    static func distance(_ meters: Double) -> String {
        guard meters >= 1000 else { return "\(Int(meters.rounded())) mètres" }
        let kilometres = (meters / 100).rounded() / 10
        let whole = kilometres.rounded(.down)
        let text = kilometres == whole ? "\(Int(whole))" : "\(Int(whole)),\(Int(((kilometres - whole) * 10).rounded()))"
        return "\(text) \(kilometres < 2 ? "kilomètre" : "kilomètres")"
    }

    /// « Hier, vous avez pris 12 photos et 2 vidéos. »
    static func photoCount(photos: Int, videos: Int, period: JarvisDevicePeriod) -> String {
        func count(_ value: Int, _ singular: String, _ plural: String) -> String {
            value == 0 ? "aucune \(singular)" : "\(value) \(value == 1 ? singular : plural)"
        }
        if photos == 0 && videos == 0 {
            return "\(period.opening), vous n'avez pris aucune photo."
        }
        if photos == 0 {
            return "\(period.opening), vous n'avez pris aucune photo, mais \(count(videos, "vidéo", "vidéos"))."
        }
        let videoText = videos > 0 ? " et \(count(videos, "vidéo", "vidéos"))" : ""
        return "\(period.opening), vous avez pris \(count(photos, "photo", "photos"))\(videoText)."
    }

    /// « Votre dernière photo date d'aujourd'hui à 14 h 05. »
    static func latestPhoto(taken date: Date, now: Date, calendar: Calendar = .current) -> String {
        let clock = DateFormatter()
        clock.locale = Locale(identifier: "fr_FR")
        clock.calendar = calendar
        clock.timeZone = calendar.timeZone
        clock.dateFormat = "H 'h' mm"
        let time = clock.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "Votre dernière photo date d'aujourd'hui à \(time)." }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Votre dernière photo date d'hier à \(time)."
        }
        let day = DateFormatter()
        day.locale = Locale(identifier: "fr_FR")
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "EEEE d MMMM" : "EEEE d MMMM yyyy"
        return "Votre dernière photo date du \(day.string(from: date)) à \(time)."
    }
}
