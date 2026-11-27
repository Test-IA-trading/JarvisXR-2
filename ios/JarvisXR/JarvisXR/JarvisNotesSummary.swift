import Foundation

/// Counts the notes Jarvis really stored over a period. The spoken total, the
/// « montre-les-moi » list and the AR card all come from the same instance.
struct JarvisNotesSummary {
    /// Notes inside the period, newest first.
    let notes: [JarvisNote]
    /// nil = all notes; 0 = today; N = the last N × 24 hours.
    let days: Int?
    let now: Date

    var count: Int { notes.count }

    static func make(from allNotes: [JarvisNote], days: Int?, now: Date = Date(), calendar: Calendar = .current) -> JarvisNotesSummary {
        let start = startDate(days: days, now: now, calendar: calendar)
        let selected = allNotes
            .filter { note in start.map { note.createdAt >= $0 } ?? true }
            .filter { $0.createdAt <= now.addingTimeInterval(60) }
            .sorted { $0.createdAt > $1.createdAt }
        return JarvisNotesSummary(notes: selected, days: days, now: now)
    }

    static func startDate(days: Int?, now: Date, calendar: Calendar = .current) -> Date? {
        guard let days else { return nil }
        if days == 0 {
            return calendar.startOfDay(for: now)
        }
        return now.addingTimeInterval(-Double(days) * 86_400)
    }

    /// « ces 7 derniers jours », « aujourd'hui », « au total »
    var periodDescription: String {
        switch days {
        case nil: return "au total"
        case 0: return "aujourd'hui"
        case 1: return "depuis hier"
        case 7: return "ces 7 derniers jours"
        case let value?: return "ces \(value) derniers jours"
        }
    }

    /// « du 18 au 25 novembre », or nil for all notes.
    func dateRangeText(calendar: Calendar = .current) -> String? {
        guard let start = Self.startDate(days: days, now: now, calendar: calendar) else { return nil }
        let locale = Locale(identifier: "fr_FR")
        let dayMonth = DateFormatter()
        dayMonth.locale = locale
        dayMonth.dateFormat = "d MMMM"
        if days == 0 {
            return "le \(dayMonth.string(from: now))"
        }
        let sameMonth = calendar.component(.month, from: start) == calendar.component(.month, from: now)
        let day = DateFormatter()
        day.locale = locale
        day.dateFormat = "d"
        let startText = sameMonth ? day.string(from: start) : dayMonth.string(from: start)
        return "du \(startText) au \(dayMonth.string(from: now))"
    }

    var spokenAnswer: String {
        switch count {
        case 0: return "Vous n'avez pris aucune note \(periodDescription)."
        case 1: return "Vous avez pris une note \(periodDescription)."
        default: return "Vous avez pris \(count) notes \(periodDescription)."
        }
    }

    var displayAnswer: String {
        let noun = count == 1 ? "note" : "notes"
        guard let range = dateRangeText() else {
            return "\(count) \(noun) au total."
        }
        return "\(count) \(noun) \(range) (\(periodDescription))."
    }

    func listText(calendar: Calendar = .current) -> String {
        guard !notes.isEmpty else { return "Aucune note \(periodDescription)." }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM, HH:mm"
        return notes.enumerated().map { index, note in
            "\(index + 1). \(formatter.string(from: note.createdAt)) — \(note.text)"
        }.joined(separator: "\n")
    }

    /// Fields carried in a response's `data` for the AR card.
    var cardData: [String: String] {
        [
            "action": "ar_summary",
            "summary_value": "\(count)",
            "summary_title": count == 1 ? "note \(periodDescription)" : "notes \(periodDescription)",
            "summary_detail": dateRangeText() ?? "toutes vos notes"
        ]
    }

    /// Reads the period asked for: « ces sept derniers jours », « cette semaine »,
    /// « aujourd'hui », « depuis hier », « ce mois-ci ». Nil means all notes.
    static func requestedDays(in normalized: String) -> Int? {
        let tokens = normalized.split(separator: " ").map(String.init)
        let padded = " \(normalized) "
        if padded.contains(" aujourd'hui ") { return 0 }
        if padded.contains(" depuis hier ") || padded.contains(" hier ") { return 1 }
        if padded.contains(" cette semaine ") || padded.contains(" la semaine ") { return 7 }
        if padded.contains(" ce mois ") || padded.contains(" ce mois ci ") || padded.contains(" le mois ") { return 30 }
        for (index, token) in tokens.enumerated() where token == "derniers" || token == "dernieres" {
            // « ces 7 derniers jours », « les sept derniers jours »
            if index >= 1, let parsed = JarvisFrenchTimeParser.number(in: tokens, at: index - 1) {
                return parsed.value
            }
            if index >= 2, let parsed = JarvisFrenchTimeParser.number(in: tokens, at: index - 2) {
                return parsed.value
            }
            if tokens.indices.contains(index + 2), let parsed = JarvisFrenchTimeParser.number(in: tokens, at: index + 1) {
                // « les derniers 7 jours »
                return parsed.value
            }
        }
        if let index = tokens.firstIndex(where: { $0 == "jours" }), index >= 1,
           let parsed = JarvisFrenchTimeParser.number(in: tokens, at: index - 1) {
            return parsed.value
        }
        return nil
    }
}

/// Content of the summary card Jarvis places on the table, built from the same
/// `JarvisNotesSummary` as the spoken total.
struct JarvisARSummaryCard: Equatable {
    let value: String
    let title: String
    let detail: String

    init(value: String, title: String, detail: String) {
        self.value = value
        self.title = title
        self.detail = detail
    }

    init?(data: [String: String]) {
        guard let value = data["summary_value"] else { return nil }
        self.init(value: value, title: data["summary_title"] ?? "notes", detail: data["summary_detail"] ?? "")
    }
}

/// Opt-in or default-on behaviour of the hands-free conversation.
enum JarvisConversationSettings {
    private static let continuousKey = "JarvisXR.continuousConversation"

    /// After a spoken reply to a spoken request, Jarvis listens again without a tap.
    static var isContinuous: Bool {
        get {
            if UserDefaults.standard.object(forKey: continuousKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: continuousKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: continuousKey) }
    }
}
