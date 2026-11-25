import ActivityKit
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
