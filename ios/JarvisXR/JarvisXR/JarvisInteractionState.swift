import Foundation

enum JarvisInteractionState: String {
    case standby = "Standby"
    case ready = "Ready"
    case listening = "Listening"
    case heardYou = "Heard you"
    case processing = "Processing"
    case speaking = "Speaking"
    case done = "Done"
    case inspection = "Inspection"
    case quiet = "Quiet"
    case attention = "Attention"

    /// French label shown on the home screen and read by VoiceOver. `rawValue` stays the
    /// stable technical identifier.
    var displayName: String {
        switch self {
        case .standby: return "En veille"
        case .ready: return "Prêt"
        case .listening: return "À l'écoute"
        case .heardYou: return "Compris"
        case .processing: return "Traitement"
        case .speaking: return "Réponse"
        case .done: return "Terminé"
        case .inspection: return "Inspection"
        case .quiet: return "Silencieux"
        case .attention: return "Attention"
        }
    }
}

/// Progress of one voice turn, shown as "Micro · Son · Texte · Réponse".
enum JarvisVoiceStage: Int {
    case idle = 0
    case micro
    case sound
    case text
    case reply
}

enum JarvisIntent: String {
    case ready
    case visionInspection
    case readText
    case barcodeScan
    case objectDetection
    case deviceStatus
    case memory
    case controlMesh
    case settings
    case voice
    case unsupported
}

struct JarvisAssistantDecision {
    let intent: JarvisIntent
    let plan: JarvisCommandPlan?
    let response: JarvisResponse
}

final class JarvisAssistantCore {
    private let router: JarvisCommandRouter
    private let planner: JarvisCommandPlanner
    private let french: JarvisFrenchCommandRouter
    private let conversation: JarvisConversationContext

    init(
        router: JarvisCommandRouter = JarvisCommandRouter(),
        planner: JarvisCommandPlanner = JarvisCommandPlanner(),
        french: JarvisFrenchCommandRouter = JarvisFrenchCommandRouter(),
        conversation: JarvisConversationContext = .shared
    ) {
        self.router = router
        self.planner = planner
        self.french = french
        self.conversation = conversation
    }

    func decide(_ rawCommand: String) -> JarvisAssistantDecision {
        let decision = decideWithoutMemory(rawCommand)
        // Every answered exchange becomes context for the local brain. Open questions
        // are recorded by the brain itself once it has answered.
        if decision.response.data["action"] != "local_brain", decision.response.status == .ok {
            conversation.recordTurn(user: rawCommand, assistant: decision.response.spokenResponse)
        }
        return decision
    }

    private func decideWithoutMemory(_ rawCommand: String) -> JarvisAssistantDecision {
        switch french.route(rawCommand) {
        case .answer(let response):
            let normalized = JarvisFrenchCommandRouter.normalize(rawCommand)
            return JarvisAssistantDecision(intent: classify(normalized, response: response), plan: nil, response: response)
        case .forward(let command, let spoken, let display):
            let decision = decideCanonical(command)
            let base = decision.response
            let response = JarvisResponse(
                status: base.status,
                spokenResponse: base.status == .ok ? spoken : base.spokenResponse,
                displayResponse: display ?? base.displayResponse,
                data: base.data,
                shouldSpeak: base.shouldSpeak
            )
            return JarvisAssistantDecision(intent: decision.intent, plan: decision.plan, response: response)
        case .openQuestion(let question):
            // Screens that know the local brain replace this placeholder with its answer;
            // the text below is what is said when the brain is not available.
            let response = JarvisResponse(
                status: .ok,
                spokenResponse: "Je n'ai pas encore de réponse locale à cette demande.",
                displayResponse: "J'ai compris : « \(question) ». Je n'ai pas encore de réponse locale à cette demande.",
                data: ["action": "local_brain", "question": question]
            )
            return JarvisAssistantDecision(intent: .unsupported, plan: nil, response: response)
        case .notHandled:
            return decideCanonical(rawCommand)
        }
    }

    private func decideCanonical(_ rawCommand: String) -> JarvisAssistantDecision {
        let plan = planner.plan(rawCommand)
        let normalized = plan.normalizedCommand
        if normalized == "jarvis ready" || normalized == "ready" {
            return JarvisAssistantDecision(
                intent: .ready,
                plan: plan,
                response: .ok("JARVIS ready.", display: "JARVIS ready.", data: ["mode": "ready"])
            )
        }
        let response = router.route(JarvisCommand(rawCommand))
        return JarvisAssistantDecision(intent: classify(normalized, response: response), plan: plan, response: response)
    }

    func normalize(_ command: String) -> String {
        var value = command
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "what's", with: "what is")
            .replacingOccurrences(of: "whats", with: "what is")
        value = value
            .components(separatedBy: CharacterSet(charactersIn: ",.?;!\""))
            .joined(separator: " ")
        for prefix in ["hey jarvis ", "okay jarvis ", "ok jarvis ", "jarvis "] {
            if value.hasPrefix(prefix) {
                value = String(value.dropFirst(prefix.count))
                break
            }
        }
        return value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func classify(_ command: String, response: JarvisResponse) -> JarvisIntent {
        if response.data["action"] == "inspect" || response.data["action"] == "open_camera" {
            if response.data["vision"] == "ocr" {
                return .readText
            }
            if response.data["vision"] == "visual_classification" {
                return .objectDetection
            }
            return .visionInspection
        }
        if response.data["action"] == "control_mesh" || response.data["url_scheme"] != nil {
            return .controlMesh
        }
        if response.data["action"] == "settings" {
            return .settings
        }
        if command.contains("battery") || command.contains("status") || command.contains("diagnostics") {
            return .deviceStatus
        }
        if command.contains("note") || command.contains("remember") || command.contains("memory") {
            return .memory
        }
        if command.contains("voice") || command.contains("speaking") || command.contains("quiet") {
            return .voice
        }
        return response.status == .ok ? .deviceStatus : .unsupported
    }
}
