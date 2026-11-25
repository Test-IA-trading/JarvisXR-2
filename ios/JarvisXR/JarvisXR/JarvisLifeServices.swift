import EventKit
import Foundation
import UIKit
import UserNotifications

/// Schedules timer notifications and announces timers that end while JARVIS is open.
final class JarvisTimerCenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = JarvisTimerCenter()
    private let store: JarvisTimerStore
    private static let categoryPrefix = "jarvis.timer."

    init(store: JarvisTimerStore = .shared) {
        self.store = store
        super.init()
    }

    /// Asks for notification permission if needed, then schedules the timer.
    /// `completion` receives nil on success or a French explanation.
    func schedule(_ timer: JarvisTimer, completion: @escaping (String?) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else {
                DispatchQueue.main.async {
                    completion("Le minuteur tourne, mais iOS bloque les notifications de JARVIS : je ne pourrai vous prévenir que si l'app est ouverte. Autorisez-les dans Réglages › JarvisXR › Notifications.")
                }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Minuteur terminé"
            content.body = timer.name == "minuteur" ? "Votre minuteur est terminé." : "Le minuteur « \(timer.name) » est terminé."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.remaining(at: Date())), repeats: false)
            let request = UNNotificationRequest(identifier: Self.categoryPrefix + timer.id.uuidString, content: content, trigger: trigger)
            center.add(request) { error in
                DispatchQueue.main.async {
                    completion(error == nil ? nil : "Le minuteur tourne, mais sa notification n'a pas pu être programmée.")
                }
            }
        }
    }

    func cancel(_ timers: [JarvisTimer]) {
        let identifiers = timers.map { Self.categoryPrefix + $0.id.uuidString }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    // A timer ending while JARVIS is in the foreground: show it and say it.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let identifier = notification.request.identifier
        completionHandler([.banner, .sound, .list])
        guard identifier.hasPrefix(Self.categoryPrefix) else { return }
        let body = notification.request.content.body
        let idText = String(identifier.dropFirst(Self.categoryPrefix.count))
        DispatchQueue.main.async { [weak self] in
            if let id = UUID(uuidString: idText) { self?.store.remove(id: id) }
            if JarvisSpeechService.shared.isEnabled && !JarvisVoiceInputService.shared.isListening {
                JarvisSpeechService.shared.speak(body)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        if identifier.hasPrefix(Self.categoryPrefix), let id = UUID(uuidString: String(identifier.dropFirst(Self.categoryPrefix.count))) {
            DispatchQueue.main.async { [weak self] in self?.store.remove(id: id) }
        }
        completionHandler()
    }
}

/// Reminders and calendar through EventKit, after the user's permission. The data stays
/// on the iPhone; JARVIS reads only the day asked for and writes only what was dictated.
final class JarvisCalendarBridge {
    static let shared = JarvisCalendarBridge()
    private let store = EKEventStore()

    struct Appointment: Equatable {
        let start: Date
        let title: String
        let isAllDay: Bool
    }

    func createReminder(title: String, dueDate: Date?, completion: @escaping (Result<Void, JarvisLifeError>) -> Void) {
        store.requestFullAccessToReminders { [weak self] granted, _ in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.remindersDenied)) }
                return
            }
            let reminder = EKReminder(eventStore: self.store)
            reminder.title = title
            guard let calendar = self.store.defaultCalendarForNewReminders() else {
                DispatchQueue.main.async { completion(.failure(.noReminderList)) }
                return
            }
            reminder.calendar = calendar
            if let dueDate {
                reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                reminder.addAlarm(EKAlarm(absoluteDate: dueDate))
            }
            do {
                try self.store.save(reminder, commit: true)
                DispatchQueue.main.async { completion(.success(())) }
            } catch {
                DispatchQueue.main.async { completion(.failure(.saveFailed)) }
            }
        }
    }

    func appointments(onDayOffset offset: Int, now: Date = Date(), completion: @escaping (Result<[Appointment], JarvisLifeError>) -> Void) {
        store.requestFullAccessToEvents { [weak self] granted, _ in
            guard let self else { return }
            guard granted else {
                DispatchQueue.main.async { completion(.failure(.calendarDenied)) }
                return
            }
            let calendar = Calendar.current
            let start = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) ?? now
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let predicate = self.store.predicateForEvents(withStart: start, end: end, calendars: nil)
            let events = self.store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .map { Appointment(start: $0.startDate, title: $0.title ?? "Sans titre", isAllDay: $0.isAllDay) }
            DispatchQueue.main.async { completion(.success(events)) }
        }
    }
}

enum JarvisLifeError: Error, Equatable {
    case remindersDenied
    case calendarDenied
    case noReminderList
    case saveFailed

    var message: String {
        switch self {
        case .remindersDenied: return "Je n'ai pas accès à vos rappels. Autorisez-les dans Réglages › JarvisXR › Rappels."
        case .calendarDenied: return "Je n'ai pas accès à votre calendrier. Autorisez-le dans Réglages › JarvisXR › Calendriers."
        case .noReminderList: return "Aucune liste de rappels n'est configurée sur cet iPhone."
        case .saveFailed: return "Le rappel n'a pas pu être enregistré."
        }
    }
}

/// Describes a day's appointments in French, for speech.
enum JarvisAgendaSummary {
    static func spoken(_ appointments: [JarvisCalendarBridge.Appointment], dayLabel: String, calendar: Calendar = .current) -> String {
        guard !appointments.isEmpty else {
            return "Rien n'est prévu \(dayLabel) dans votre calendrier."
        }
        let parts = appointments.prefix(6).map { appointment -> String in
            if appointment.isAllDay { return "\(appointment.title), toute la journée" }
            let time = JarvisClockTime(hour: calendar.component(.hour, from: appointment.start), minute: calendar.component(.minute, from: appointment.start))
            return "\(time?.spoken ?? ""), \(appointment.title)"
        }
        let count = appointments.count == 1 ? "un rendez-vous" : "\(appointments.count) rendez-vous"
        var text = "\(dayLabel.prefix(1).uppercased() + dayLabel.dropFirst()), vous avez \(count) : \(parts.joined(separator: " ; "))."
        if appointments.count > 6 { text += " Et d'autres encore." }
        return text
    }
}

/// Runs the side effects of life requests decided by the French router, then gives the
/// response to show and speak. Shared by every screen that takes voice.
enum JarvisLifeActionPerformer {
    static let actions: Set<String> = [
        "timer_start", "timer_cancel", "reminder_create", "agenda_read", "briefing", "pc_command", "pc_say",
        "web_weather", "web_news", "where_am_i",
        "phone_call", "phone_message", "phone_number", "steps", "photos_count", "photos_show",
    ]

    static func handles(_ response: JarvisResponse) -> Bool {
        guard let action = response.data["action"] else { return false }
        return actions.contains(action)
    }

    /// The final response to show and speak, without the action that produced it.
    static func withoutAction(_ response: JarvisResponse) -> JarvisResponse {
        JarvisResponse(status: response.status, spokenResponse: response.spokenResponse, displayResponse: response.displayResponse, shouldSpeak: response.shouldSpeak)
    }

    private static func internetUnavailable(_ failure: JarvisInternetFailure) -> JarvisResponse {
        JarvisResponse(status: .unavailable, spokenResponse: failure.message, displayResponse: failure.message)
    }

    static func perform(_ response: JarvisResponse, now: Date = Date(), completion: @escaping (JarvisResponse) -> Void) {
        let data = response.data
        switch data["action"] {
        case "phone_call", "phone_message", "phone_number", "steps", "photos_count", "photos_show":
            JarvisDeviceActions.perform(data, now: now, completion: completion)
        case "web_weather":
            let dayOffset = Int(data["day_offset"] ?? "0") ?? 0
            JarvisInternetClient.shared.weather(city: data["city"], dayOffset: dayOffset) { result in
                switch result {
                case .success(let text):
                    completion(.ok(text, display: "\(text)\nSource : Open-Meteo"))
                case .failure(.unknownCity(let unknown)):
                    // « … pour le match » names no city: the weather of here, said so.
                    JarvisInternetClient.shared.weather(city: nil, dayOffset: dayOffset) { here in
                        guard case .success(let text) = here else {
                            completion(Self.internetUnavailable(.unknownCity(unknown)))
                            return
                        }
                        completion(.ok("Je ne trouve pas la ville « \(unknown) ». \(text)", display: "\(text)\nSource : Open-Meteo"))
                    }
                case .failure(let failure):
                    completion(Self.internetUnavailable(failure))
                }
            }
        case "web_news":
            JarvisInternetClient.shared.news { result in
                switch result {
                case .success(let titles):
                    let answer = JarvisNewsFeedParser.answer(titles)
                    completion(.ok(answer.spoken, display: answer.display))
                case .failure(let failure):
                    completion(Self.internetUnavailable(failure))
                }
            }
        case "where_am_i":
            JarvisInternetClient.shared.whereAmI { result in
                switch result {
                case .success(let answer):
                    completion(.ok(answer.spoken, display: answer.display))
                case .failure(let failure):
                    completion(Self.internetUnavailable(failure))
                }
            }
        case "pc_command":
            JarvisPCLink.shared.command(data["text"] ?? "") { result in
                switch result {
                case .success(let answer):
                    completion(.ok(answer.spoken, display: "PC : \(answer.display)"))
                case .failure(let error):
                    completion(JarvisResponse(status: .unavailable, spokenResponse: error.message, displayResponse: error.message))
                }
            }
        case "pc_say":
            JarvisPCLink.shared.say(data["text"] ?? "") { result in
                switch result {
                case .success:
                    completion(.ok("C'est dit sur le PC.", display: response.displayResponse))
                case .failure(let error):
                    completion(JarvisResponse(status: .unavailable, spokenResponse: error.message, displayResponse: error.message))
                }
            }
        case "timer_start":
            guard let idText = data["timer_id"], let id = UUID(uuidString: idText),
                  let timer = JarvisTimerStore.shared.active(at: now).first(where: { $0.id == id }) else {
                completion(response)
                return
            }
            JarvisTimerCenter.shared.schedule(timer) { problem in
                guard let problem else {
                    completion(response)
                    return
                }
                completion(.ok("\(response.spokenResponse) \(problem)", display: "\(response.displayResponse) \(problem)"))
            }
        case "timer_cancel":
            let ids = Set((data["timer_ids"] ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) })
            let removed = JarvisTimerStore.shared.all().filter { ids.contains($0.id) }
            JarvisTimerCenter.shared.cancel(removed)
            if removed.isEmpty {
                // Already removed by the router: cancel the notifications by identifier.
                let placeholders = ids.map { JarvisTimer(id: $0, name: "", fireDate: now, duration: 0) }
                JarvisTimerCenter.shared.cancel(placeholders)
            }
            completion(response)
        case "reminder_create":
            let title = data["reminder_title"] ?? ""
            let due = data["reminder_due"].flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
            JarvisCalendarBridge.shared.createReminder(title: title, dueDate: due) { result in
                switch result {
                case .success:
                    let when = data["reminder_spoken_due"].map { " \($0)" } ?? ""
                    completion(.ok("C'est noté, je vous le rappellerai\(when) : \(title.lowercased()).", display: "Rappel créé dans l'app Rappels : « \(title) »\(when)."))
                case .failure(let error):
                    completion(JarvisResponse(status: .unavailable, spokenResponse: error.message, displayResponse: error.message))
                }
            }
        case "agenda_read":
            let offset = Int(data["day_offset"] ?? "0") ?? 0
            let label = data["day_label"] ?? "aujourd'hui"
            JarvisCalendarBridge.shared.appointments(onDayOffset: offset, now: now) { result in
                switch result {
                case .success(let appointments):
                    let text = JarvisAgendaSummary.spoken(appointments, dayLabel: label)
                    completion(.ok(text))
                case .failure(let error):
                    completion(JarvisResponse(status: .unavailable, spokenResponse: error.message, displayResponse: error.message))
                }
            }
        case "briefing":
            JarvisCalendarBridge.shared.appointments(onDayOffset: 0, now: now) { result in
                var parts = [response.spokenResponse]
                switch result {
                case .success(let appointments):
                    parts.append(JarvisAgendaSummary.spoken(appointments, dayLabel: "aujourd'hui"))
                case .failure:
                    parts.append("Je n'ai pas accès à votre calendrier.")
                }
                let timers = JarvisTimerStore.shared.active(at: now)
                if !timers.isEmpty {
                    let list = timers.map { "\($0.name) dans \(JarvisFrenchDurationParser.spoken($0.remaining(at: now)))" }.joined(separator: ", ")
                    parts.append("Minuteurs en cours : \(list).")
                }
                let battery = UIDevice.current.batteryLevel
                if battery >= 0 {
                    parts.append("Batterie à \(Int((battery * 100).rounded())) %.")
                }
                guard JarvisInternetSettings.isEnabled else {
                    completion(.ok(parts.joined(separator: " ")))
                    return
                }
                // Connected mode: the day's weather and the first titles.
                JarvisInternetClient.shared.weather(city: nil, dayOffset: 0) { weather in
                    if case .success(let text) = weather { parts.append(text) }
                    JarvisInternetClient.shared.news(limit: 3) { news in
                        if case .success(let titles) = news {
                            parts.append("À la une : " + titles.joined(separator: " ; ") + ".")
                        }
                        completion(.ok(parts.joined(separator: " ")))
                    }
                }
            }
        default:
            completion(response)
        }
    }
}
