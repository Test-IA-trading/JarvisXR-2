import Foundation

/// Unit conversions that must be exact and need no network: « 10 miles en kilomètres »,
/// « Combien de mètres dans un mile ? », « 100 degrés Fahrenheit en Celsius ». Like
/// JarvisMathSolver, a sentence not read completely returns nil and goes elsewhere.
enum JarvisUnitConverter {
    struct Unit {
        let dimension: String
        /// Value of one unit in the base unit of its dimension (unused for temperatures).
        let factor: Double
        let singular: String
        let plural: String
        let symbol: String
        /// Folded spellings, as JarvisMathSolver.prepare writes them.
        let aliases: [String]
    }

    static let units: [Unit] = [
        Unit(dimension: "longueur", factor: 0.001, singular: "millimètre", plural: "millimètres", symbol: "mm", aliases: ["mm", "millimetre", "millimetres"]),
        Unit(dimension: "longueur", factor: 0.01, singular: "centimètre", plural: "centimètres", symbol: "cm", aliases: ["cm", "centimetre", "centimetres"]),
        Unit(dimension: "longueur", factor: 1, singular: "mètre", plural: "mètres", symbol: "m", aliases: ["m", "metre", "metres"]),
        Unit(dimension: "longueur", factor: 1000, singular: "kilomètre", plural: "kilomètres", symbol: "km", aliases: ["km", "kilometre", "kilometres"]),
        Unit(dimension: "longueur", factor: 0.0254, singular: "pouce", plural: "pouces", symbol: "in", aliases: ["pouce", "pouces", "inch", "inches"]),
        Unit(dimension: "longueur", factor: 0.3048, singular: "pied", plural: "pieds", symbol: "ft", aliases: ["pied", "pieds", "foot", "feet", "ft"]),
        Unit(dimension: "longueur", factor: 0.9144, singular: "yard", plural: "yards", symbol: "yd", aliases: ["yard", "yards"]),
        Unit(dimension: "longueur", factor: 1609.344, singular: "mile", plural: "miles", symbol: "mi", aliases: ["mile", "miles"]),
        Unit(dimension: "longueur", factor: 1852, singular: "mille marin", plural: "milles marins", symbol: "NM", aliases: ["mille marin", "milles marins", "mille nautique", "milles nautiques"]),
        Unit(dimension: "masse", factor: 0.000001, singular: "milligramme", plural: "milligrammes", symbol: "mg", aliases: ["mg", "milligramme", "milligrammes"]),
        Unit(dimension: "masse", factor: 0.001, singular: "gramme", plural: "grammes", symbol: "g", aliases: ["g", "gramme", "grammes"]),
        Unit(dimension: "masse", factor: 1, singular: "kilogramme", plural: "kilogrammes", symbol: "kg", aliases: ["kg", "kilo", "kilos", "kilogramme", "kilogrammes"]),
        Unit(dimension: "masse", factor: 1000, singular: "tonne", plural: "tonnes", symbol: "t", aliases: ["tonne", "tonnes"]),
        Unit(dimension: "masse", factor: 0.45359237, singular: "livre", plural: "livres", symbol: "lb", aliases: ["livre", "livres", "lb", "lbs", "pound", "pounds"]),
        Unit(dimension: "masse", factor: 0.028349523125, singular: "once", plural: "onces", symbol: "oz", aliases: ["once", "onces", "oz"]),
        Unit(dimension: "volume", factor: 0.001, singular: "millilitre", plural: "millilitres", symbol: "ml", aliases: ["ml", "millilitre", "millilitres"]),
        Unit(dimension: "volume", factor: 0.01, singular: "centilitre", plural: "centilitres", symbol: "cl", aliases: ["cl", "centilitre", "centilitres"]),
        Unit(dimension: "volume", factor: 1, singular: "litre", plural: "litres", symbol: "L", aliases: ["l", "litre", "litres"]),
        Unit(dimension: "volume", factor: 1000, singular: "mètre cube", plural: "mètres cubes", symbol: "m³", aliases: ["metre cube", "metres cubes", "m^(3)", "m3"]),
        Unit(dimension: "volume", factor: 3.785411784, singular: "gallon", plural: "gallons", symbol: "gal", aliases: ["gallon", "gallons"]),
        Unit(dimension: "temps", factor: 1, singular: "seconde", plural: "secondes", symbol: "s", aliases: ["s", "seconde", "secondes"]),
        Unit(dimension: "temps", factor: 60, singular: "minute", plural: "minutes", symbol: "min", aliases: ["min", "minute", "minutes"]),
        Unit(dimension: "temps", factor: 3600, singular: "heure", plural: "heures", symbol: "h", aliases: ["h", "heure", "heures"]),
        Unit(dimension: "temps", factor: 86400, singular: "jour", plural: "jours", symbol: "j", aliases: ["jour", "jours"]),
        Unit(dimension: "temps", factor: 604_800, singular: "semaine", plural: "semaines", symbol: "sem.", aliases: ["semaine", "semaines"]),
        Unit(dimension: "temps", factor: 31_557_600, singular: "an", plural: "ans", symbol: "an", aliases: ["an", "ans", "annee", "annees"]),
        Unit(dimension: "vitesse", factor: 1 / 3.6, singular: "kilomètre par heure", plural: "kilomètres par heure", symbol: "km/h", aliases: ["km/h", "kmh", "kilometre par heure", "kilometres par heure", "kilometre heure", "kilometres heure"]),
        Unit(dimension: "vitesse", factor: 1, singular: "mètre par seconde", plural: "mètres par seconde", symbol: "m/s", aliases: ["m/s", "metre par seconde", "metres par seconde"]),
        Unit(dimension: "vitesse", factor: 0.44704, singular: "mile par heure", plural: "miles par heure", symbol: "mph", aliases: ["mph", "mile par heure", "miles par heure", "miles heure"]),
        Unit(dimension: "vitesse", factor: 1852.0 / 3600.0, singular: "nœud", plural: "nœuds", symbol: "kn", aliases: ["noeud", "noeuds"]),
        Unit(dimension: "surface", factor: 1, singular: "mètre carré", plural: "mètres carrés", symbol: "m²", aliases: ["metre carre", "metres carres", "m^(2)", "m2"]),
        Unit(dimension: "surface", factor: 1_000_000, singular: "kilomètre carré", plural: "kilomètres carrés", symbol: "km²", aliases: ["kilometre carre", "kilometres carres", "km^(2)", "km2"]),
        Unit(dimension: "surface", factor: 100, singular: "are", plural: "ares", symbol: "a", aliases: ["are", "ares"]),
        Unit(dimension: "surface", factor: 10_000, singular: "hectare", plural: "hectares", symbol: "ha", aliases: ["hectare", "hectares", "ha"]),
        Unit(dimension: "surface", factor: 4046.8564224, singular: "acre", plural: "acres", symbol: "ac", aliases: ["acre", "acres"]),
        Unit(dimension: "données", factor: 1, singular: "octet", plural: "octets", symbol: "o", aliases: ["octet", "octets"]),
        Unit(dimension: "données", factor: 1e3, singular: "kilooctet", plural: "kilooctets", symbol: "ko", aliases: ["ko", "kilooctet", "kilooctets", "kilo octet", "kilo octets"]),
        Unit(dimension: "données", factor: 1e6, singular: "mégaoctet", plural: "mégaoctets", symbol: "Mo", aliases: ["mo", "megaoctet", "megaoctets", "mega octet", "mega octets"]),
        Unit(dimension: "données", factor: 1e9, singular: "gigaoctet", plural: "gigaoctets", symbol: "Go", aliases: ["go", "gigaoctet", "gigaoctets", "giga octet", "giga octets"]),
        Unit(dimension: "données", factor: 1e12, singular: "téraoctet", plural: "téraoctets", symbol: "To", aliases: ["to", "teraoctet", "teraoctets", "tera octet", "tera octets"]),
        Unit(dimension: "température", factor: 1, singular: "degré Celsius", plural: "degrés Celsius", symbol: "°C", aliases: ["degre celsius", "degres celsius", "celsius", "°c", "degre", "degres"]),
        Unit(dimension: "température", factor: 1, singular: "degré Fahrenheit", plural: "degrés Fahrenheit", symbol: "°F", aliases: ["degre fahrenheit", "degres fahrenheit", "fahrenheit", "°f"]),
        Unit(dimension: "température", factor: 1, singular: "kelvin", plural: "kelvins", symbol: "K", aliases: ["kelvin", "kelvins"]),
    ]

    /// Words around a conversion that carry no meaning: « Convertis… en… s'il te plaît ».
    private static let fillers: Set<String> = [
        "convertis", "convertir", "convertit", "convertissez", "conversion", "combien", "font", "fait", "ca", "de", "d'", "en",
        "vers", "dans", "pour", "y", "a", "t", "il", "est", "c'", "egale", "s'", "te", "vous", "plait", "svp", "stp", "jarvis",
        "les", "des", "le", "la", "l'", "un", "une", "quel", "quelle", "nombre", "donne", "moi", "dis", "peux", "tu", "me",
        "m'", "fais", "font-ils", "ok", "alors", "exactement", "environ", "valent", "vaut", "equivalent", "egalent",
    ]

    private static let aliasIndex: [(words: [String], unit: Int)] = {
        var index: [(words: [String], unit: Int)] = []
        for (position, unit) in units.enumerated() {
            for alias in unit.aliases {
                index.append((alias.split(separator: " ").map(String.init), position))
            }
        }
        return index.sorted { $0.words.count > $1.words.count }
    }()

    static func answer(to original: String) -> JarvisMathSolver.Answer? {
        var text = JarvisMathSolver.prepare(original)
        text = text.replacingRegex(#"(\d)([a-z°])"#, with: "$1 $2")
        let tokens = text.split(separator: " ").map(String.init)
        guard tokens.contains(where: { JarvisMathSolver.isNumberToken($0) || $0 == "un" || $0 == "une" }) else { return nil }

        // Every unit mentioned, with its position; a number right before it is its amount.
        var mentions: [(unit: Int, start: Int, end: Int)] = []
        var index = 0
        while index < tokens.count {
            if let match = aliasIndex.first(where: { entry in
                index + entry.words.count <= tokens.count && Array(tokens[index..<(index + entry.words.count)]) == entry.words
            }) {
                mentions.append((match.unit, index, index + match.words.count))
                index += match.words.count
            } else {
                index += 1
            }
        }
        guard mentions.count == 2 else { return nil }
        // The source has an amount right before it: « 10 miles », « un mile », « moins 5 degrés ».
        func amount(before position: Int) -> (value: Double, written: String, length: Int)? {
            guard position >= 1 else { return nil }
            let token = tokens[position - 1]
            var value: Double
            var written: String
            if JarvisMathSolver.isNumberToken(token), let number = Double(token) {
                value = number
                written = JarvisMathSolver.writtenNumber(token)
            } else if token == "un" || token == "une" {
                value = 1
                written = "1"
            } else {
                return nil
            }
            var length = 1
            if position >= 2, tokens[position - 2] == "moins" || tokens[position - 2] == "-" {
                value = -value
                written = "−" + written
                length = 2
            }
            return (value, written, length)
        }
        let first = mentions[0]
        let second = mentions[1]
        let source: (unit: Int, start: Int, end: Int)
        let target: (unit: Int, start: Int, end: Int)
        let quantity: (value: Double, written: String, length: Int)
        if let found = amount(before: first.start) {
            source = first
            target = second
            quantity = found
        } else if let found = amount(before: second.start) {
            source = second
            target = first
            quantity = found
        } else {
            return nil
        }
        let from = units[source.unit]
        let to = units[target.unit]
        guard from.dimension == to.dimension, source.unit != target.unit else { return nil }

        // Nothing else may be said: an unknown word means this is not a conversion.
        var used = Set(source.start..<source.end).union(target.start..<target.end)
        for offset in 1...quantity.length { used.insert(source.start - offset) }
        for (position, token) in tokens.enumerated() where !used.contains(position) {
            guard fillers.contains(token) else { return nil }
        }

        let result = convert(quantity.value, from: from, to: to)
        guard result.isFinite else { return nil }
        let spokenResult = spokenValue(result)
        let fromName = abs(quantity.value) >= 2 ? from.plural : from.singular
        let toName = abs(result) >= 2 ? to.plural : to.singular
        let verb = abs(quantity.value) >= 2 ? "font" : "fait"
        // Durations read better in words: « 2 ans = 730,5 jours ».
        let fromLabel = from.dimension == "temps" ? fromName : from.symbol
        let toLabel = to.dimension == "temps" ? toName : to.symbol
        return JarvisMathSolver.Answer(
            spoken: "\(quantity.written) \(fromName) \(verb) \(spokenResult) \(toName).",
            display: "\(quantity.written) \(fromLabel) = \(JarvisMathSolver.decimalText(result, decimals: 4)) \(toLabel)"
        )
    }

    static func convert(_ value: Double, from: Unit, to: Unit) -> Double {
        guard from.dimension == "température" else {
            return value * from.factor / to.factor
        }
        let celsius: Double
        switch from.symbol {
        case "°F": celsius = (value - 32) * 5 / 9
        case "K": celsius = value - 273.15
        default: celsius = value
        }
        switch to.symbol {
        case "°F": return celsius * 9 / 5 + 32
        case "K": return celsius + 273.15
        default: return celsius
        }
    }

    /// 16,09 · 37,8 · 1609 — fewer decimals as the number grows, none when it is whole.
    static func spokenValue(_ value: Double) -> String {
        let magnitude = abs(value)
        let decimals = magnitude >= 1000 ? 0 : magnitude >= 100 ? 1 : magnitude >= 1 ? 2 : 4
        return JarvisMathSolver.decimalText(value, decimals: decimals)
    }
}

/// Date questions answered from the calendar: « Quel jour serons-nous dans 100 jours ? »,
/// « Combien de jours avant Noël ? », « Le 1er janvier 2027 tombe quel jour ? ».
enum JarvisDateAnswers {
    private static let months = ["janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre", "octobre", "novembre", "decembre"]
    private static let monthNames = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
    private static let weekdayNames = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]

    /// Named days, as folded words: « Noël », « le jour de l'an », « la Saint-Valentin »…
    private static let namedDays: [(words: [String], month: Int, day: Int, name: String)] = [
        (["noel"], 12, 25, "Noël"),
        (["jour", "de", "l'", "an"], 1, 1, "Le jour de l'an"),
        (["nouvel", "an"], 1, 1, "Le nouvel an"),
        (["saint", "valentin"], 2, 14, "La Saint-Valentin"),
        (["halloween"], 10, 31, "Halloween"),
        (["toussaint"], 11, 1, "La Toussaint"),
        (["fete", "nationale"], 7, 14, "La fête nationale"),
        (["fete", "du", "travail"], 5, 1, "La fête du Travail"),
        (["armistice"], 11, 11, "L'armistice"),
        (["reveillon"], 12, 31, "Le réveillon"),
    ]

    static func answer(to original: String, now: Date, calendar: Calendar = .current) -> JarvisMathSolver.Answer? {
        let text = JarvisMathSolver.prepare(original)
        let tokens = text.split(separator: " ").map(String.init)
        let padded = " \(text) "
        func has(_ phrase: String) -> Bool { padded.contains(" \(phrase) ") }

        // « dans 100 jours » / « il y a 3 semaines », with a question about the date.
        if let offset = offsetQuestion(tokens: tokens), has("quel jour") || has("quelle date") || has("serons") || has("sera") || has("etions") || has("etait") {
            guard let date = calendar.date(byAdding: offset.component, value: offset.value, to: now) else { return nil }
            let when = full(date, calendar: calendar)
            if offset.value >= 0 {
                return JarvisMathSolver.Answer(spoken: "Dans \(offset.phrase), nous serons le \(when).", display: "Dans \(offset.phrase) : \(when)")
            }
            return JarvisMathSolver.Answer(spoken: "Il y a \(offset.phrase), nous étions le \(when).", display: "Il y a \(offset.phrase) : \(when)")
        }

        guard let target = dateMention(tokens: tokens, now: now, calendar: calendar) else { return nil }
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: target.date).day ?? 0
        let when = full(target.date, calendar: calendar)

        // « Combien de jours avant Noël ? », « Dans combien de jours est le 14 juillet ? »
        if has("combien de jours") {
            switch days {
            case 0:
                return JarvisMathSolver.Answer(spoken: "\(target.name), c'est aujourd'hui !", display: "\(target.name) : aujourd'hui, \(when)")
            case 1:
                return JarvisMathSolver.Answer(spoken: "\(target.name), c'est demain, le \(when).", display: "\(target.name) : demain, \(when)")
            case let count where count > 1:
                return JarvisMathSolver.Answer(spoken: "\(target.name) est dans \(count) jours, le \(when).", display: "\(target.name) : dans \(count) jours, \(when)")
            default:
                return JarvisMathSolver.Answer(spoken: "\(target.name) était il y a \(-days) jours, le \(when).", display: "\(target.name) : il y a \(-days) jours, \(when)")
            }
        }
        // « Quel jour tombe le 1er janvier 2027 ? », « Noël, c'est quel jour ? »
        if has("quel jour") || has("tombe") || has("tombera") || has("tombait") {
            let verb = days < 0 ? "tombait" : days == 0 ? "tombe" : "tombera"
            let weekday = weekdayNames[calendar.component(.weekday, from: target.date) - 1]
            return JarvisMathSolver.Answer(spoken: "\(target.name) \(verb) un \(weekday) : le \(when).", display: "\(target.name) : \(when)")
        }
        return nil
    }

    /// « dans 100 jours », « dans trois semaines », « il y a 2 mois ».
    private static func offsetQuestion(tokens: [String]) -> (component: Calendar.Component, value: Int, phrase: String)? {
        for index in tokens.indices {
            let isFuture = tokens[index] == "dans"
            let isPast = index + 2 < tokens.count && tokens[index] == "il" && tokens[index + 1] == "y" && tokens[index + 2] == "a"
            guard isFuture || isPast else { continue }
            let numberIndex = isFuture ? index + 1 : index + 3
            guard numberIndex + 1 < tokens.count,
                  JarvisMathSolver.isNumberToken(tokens[numberIndex]),
                  let value = Int(tokens[numberIndex]), value <= 100_000 else { continue }
            let unit = tokens[numberIndex + 1]
            let component: Calendar.Component
            let word: String
            switch unit {
            case "jour", "jours":
                component = .day
                word = value > 1 ? "jours" : "jour"
            case "semaine", "semaines":
                component = .weekOfYear
                word = value > 1 ? "semaines" : "semaine"
            case "mois":
                component = .month
                word = "mois"
            case "an", "ans", "annee", "annees":
                component = .year
                word = value > 1 ? "ans" : "an"
            default:
                continue
            }
            return (component, isFuture ? value : -value, "\(value) \(word)")
        }
        return nil
    }

    /// A named day or « le 14 juillet [2027] », at its next occurrence when no year is said.
    private static func dateMention(tokens: [String], now: Date, calendar: Calendar) -> (date: Date, name: String)? {
        let today = calendar.startOfDay(for: now)
        let currentYear = calendar.component(.year, from: now)
        func resolve(month: Int, day: Int, year: Int?) -> Date? {
            if let year {
                return calendar.date(from: DateComponents(year: year, month: month, day: day))
            }
            guard let thisYear = calendar.date(from: DateComponents(year: currentYear, month: month, day: day)) else { return nil }
            return thisYear >= today ? thisYear : calendar.date(from: DateComponents(year: currentYear + 1, month: month, day: day))
        }
        func year(after index: Int) -> Int? {
            guard index < tokens.count, tokens[index].count == 4, let value = Int(tokens[index]), (1600...2400).contains(value) else { return nil }
            return value
        }
        for named in namedDays {
            for start in tokens.indices where start + named.words.count <= tokens.count {
                guard Array(tokens[start..<(start + named.words.count)]) == named.words else { continue }
                let explicitYear = year(after: start + named.words.count)
                guard let date = resolve(month: named.month, day: named.day, year: explicitYear) else { return nil }
                return (date, named.name)
            }
        }
        for (index, token) in tokens.enumerated() {
            guard let monthIndex = months.firstIndex(of: token), index >= 1 else { continue }
            let dayToken = tokens[index - 1]
            let day: Int
            if dayToken == "1er" || dayToken == "premier" {
                day = 1
            } else if let value = Int(dayToken), (1...31).contains(value) {
                day = value
            } else {
                continue
            }
            let explicitYear = year(after: index + 1)
            guard let date = resolve(month: monthIndex + 1, day: day, year: explicitYear),
                  calendar.component(.day, from: date) == day else { return nil }
            let dayText = day == 1 ? "1er" : "\(day)"
            let yearText = explicitYear.map { " \($0)" } ?? ""
            return (date, "Le \(dayText) \(monthNames[monthIndex])\(yearText)")
        }
        return nil
    }

    /// « vendredi 25 décembre 2026 », « vendredi 1er janvier 2027 ».
    static func full(_ date: Date, calendar: Calendar = .current) -> String {
        let weekday = weekdayNames[calendar.component(.weekday, from: date) - 1]
        let day = calendar.component(.day, from: date)
        let month = monthNames[calendar.component(.month, from: date) - 1]
        let year = calendar.component(.year, from: date)
        return "\(weekday) \(day == 1 ? "1er" : "\(day)") \(month) \(year)"
    }
}
