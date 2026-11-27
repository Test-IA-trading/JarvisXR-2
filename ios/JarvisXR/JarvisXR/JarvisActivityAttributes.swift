import ActivityKit
import AppIntents
import Foundation

/// What the Dynamic Island and the lock screen show while Jarvis keeps watch in the
/// background (Réglages › Veille en arrière-plan). Shared by the app, which starts and
/// updates the activity, and the JarvisXRWidgets extension, which draws it.
struct JarvisActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            /// Waiting for two claps.
            case watching
            /// « Oui ? »: listening to the request.
            case listening
            /// The answer is being prepared.
            case thinking
            /// The answer, said aloud and shown here.
            case answering
            /// Something needs the screen (a call to confirm): a tap on the island opens Jarvis.
            case needsScreen
        }

        var phase: Phase
        /// One line: « En veille », « Je vous écoute », or the request.
        var title: String
        /// The answer or what to do, a few lines at most.
        var detail: String

        /// SF Symbol of the phase.
        var symbol: String {
            switch phase {
            case .watching: return "hands.clap"
            case .listening: return "waveform"
            case .thinking: return "ellipsis"
            case .answering: return "text.bubble"
            case .needsScreen: return "hand.tap"
            }
        }

        /// The few letters shown next to the camera.
        var short: String {
            switch phase {
            case .watching: return "Veille"
            case .listening: return "Oui ?"
            case .thinking: return "…"
            case .answering: return "Jarvis"
            case .needsScreen: return "Touchez"
            }
        }

        static let watching = ContentState(phase: .watching, title: "En veille", detail: "Tapez deux fois dans vos mains pour appeler Jarvis.")
    }

    var name = "JARVIS"
}

/// « Arrêter la veille » on the Dynamic Island and the lock screen: the background watch
/// is turned off (Réglages › Veille en arrière-plan), the microphone closes and the island
/// goes away. iOS may run this in the widget extension instead of the app: a Darwin
/// notification reaches the app's process either way (JarvisVoiceInputService), which
/// ends the activity.
struct StopBackgroundWatchIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Arrêter la veille de Jarvis"
    static var isDiscoverable = false

    /// Inside the app's process.
    static let notification = Notification.Name("JarvisXR.stopBackgroundWatch")
    /// Between processes (extension to app).
    static let darwinName = "com.amrik.jarvisxr.stopBackgroundWatch"

    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(Self.darwinName as CFString), nil, nil, true)
        await MainActor.run {
            NotificationCenter.default.post(name: Self.notification, object: nil)
        }
        return .result()
    }
}
