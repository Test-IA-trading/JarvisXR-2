import Foundation

/// What the user is looking at inside JARVIS, for « À quoi sert cette option ? » and
/// « Et celle-ci ? ». Only options the user touched in JARVIS screens are known; nothing
/// from other apps is read. Kept in memory only, and the user can suspend it.
final class JarvisScreenContext {
    static let shared = JarvisScreenContext()

    struct Option: Equatable {
        let title: String
        let explanation: String
        /// « Réglages », « Réglages Vision »…
        let screen: String
    }

    private(set) var selectedOption: Option?
    private(set) var previousOption: Option?
    /// « Suspends l'assistance » stops recording selections and answering about them.
    private(set) var isAssistanceEnabled = true

    func select(_ option: Option) {
        guard isAssistanceEnabled else { return }
        if option != selectedOption {
            previousOption = selectedOption
            selectedOption = option
        }
    }

    func leaveScreen() {
        selectedOption = nil
        previousOption = nil
    }

    func setAssistanceEnabled(_ enabled: Bool) {
        isAssistanceEnabled = enabled
        if !enabled { leaveScreen() }
    }

    func answerAboutSelection() -> String {
        guard isAssistanceEnabled else {
            return "L'assistance contextuelle est suspendue. Dites « reprends l'assistance » pour la réactiver."
        }
        guard let option = selectedOption else {
            return "Touchez d'abord une option dans les Réglages, puis demandez-moi à quoi elle sert."
        }
        let explanation = option.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !explanation.isEmpty else {
            return "« \(option.title) » : je n'ai pas encore d'explication pour cette option."
        }
        return "« \(option.title) » : \(explanation)"
    }
}
