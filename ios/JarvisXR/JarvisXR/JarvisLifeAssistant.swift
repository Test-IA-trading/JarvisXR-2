import Foundation

// MARK: - Durations

/// Reads a duration said in French: « 10 minutes », « une heure et demie »,
/// « 1 h 30 », « 45 secondes », « un quart d'heure », « une demi-heure ».
enum JarvisFrenchDurationParser {
    struct Match: Equatable {
        let seconds: TimeInterval
        let range: ClosedRange<Int>
    }

    private static let hourWords: Set<String> = ["h", "heure", "heures"]
    private static let minuteWords: Set<String> = ["min", "mn", "minute", "minutes"]
    private static let secondWords: Set<String> = ["s", "sec", "seconde", "secondes"]

    static func durations(in tokens: [String]) -> [Match] {
        var matches: [Match] = []
        var index = 0
        while index < tokens.count {
            if let match = duration(in: tokens, at: index) {
                matches.append(match)
                index = match.range.upperBound + 1
            } else {
                index += 1
            }
        }
        return matches
    }

    static func firstDuration(in normalized: String) -> Match? {
        durations(in: normalized.split(separator: " ").map(String.init)).first
    }

    private static func duration(in tokens: [String], at start: Int) -> Match? {
        // « à 9 h », « vers 18 h » are clock times, not durations.
        if start > 0, ["a", "vers", "des", "jusqu'a"].contains(tokens[start - 1]) {
            return nil
        }
        // « un quart d'heure », « une demi heure »
        if tokens.indices.contains(start + 2), ["un", "une"].contains(tokens[start]) {
            if tokens[start + 1] == "quart", tokens[start + 2] == "d'heure" {
                return Match(seconds: 15 * 60, range: start...(start + 2))
            }
            if tokens[start + 1] == "demi", hourWords.contains(tokens[start + 2]) {
                return Match(seconds: 30 * 60, range: start...(start + 2))
            }
        }
        // « 1h30 » written as one token
        if let compact = compactHours(tokens[start]) {
            return Match(seconds: compact, range: start...start)
        }
        guard let first = JarvisFrenchTimeParser.number(in: tokens, at: start) else { return nil }
        var unitIndex = start + first.length
        guard tokens.indices.contains(unitIndex) else { return nil }
        var seconds: TimeInterval
        let unit = tokens[unitIndex]
        if hourWords.contains(unit) {
            seconds = TimeInterval(first.value) * 3600
        } else if minuteWords.contains(unit) {
            seconds = TimeInterval(first.value) * 60
        } else if secondWords.contains(unit) {
            seconds = TimeInterval(first.value)
        } else {
            return nil
        }
        var end = unitIndex
        // « et demie », « et quart »
        if tokens.indices.contains(end + 2), tokens[end + 1] == "et" {
            if ["demie", "demi"].contains(tokens[end + 2]) {
                seconds += hourWords.contains(unit) ? 1800 : (minuteWords.contains(unit) ? 30 : 0)
                end += 2
            } else if tokens[end + 2] == "quart", hourWords.contains(unit) {
                seconds += 900
                end += 2
            }
        }
        // « 1 heure 30 », « 2 h 15 minutes », « 10 minutes 30 »
        if let extra = JarvisFrenchTimeParser.number(in: tokens, at: end + 1) {
            unitIndex = end + 1 + extra.length
            let nextUnit = tokens.indices.contains(unitIndex) ? tokens[unitIndex] : ""
            if hourWords.contains(unit) {
                seconds += TimeInterval(extra.value) * 60
                end = minuteWords.contains(nextUnit) ? unitIndex : end + extra.length
            } else if minuteWords.contains(unit), secondWords.contains(nextUnit) {
                seconds += TimeInterval(extra.value)
                end = unitIndex
            }
        }
        guard seconds > 0 else { return nil }
        return Match(seconds: seconds, range: start...end)
    }

    private static func compactHours(_ token: String) -> TimeInterval? {
        guard let separator = token.firstIndex(of: "h") else { return nil }
        let hours = token[token.startIndex..<separator]
        let minutes = token[token.index(after: separator)...]
        guard let h = Int(hours), (0...23).contains(h), !minutes.isEmpty, minutes.count == 2, let m = Int(minutes), (0...59).contains(m) else {
            return nil
        }
        return TimeInterval(h * 3600 + m * 60)
    }

    /// « 10 minutes », « 1 heure 30 », « 45 secondes »
    static func spoken(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        func plural(_ value: Int, _ word: String) -> String { "\(value) \(word)\(value > 1 ? "s" : "")" }
        if hours > 0 {
            return minutes > 0 ? "\(plural(hours, "heure")) \(minutes)" : plural(hours, "heure")
        }
        if minutes > 0 {
            return secs > 0 && minutes < 5 ? "\(plural(minutes, "minute")) \(secs)" : plural(minutes, "minute")
        }
        return plural(secs, "seconde")
    }
}

// MARK: - Days

/// « aujourd'hui », « ce soir », « demain », « après-demain », « lundi », « lundi prochain ».
enum JarvisFrenchDayParser {
    struct Match: Equatable {
        let dayOffset: Int
        let label: String
        let range: ClosedRange<Int>
    }

    private static let weekdays = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]

    static func day(in tokens: [String], now: Date, calendar: Calendar = .current) -> Match? {
        for (index, token) in tokens.enumerated() {
            if token == "aujourd'hui" { return Match(dayOffset: 0, label: "aujourd'hui", range: index...index) }
            if token == "apres", tokens.indices.contains(index + 1), tokens[index + 1] == "demain" {
                return Match(dayOffset: 2, label: "après-demain", range: index...(index + 1))
            }
            if token == "demain" { return Match(dayOffset: 1, label: "demain", range: index...index) }
            if token == "soir", index >= 1, tokens[index - 1] == "ce" {
                return Match(dayOffset: 0, label: "ce soir", range: (index - 1)...index)
            }
            if let weekday = weekdays.firstIndex(of: token) {
                let today = calendar.component(.weekday, from: now) - 1 // 0 = dimanche
                var offset = (weekday - today + 7) % 7
                var end = index
                if tokens.indices.contains(index + 1), tokens[index + 1] == "prochain" {
                    end = index + 1
                }
                // The weekday named on that same day means next week (« aujourd'hui » covers today).
                if offset == 0 { offset = 7 }
                return Match(dayOffset: offset, label: token, range: index...end)
            }
        }
        return nil
    }
}

// MARK: - Timers

struct JarvisTimer: Codable, Equatable {
    let id: UUID
    let name: String
    let fireDate: Date
    let duration: TimeInterval

    func remaining(at now: Date) -> TimeInterval { max(0, fireDate.timeIntervalSince(now)) }
}

/// Named countdown timers, persisted so they survive a relaunch.
final class JarvisTimerStore {
    static let shared = JarvisTimerStore()
    private let defaults: UserDefaults
    private let key = "JarvisXR.timers.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [JarvisTimer] {
        guard let data = defaults.data(forKey: key),
              let timers = try? JSONDecoder().decode([JarvisTimer].self, from: data) else { return [] }
        return timers
    }

    func active(at now: Date = Date()) -> [JarvisTimer] {
        all().filter { $0.fireDate > now }.sorted { $0.fireDate < $1.fireDate }
    }

    @discardableResult
    func add(name: String, duration: TimeInterval, now: Date = Date()) -> JarvisTimer {
        let timer = JarvisTimer(id: UUID(), name: name, fireDate: now.addingTimeInterval(duration), duration: duration)
        save(active(at: now) + [timer])
        return timer
    }

    /// Removes the timers named `name` (all active timers when nil) and returns them.
    @discardableResult
    func remove(named name: String?, now: Date = Date()) -> [JarvisTimer] {
        let current = active(at: now)
        let removed = name.map { wanted in current.filter { JarvisFrenchCommandRouter.normalize($0.name) == JarvisFrenchCommandRouter.normalize(wanted) } } ?? current
        save(current.filter { timer in !removed.contains(where: { $0.id == timer.id }) })
        return removed
    }

    func remove(id: UUID) {
        save(all().filter { $0.id != id })
    }

    private func save(_ timers: [JarvisTimer]) {
        if let data = try? JSONEncoder().encode(timers) {
            defaults.set(data, forKey: key)
        }
    }
}

// MARK: - Requests

/// Everyday requests that touch the user's life: timers, reminders, agenda, briefing.
/// Parsing is pure and tested; side effects run in `JarvisLifeActionPerformer`.
enum JarvisLifeRequestParser {
    static let timerWords = ["minuteur", "timer", "compte a rebours", "chrono", "chronometre"]

    /// Removes filler words around a timer name: « pour les pâtes » → « pâtes ».
    static func timerName(fromOriginal original: String, normalizedTokens: [String], excluding ranges: [ClosedRange<Int>]) -> String {
        let originalTokens = originalWords(original)
        guard originalTokens.count == normalizedTokens.count else { return "minuteur" }
        let fillers: Set<String> = ["mets", "met", "lance", "demarre", "cree", "programme", "un", "une", "le", "la", "les", "des", "du", "de", "d'", "pour", "minuteur", "timer", "compte", "a", "rebours", "chrono", "chronometre", "jarvis", "s'il", "te", "plait", "vous", "moi", "dans", "sur", "et", "ok"]
        var words: [String] = []
        for (index, token) in normalizedTokens.enumerated() {
            if ranges.contains(where: { $0.contains(index) }) { continue }
            if fillers.contains(token) { continue }
            words.append(originalTokens[index])
        }
        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "minuteur" : name
    }

    /// Splits original text with the same separators as `JarvisFrenchCommandRouter.normalize`.
    static func originalWords(_ text: String) -> [String] {
        let prepared = text
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"(\d{1,2}):(\d{2})"#, with: "$1h$2", options: .regularExpression)
        let separators = CharacterSet(charactersIn: ",.?;:!\"«»()-–—…").union(.whitespacesAndNewlines)
        return prepared.components(separatedBy: separators).filter { !$0.isEmpty }
    }

    struct Reminder: Equatable {
        let title: String
        let dueDate: Date?
        let spokenDue: String?
    }

    /// « Rappelle-moi d'appeler maman demain à 18 h », « rappelle-moi de sortir le linge dans 20 minutes ».
    static func reminder(original: String, normalized: String, now: Date, calendar: Calendar = .current) -> Reminder? {
        let tokens = normalized.split(separator: " ").map(String.init)
        guard let start = tokens.firstIndex(of: "rappelle"), tokens.indices.contains(start + 1), ["moi", "nous"].contains(tokens[start + 1]) else { return nil }
        let bodyStart = start + 2
        guard bodyStart < tokens.count else { return Reminder(title: "", dueDate: nil, spokenDue: nil) }

        var excluded: [ClosedRange<Int>] = [0...(bodyStart - 1)]
        var due: Date?
        var spokenDue: String?

        if let inIndex = tokens[bodyStart...].firstIndex(of: "dans"),
           let duration = JarvisFrenchDurationParser.durations(in: Array(tokens[(inIndex + 1)...])).first,
           duration.range.lowerBound == 0 {
            due = now.addingTimeInterval(duration.seconds)
            spokenDue = "dans \(JarvisFrenchDurationParser.spoken(duration.seconds))"
            excluded.append(inIndex...(inIndex + 1 + duration.range.upperBound))
        } else {
            let day = JarvisFrenchDayParser.day(in: tokens, now: now, calendar: calendar)
            let time = JarvisFrenchTimeParser.times(in: tokens).first { $0.range.lowerBound >= bodyStart }
            if let day { excluded.append(day.range) }
            if let time {
                var lower = time.range.lowerBound
                if lower > bodyStart, ["a", "vers", "pour"].contains(tokens[lower - 1]) { lower -= 1 }
                excluded.append(lower...time.range.upperBound)
            }
            if day != nil || time != nil {
                let base = calendar.date(byAdding: .day, value: day?.dayOffset ?? 0, to: calendar.startOfDay(for: now)) ?? now
                let hour = time?.time.hour ?? (day?.label == "ce soir" ? 19 : 9)
                let minute = time?.time.minute ?? 0
                var candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
                if day == nil, candidate <= now {
                    candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
                }
                due = candidate
                spokenDue = spokenDate(candidate, now: now, calendar: calendar)
            }
        }

        let originalTokens = originalWords(original)
        guard originalTokens.count == tokens.count else {
            return Reminder(title: "", dueDate: due, spokenDue: spokenDue)
        }
        var words: [String] = []
        for index in bodyStart..<tokens.count where !excluded.contains(where: { $0.contains(index) }) {
            words.append(originalTokens[index])
        }
        // « de sortir le linge » → « sortir le linge » ; « d'appeler » → « appeler »
        if let first = words.first?.lowercased(), first == "de" || first == "du" {
            words.removeFirst()
        }
        if let first = words.first, first.lowercased().hasPrefix("d'") {
            words[0] = String(first.dropFirst(2))
        }
        // A dangling preposition left at the end (« appeler maman le »).
        while let last = words.last?.lowercased(), ["a", "à", "le", "la", "pour", "vers", "de", "ce"].contains(last) {
            words.removeLast()
        }
        let title = words.joined(separator: " ")
        return Reminder(title: title.prefix(1).uppercased() + title.dropFirst(), dueDate: due, spokenDue: spokenDue)
    }

    /// « demain à 18 h », « aujourd'hui à 9 h 30 », « lundi 1 décembre à 8 h »
    static func spokenDate(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        guard let time = JarvisClockTime(hour: calendar.component(.hour, from: date), minute: calendar.component(.minute, from: date)) else { return "" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return "aujourd'hui à \(time.spoken)"
        case 1: return "demain à \(time.spoken)"
        case 2: return "après-demain à \(time.spoken)"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "fr_FR")
            formatter.dateFormat = "EEEE d MMMM"
            return "\(formatter.string(from: date)) à \(time.spoken)"
        }
    }
}
