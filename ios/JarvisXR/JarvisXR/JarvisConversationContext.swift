import Foundation

/// A clock time said in French: « neuf heures », « 9 h 30 », « 21:15 », « midi »,
/// « onze heures et demie », « dix heures moins le quart ».
struct JarvisClockTime: Equatable, Comparable {
    let hour: Int
    let minute: Int

    init?(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        self.hour = hour
        self.minute = minute
    }

    var totalMinutes: Int { hour * 60 + minute }

    static func < (lhs: JarvisClockTime, rhs: JarvisClockTime) -> Bool {
        lhs.totalMinutes < rhs.totalMinutes
    }

    /// French wording, also good for speech synthesis: « midi », « minuit », « 9 h », « 11 h 30 ».
    var spoken: String {
        switch (hour, minute) {
        case (12, 0): return "midi"
        case (0, 0): return "minuit"
        case (_, 0): return "\(hour) h"
        default: return String(format: "%d h %02d", hour, minute)
        }
    }
}

/// Finds clock times in normalized French text (see `JarvisFrenchCommandRouter.normalize`).
enum JarvisFrenchTimeParser {
    struct Match: Equatable {
        let time: JarvisClockTime
        /// Index of the first and last token of the expression.
        let range: ClosedRange<Int>
    }

    private static let units: [String: Int] = [
        "zero": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7,
        "huit": 8, "neuf": 9, "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14,
        "quinze": 15, "seize": 16, "vingt": 20, "trente": 30, "quarante": 40, "cinquante": 50
    ]

    /// Reads a number (digits or French words, 0...59) starting at `index`.
    static func number(in tokens: [String], at index: Int) -> (value: Int, length: Int)? {
        guard tokens.indices.contains(index) else { return nil }
        let token = tokens[index]
        if let value = Int(token), (0...59).contains(value) {
            return (value, 1)
        }
        guard let first = units[token] else { return nil }
        var value = first
        var length = 1
        if first == 10, tokens.indices.contains(index + 1), let unit = units[tokens[index + 1]], (7...9).contains(unit) {
            // dix-sept, dix-huit, dix-neuf
            return (10 + unit, 2)
        }
        if [20, 30, 40, 50].contains(first) {
            var next = index + 1
            if tokens.indices.contains(next), tokens[next] == "et", tokens.indices.contains(next + 1), ["un", "une"].contains(tokens[next + 1]) {
                return (first + 1, 3)
            }
            if tokens.indices.contains(next), let unit = units[tokens[next]], (1...9).contains(unit) {
                value += unit
                length += 1
                next += 1
            }
        }
        return (value, length)
    }

    static func times(in tokens: [String]) -> [Match] {
        var matches: [Match] = []
        var index = 0
        while index < tokens.count {
            if let match = time(in: tokens, at: index) {
                matches.append(match)
                index = match.range.upperBound + 1
            } else {
                index += 1
            }
        }
        return matches
    }

    private static func time(in tokens: [String], at start: Int) -> Match? {
        let token = tokens[start]
        var hour: Int
        var minute = 0
        var end: Int

        // « 9h30 », « 9h », « 21:15 »
        if let compact = compactTime(token) {
            hour = compact.hour
            minute = compact.minute
            end = start
        } else if token == "midi" || token == "minuit" {
            hour = token == "midi" ? 12 : 0
            end = start
        } else if let parsed = number(in: tokens, at: start), parsed.value <= 23,
                  tokens.indices.contains(start + parsed.length),
                  ["h", "heure", "heures"].contains(tokens[start + parsed.length]) {
            hour = parsed.value
            end = start + parsed.length
            if let minutes = number(in: tokens, at: end + 1), minutes.value <= 59, !isFollowedByHourWord(tokens, at: end + 1 + minutes.length) {
                minute = minutes.value
                end += minutes.length
            }
        } else {
            return nil
        }

        // « et demie », « et quart », « moins le quart », « moins dix »
        if tokens.indices.contains(end + 2), tokens[end + 1] == "et" {
            if ["demie", "demi"].contains(tokens[end + 2]) { minute = 30; end += 2 }
            else if tokens[end + 2] == "quart" { minute = 15; end += 2 }
        } else if tokens.indices.contains(end + 1), tokens[end + 1] == "moins" {
            if tokens.indices.contains(end + 3), tokens[end + 2] == "le", tokens[end + 3] == "quart" {
                hour = (hour + 23) % 24
                minute = 45
                end += 3
            } else if let minutes = number(in: tokens, at: end + 2), (1...30).contains(minutes.value) {
                hour = (hour + 23) % 24
                minute = 60 - minutes.value
                end += 1 + minutes.length
            }
        }

        // « du soir », « de l'apres midi »
        if tokens.indices.contains(end + 2), tokens[end + 1] == "du", tokens[end + 2] == "soir", hour < 12 {
            hour += 12
            end += 2
        } else if tokens.indices.contains(end + 3), tokens[end + 1] == "de", tokens[end + 2] == "l'apres", tokens[end + 3] == "midi", hour < 12 {
            hour += 12
            end += 3
        } else if tokens.indices.contains(end + 2), tokens[end + 1] == "du", tokens[end + 2] == "matin" {
            end += 2
        }

        guard let time = JarvisClockTime(hour: hour, minute: minute) else { return nil }
        return Match(time: time, range: start...end)
    }

    private static func isFollowedByHourWord(_ tokens: [String], at index: Int) -> Bool {
        tokens.indices.contains(index) && ["h", "heure", "heures"].contains(tokens[index])
    }

    private static func compactTime(_ token: String) -> (hour: Int, minute: Int)? {
        let separators: [Character] = ["h", ":"]
        guard let separatorIndex = token.firstIndex(where: { separators.contains($0) }) else { return nil }
        let hourPart = token[token.startIndex..<separatorIndex]
        let minutePart = token[token.index(after: separatorIndex)...]
        guard let hour = Int(hourPart), (0...23).contains(hour) else { return nil }
        if minutePart.isEmpty {
            return token.last == "h" ? (hour, 0) : nil
        }
        guard minutePart.count == 2, let minute = Int(minutePart), (0...59).contains(minute) else { return nil }
        return (hour, minute)
    }
}

/// Short-term memory of the current conversation: facts the user stated (« le train
/// part à neuf heures »), the last question, and the last list of notes Jarvis counted.
/// Kept in memory for the app session; never written to disk.
final class JarvisConversationContext {
    static let shared = JarvisConversationContext()

    struct Departure: Equatable {
        /// « train », « navette », « avion »
        let subject: String
        /// « le train », « la navette », « l'avion »
        let phrase: String
        var time: JarvisClockTime
    }

    enum Question: Equatable {
        case earliest
        case latest
        case timeOf(String)
    }

    private(set) var departures: [Departure] = []
    private(set) var lastQuestion: Question?
    /// Result of the last « combien de notes » question: « montre-les-moi » lists it and
    /// « pose ce bilan sur la table » shows the same total.
    var lastNotesSummary: JarvisNotesSummary?

    /// Last exchanges, oldest first, given to the local brain so it follows the
    /// conversation (« et la deuxième ? »). Kept short and in memory only.
    private(set) var recentTurns: [JarvisChatTurn] = []
    static let maximumTurns = 6

    func recordTurn(user: String, assistant: String) {
        let question = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = assistant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !answer.isEmpty else { return }
        recentTurns.append(JarvisChatTurn(user: question, assistant: answer))
        if recentTurns.count > Self.maximumTurns {
            recentTurns.removeFirst(recentTurns.count - Self.maximumTurns)
        }
    }

    /// Facts the app knows for sure, written for the local brain's system prompt.
    func brainContextLines(scene: JarvisSpatialSceneMemory = .shared) -> [String] {
        var lines: [String] = []
        if !departures.isEmpty {
            let list = departures.map { "\($0.phrase) part à \($0.time.spoken)" }.joined(separator: ", ")
            lines.append("Horaires donnés par l'utilisateur dans cette conversation : \(list).")
        }
        if let moved = scene.lastManipulation {
            lines.append("Dernier objet virtuel déplacé par l'utilisateur en réalité augmentée : \(moved.spokenName.lowercased()).")
        }
        if let summary = lastNotesSummary {
            lines.append("Notes comptées \(summary.periodDescription) : \(summary.count).")
        }
        return lines
    }

    func reset() {
        departures = []
        lastQuestion = nil
        lastNotesSummary = nil
        recentTurns = []
    }

    private static let articles: Set<String> = ["le", "la", "les", "mon", "ma", "mes", "ton", "ta", "son", "sa", "notre", "votre", "leur", "ce", "cet", "cette"]
    private static let departureVerbs: Set<String> = ["part", "partira", "partent", "partiront", "decolle", "decollera", "pars"]
    private static let correctionMarkers = ["en fait", "finalement", "correction", "plutot", "je me suis trompe", "non"]

    /// Answers when the utterance states departures, corrects them or asks about them.
    /// Returns nil when it is about something else, so other routes can handle it.
    func respond(to normalizedRequest: String) -> String? {
        let tokens = normalizedRequest.split(separator: " ").map(String.init)
        let padded = " \(normalizedRequest) "
        func has(_ needles: [String]) -> Bool { needles.contains { padded.contains(" \($0) ") } }

        let stated = parseDepartures(tokens)
        let isCorrection = has(Self.correctionMarkers)
        var replies: [String] = []

        if !stated.isEmpty {
            let knownSubjects = Set(departures.map(\.subject))
            let mentionsKnown = stated.contains { knownSubjects.contains($0.subject) }
            if !isCorrection && !mentionsKnown && stated.count >= 2 {
                // A new situation replaces the previous one.
                departures = []
                lastQuestion = nil
            }
            for departure in stated {
                if let index = departures.firstIndex(where: { $0.subject == departure.subject }) {
                    departures[index].time = departure.time
                } else {
                    departures.append(departure)
                }
            }
        }

        let question = detectQuestion(tokens: tokens, has: has)
        let wantsExplanation = has(["pourquoi", "explique", "explique moi", "expliquer"])
        let asksAgain = has(["et maintenant", "maintenant"])

        guard !departures.isEmpty else { return nil }

        if let question {
            lastQuestion = question
            replies.append(answer(question, explain: wantsExplanation, afterCorrection: isCorrection || asksAgain))
        } else if (asksAgain || wantsExplanation), let previous = lastQuestion {
            replies.append(answer(previous, explain: wantsExplanation, afterCorrection: true))
        } else if !stated.isEmpty {
            if isCorrection, let first = stated.first {
                replies.append("D'accord : \(first.phrase) part maintenant à \(first.time.spoken).")
            } else {
                let list = stated.map { "\($0.phrase) à \($0.time.spoken)" }.joined(separator: ", ")
                replies.append("C'est noté : \(list).")
            }
        } else {
            return nil
        }
        return replies.joined(separator: " ").capitalizedFirstLetter
    }

    private func detectQuestion(tokens: [String], has: ([String]) -> Bool) -> Question? {
        if has(["l'heure du", "l'heure de", "a quelle heure", "quelle heure part", "quand part", "part a quelle heure", "partira a quelle heure", "l'horaire du", "l'horaire de"]) {
            if let subject = mentionedSubject(tokens) {
                return .timeOf(subject)
            }
        }
        let asksWhich = has(["lequel", "laquelle", "lesquels", "qui", "quel", "quelle"])
        if asksWhich && has(["premier", "premiere", "plus tot", "d'abord", "avant", "en premier"]) {
            return .earliest
        }
        if asksWhich && has(["dernier", "derniere", "plus tard", "en dernier", "apres"]) {
            return .latest
        }
        return nil
    }

    private func mentionedSubject(_ tokens: [String]) -> String? {
        let known = Set(departures.map(\.subject))
        for token in tokens.reversed() {
            if known.contains(token) { return token }
            if token.hasPrefix("l'"), known.contains(String(token.dropFirst(2))) { return String(token.dropFirst(2)) }
            if token.hasPrefix("d'"), known.contains(String(token.dropFirst(2))) { return String(token.dropFirst(2)) }
        }
        return nil
    }

    private func answer(_ question: Question, explain: Bool, afterCorrection: Bool) -> String {
        switch question {
        case .timeOf(let subject):
            guard let departure = departures.first(where: { $0.subject == subject }) else {
                return "Je ne connais pas encore l'heure de départ de ce \(subject)."
            }
            if explain {
                return "\(departure.phrase.capitalizedFirstLetter) part à \(departure.time.spoken)."
            }
            return "\(departure.time.spoken.capitalizedFirstLetter)."
        case .earliest, .latest:
            guard departures.count >= 2 else {
                if let only = departures.first {
                    return "Je ne connais qu'un départ : \(only.phrase) à \(only.time.spoken)."
                }
                return "Je ne connais encore aucun horaire."
            }
            let sorted = departures.sorted { $0.time < $1.time }
            let chosen = question == .earliest ? sorted.first! : sorted.last!
            let others = departures.filter { $0.subject != chosen.subject }
            if others.contains(where: { $0.time == chosen.time }) {
                return "Ils partent en même temps, à \(chosen.time.spoken)."
            }
            let rank = question == .earliest ? "en premier" : "en dernier"
            let lead = afterCorrection ? "Maintenant, c'est \(chosen.phrase) qui part \(rank)" : "\(chosen.phrase.capitalizedFirstLetter) part \(rank)"
            let othersText = others.map { "\($0.phrase) à \($0.time.spoken)" }.joined(separator: " et ")
            if explain {
                let comparison = question == .earliest ? "avant" : "après"
                return "\(lead), à \(chosen.time.spoken) : c'est \(comparison) \(othersText)."
            }
            return "\(lead), à \(chosen.time.spoken)."
        }
    }

    /// Reads « <article> <nom> part à <heure> » clauses, including the elliptic second
    /// clause of « le train part à 9 h et le bus à 11 h ».
    func parseDepartures(_ tokens: [String]) -> [Departure] {
        let containsVerb = tokens.contains { Self.departureVerbs.contains($0) }
        guard containsVerb else { return [] }
        var result: [Departure] = []
        for match in JarvisFrenchTimeParser.times(in: tokens) {
            let start = match.range.lowerBound
            guard start >= 1, ["a", "vers", "des"].contains(tokens[start - 1]) else { continue }
            var subject: (noun: String, phrase: String)?
            var index = start - 2
            let lowerLimit = max(0, start - 6)
            while index >= lowerLimit {
                let token = tokens[index]
                if token.hasPrefix("l'") && token.count > 2 {
                    let noun = String(token.dropFirst(2))
                    subject = (noun, "l'\(noun)")
                    break
                }
                if Self.articles.contains(token), tokens.indices.contains(index + 1) {
                    let noun = tokens[index + 1]
                    if !Self.departureVerbs.contains(noun), noun != "a" {
                        subject = (noun, "\(token) \(noun)")
                        break
                    }
                }
                index -= 1
            }
            if let subject {
                result.append(Departure(subject: subject.noun, phrase: subject.phrase, time: match.time))
            }
        }
        return result
    }
}

extension String {
    var capitalizedFirstLetter: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}
