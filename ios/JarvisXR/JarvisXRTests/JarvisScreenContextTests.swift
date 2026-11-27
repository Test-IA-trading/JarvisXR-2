import UIKit
import XCTest
@testable import JarvisXR

/// Lot 4 — scenario 6: « À quoi sert cette option ? », « Et celle-ci ? », suspension.
final class JarvisScreenContextTests: XCTestCase {
    private func makeRouter(screen: JarvisScreenContext) -> JarvisFrenchCommandRouter {
        let defaults = UserDefaults(suiteName: "JarvisScreenContextTests.\(UUID().uuidString)")!
        return JarvisFrenchCommandRouter(
            memory: JarvisMemoryStore(defaults: defaults),
            scene: JarvisSpatialSceneMemory(),
            context: JarvisConversationContext(),
            screen: screen
        )
    }

    private func spoken(_ router: JarvisFrenchCommandRouter, _ phrase: String) -> String {
        guard case .answer(let response) = router.route(phrase) else {
            XCTFail("Expected a native answer for « \(phrase) »")
            return ""
        }
        return response.spokenResponse
    }

    func testSelectedOptionIsExplainedAndFollowUpUsesTheNewSelection() {
        let screen = JarvisScreenContext()
        let router = makeRouter(screen: screen)
        XCTAssertTrue(spoken(router, "À quoi sert cette option ?").contains("Touchez d'abord une option"))

        screen.select(.init(title: "Sortie vocale", explanation: "Énonce les résultats de JARVIS et Vision.", screen: "Réglages"))
        XCTAssertEqual(spoken(router, "À quoi sert cette option ?"), "« Sortie vocale » : Énonce les résultats de JARVIS et Vision.")

        screen.select(.init(title: "Haptique Vision", explanation: "Fournit les motifs de direction, cible, avertissement et achèvement.", screen: "Réglages"))
        let followUp = spoken(router, "Et celle-ci ?")
        XCTAssertTrue(followUp.hasPrefix("« Haptique Vision »"), "« Et celle-ci ? » must use the new selection: \(followUp)")
        XCTAssertEqual(screen.previousOption?.title, "Sortie vocale")
    }

    func testSuspendedAssistanceIgnoresSelectionsUntilResumed() {
        let screen = JarvisScreenContext()
        let router = makeRouter(screen: screen)
        _ = spoken(router, "Suspends l'assistance")
        XCTAssertFalse(screen.isAssistanceEnabled)
        screen.select(.init(title: "Caméra", explanation: "La caméra arrière est recommandée.", screen: "Réglages"))
        XCTAssertNil(screen.selectedOption, "No selection is recorded while assistance is suspended.")
        XCTAssertTrue(spoken(router, "Et celle-ci ?").contains("suspendue"))
        _ = spoken(router, "Reprends l'assistance")
        XCTAssertTrue(screen.isAssistanceEnabled)
    }

    func testTouchingASettingsOptionSelectsItWithItsOwnExplanation() throws {
        let shared = JarvisScreenContext.shared
        shared.setAssistanceEnabled(true)
        shared.leaveScreen()
        defer { shared.leaveScreen() }

        let controller = JarvisSettingsViewController()
        controller.loadViewIfNeeded()
        let haptics = try XCTUnwrap(findControl(identifier: "jarvis.settings.vision.haptics", in: controller.view))
        // Re-sending the current value selects the option without changing the preference.
        haptics.sendActions(for: .valueChanged)
        XCTAssertEqual(shared.selectedOption?.title, "Haptique Vision")
        XCTAssertEqual(shared.selectedOption?.explanation, "Fournit les motifs de direction, cible, avertissement et achèvement.")

        let camera = try XCTUnwrap(findControl(identifier: "jarvis.settings.vision.camera", in: controller.view))
        camera.sendActions(for: .valueChanged)
        XCTAssertEqual(shared.selectedOption?.title, "Caméra")
    }

    private func findControl(identifier: String, in root: UIView) -> UIControl? {
        if let control = root as? UIControl, control.accessibilityIdentifier == identifier {
            return control
        }
        for subview in root.subviews {
            if let found = findControl(identifier: identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}
