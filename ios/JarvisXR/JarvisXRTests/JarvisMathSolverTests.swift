import XCTest
@testable import JarvisXR

/// Exact calculations (arithmetic, integrals, derivatives), formulas read as words, and
/// the brain's answers about math. The same cases were replayed in a Python replica
/// before this file was written, since the Windows PC has no Swift compiler.
final class JarvisMathSolverTests: XCTestCase {
    private let nnbsp = "\u{202F}"

    private func assertAnswer(_ phrase: String, spoken: String, display: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let answer = JarvisMathSolver.answer(to: phrase) else {
            return XCTFail("No calculation found in « \(phrase) »", file: file, line: line)
        }
        XCTAssertEqual(answer.spoken, spoken, file: file, line: line)
        XCTAssertEqual(answer.display, display, file: file, line: line)
    }

    // MARK: Arithmetic

    func testArithmeticSaidInFrenchIsExact() {
        assertAnswer("Combien font 128 fois 46 ?", spoken: "128 fois 46 égale 5888.", display: "128 × 46 = 5888")
        assertAnswer("Combien font deux plus deux ?", spoken: "2 plus 2 égale 4.", display: "2 + 2 = 4")
        assertAnswer("Combien font 2 et 2 ?", spoken: "2 plus 2 égale 4.", display: "2 + 2 = 4")
        assertAnswer("Combien font 3 x 4 ?", spoken: "3 fois 4 égale 12.", display: "3 × 4 = 12")
        assertAnswer("Combien font vingt-deux moins quatre-vingt-dix-sept ?", spoken: "22 moins 97 égale moins 75.", display: "22 − 97 = −75")
        assertAnswer("Combien font 3,5 fois 4 ?", spoken: "3,5 fois 4 égale 14.", display: "3,5 × 4 = 14")
        assertAnswer("Combien font 0,1 plus 0,2 ?", spoken: "0,1 plus 0,2 égale 0,3.", display: "0,1 + 0,2 = 0,3")
        assertAnswer("Combien font 12 345 fois 3 ?", spoken: "12345 fois 3 égale 37035.", display: "12\(nnbsp)345 × 3 = 37\(nnbsp)035")
    }

    func testPercentagesPowersRootsAndFactorials() {
        assertAnswer("Calcule 15 % de 80", spoken: "15 pour cent de 80 égale 12.", display: "15 % de 80 = 12")
        assertAnswer("C'est quoi 20 pour cent de 150 ?", spoken: "20 pour cent de 150 égale 30.", display: "20 % de 150 = 30")
        assertAnswer("2 puissance 10", spoken: "2 puissance 10 égale 1024.", display: "2¹⁰ = 1024")
        assertAnswer("Racine carrée de 144", spoken: "Racine carrée de 144 égale 12.", display: "√144 = 12")
        assertAnswer("5 factorielle", spoken: "5 factorielle égale 120.", display: "5! = 120")
    }

    func testInexactResultsAndDivisionByZeroAreSaidHonestly() {
        assertAnswer("Combien font 10 divisé par 3 ?", spoken: "10 divisé par 3 égale environ 3,333.", display: "10 ÷ 3 ≈ 3,33333")
        assertAnswer(
            "Combien font 7 divisé par 0 ?",
            spoken: "La division par zéro n'est pas définie.",
            display: "7 ÷ 0 : la division par zéro n'est pas définie."
        )
    }

    // MARK: Integrals and derivatives

    func testIntegralOfXSquared() {
        assertAnswer(
            "Quelle est l'intégrale de x au carré ?",
            spoken: "Une primitive de x² est x³/3 + C, où C est une constante.",
            display: "∫ x² dx = x³/3 + C"
        )
        assertAnswer(
            "Intégrale de 0 à 1 de x au carré",
            spoken: "L'intégrale de 0 à 1 de x² vaut 1/3, soit environ 0,333.",
            display: "∫ de 0 à 1 de x² dx = [x³/3] = 1/3 ≈ 0,3333"
        )
        assertAnswer(
            "Calcule l'intégrale de x au carré entre 0 et 3",
            spoken: "L'intégrale de 0 à 3 de x² vaut 9.",
            display: "∫ de 0 à 3 de x² dx = [x³/3] = 9"
        )
    }

    func testPolynomialsTypedOrSaid() {
        assertAnswer(
            "Quelle est la dérivée de x au cube moins 2x ?",
            spoken: "La dérivée de x³ − 2x est 3x² − 2.",
            display: "Dérivée de x³ − 2x : 3x² − 2"
        )
        assertAnswer(
            "Primitive de 3x² + 2x − 5",
            spoken: "Une primitive de 3x² + 2x − 5 est x³ + x² − 5x + C, où C est une constante.",
            display: "∫ (3x² + 2x − 5) dx = x³ + x² − 5x + C"
        )
        assertAnswer("Dérivée de la fonction f(x) = x⁴ + 3", spoken: "La dérivée de x⁴ + 3 est 4x³.", display: "Dérivée de x⁴ + 3 : 4x³")
        assertAnswer(
            "Intégrale de x sur 2",
            spoken: "Une primitive de x/2 est x²/4 + C, où C est une constante.",
            display: "∫ x/2 dx = x²/4 + C"
        )
    }

    func testSineCosineExponentialAndInverse() {
        assertAnswer("Intégrale de cos x", spoken: "Une primitive de cos x est sin x + C, où C est une constante.", display: "∫ cos x dx = sin x + C")
        assertAnswer("Dérivée de sinus de x", spoken: "La dérivée de sin x est cos x.", display: "Dérivée de sin x : cos x")
        assertAnswer("Intégrale de 1 sur x", spoken: "Une primitive de 1/x est ln|x| + C, où C est une constante.", display: "∫ 1/x dx = ln|x| + C")
        assertAnswer("Intégrale de e puissance x", spoken: "Une primitive de eˣ est eˣ + C, où C est une constante.", display: "∫ eˣ dx = eˣ + C")
        assertAnswer("Dérivée de ln x", spoken: "La dérivée de ln x est 1/x.", display: "Dérivée de ln x : 1/x")
    }

    func testDefiniteIntegralsWithPiLogarithmsAndSingularities() {
        assertAnswer("Intégrale de sin x de 0 à pi", spoken: "L'intégrale de 0 à π de sin x vaut 2.", display: "∫ de 0 à π de sin x dx = [−cos x] = 2")
        assertAnswer(
            "Intégrale de 1 à 2 de 1 sur x",
            spoken: "L'intégrale de 1 à 2 de 1/x vaut environ 0,693.",
            display: "∫ de 1 à 2 de 1/x dx = [ln|x|] ≈ 0,6931"
        )
        assertAnswer(
            "Intégrale de moins 1 à 1 de 1 sur x",
            spoken: "L'intégrale de −1 à 1 de 1/x n'est pas définie : la fonction n'existe pas en 0, qui est dans l'intervalle.",
            display: "∫ de −1 à 1 de 1/x dx : non définie, la fonction n'existe pas en 0."
        )
    }

    func testEverythingElseIsLeftToTheBrainOrToOtherCommands() {
        for phrase in [
            "Qu'est-ce qu'une intégrale ?",
            "Explique-moi les dérivées",
            "Une intégrale par parties, comment ça marche ?",
            "Intégrale de x fois e puissance x",
            "Pourquoi le ciel est-il bleu ?",
            "Le train part à 9 h et le bus à 11 h",
            "Mets un minuteur de 10 minutes",
            "Rappelle-moi d'appeler maman demain à 18 h",
            "Quelle heure est-il ?",
            "Combien de notes ai-je prises ces sept derniers jours ?",
            "J'ai 3 chats et 2 chiens",
            "Mets la luminosité à 50 pour cent",
            "calculate 2 + 2",
        ] {
            XCTAssertNil(JarvisMathSolver.answer(to: phrase), phrase)
        }
    }

    func testTheRouterAnswersCalculationsBeforeTheBrain() {
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: UserDefaults(suiteName: "JarvisMathSolverTests.\(UUID().uuidString)")!), scene: JarvisSpatialSceneMemory(), context: JarvisConversationContext())
        guard case .answer(let response) = router.route("Jarvis, quelle est l'intégrale de x au carré ?") else {
            return XCTFail("A calculation must be answered exactly, not by the language model")
        }
        XCTAssertEqual(response.displayResponse, "∫ x² dx = x³/3 + C")
        guard case .openQuestion = router.route("Pourquoi les intégrales sont-elles utiles ?") else {
            return XCTFail("A question about math, not a calculation, still goes to the local brain")
        }
    }

    // MARK: Formulas read aloud

    func testFormulasAreReadAsFrenchWords() {
        XCTAssertEqual(JarvisSpokenMath.speakable("x³/3 + C"), "x au cube sur 3 plus C")
        XCTAssertEqual(JarvisSpokenMath.speakable("La dérivée de x³ − 2x est 3x² − 2."), "La dérivée de x au cube moins 2 x est 3 x au carré moins 2.")
        XCTAssertEqual(JarvisSpokenMath.speakable("La dérivée de cos x est −sin x."), "La dérivée de cosinus de x est moins sinus de x.")
        XCTAssertEqual(JarvisSpokenMath.speakable("√2 ≈ 1,414"), "racine carrée de 2 égale environ 1,414")
        XCTAssertEqual(JarvisSpokenMath.speakable("ln|x| + C"), "logarithme népérien de valeur absolue de x plus C")
        XCTAssertEqual(JarvisSpokenMath.speakable("1/(2x²)"), "1 sur (2 x au carré)")
        XCTAssertEqual(JarvisSpokenMath.speakable("eˣ"), "e puissance x")
        XCTAssertEqual(JarvisSpokenMath.speakable("∫ x² dx = x³/3 + C"), "intégrale de x au carré d x égale x au cube sur 3 plus C")
        XCTAssertEqual(JarvisSpokenMath.speakable("x² - 1"), "x au carré moins 1")
        XCTAssertEqual(JarvisSpokenMath.speakable("Il fait 3.5 degrés."), "Il fait 3,5 degrés.")
        XCTAssertEqual(
            JarvisSpokenMath.speakable("L'intégrale de 0 à 1 de x² vaut 1/3, soit environ 0,333."),
            "L'intégrale de 0 à 1 de x au carré vaut 1 sur 3, soit environ 0,333."
        )
    }

    func testOrdinarySentencesAreNotTouched() {
        for sentence in [
            "La vitesse est de 90 km/h sur le Wi-Fi.",
            "Rendez-vous le 25/11/2026 à 9 h 30.",
            "Le ciel - pendant la journée - est bleu.",
            "Bonjour, je suis Jarvis. Voici ma voix.",
            "Dernière réponse : 12 mots-jetons/s.",
        ] {
            XCTAssertEqual(JarvisSpokenMath.speakable(sentence), sentence)
        }
    }

    func testLatexFromTheBrainBecomesPlainNotation() {
        XCTAssertEqual(JarvisSpokenMath.plainMath("La primitive est $\\frac{x^3}{3} + C$."), "La primitive est x³/3 + C.")
        XCTAssertEqual(JarvisSpokenMath.plainMath("On obtient \\sqrt{2} \\approx 1.414"), "On obtient √2 ≈ 1.414")
        XCTAssertEqual(JarvisSpokenMath.plainMath("x^2 + 1"), "x² + 1")
        XCTAssertEqual(JarvisAnswerCleaner.clean("\\int x^2 \\, dx = \\frac{x^3}{3} + C"), "∫ x² dx = x³/3 + C")
        XCTAssertEqual(JarvisSpokenMath.plainMath("Il fait 3.5 degrés."), "Il fait 3.5 degrés.")
    }

    // MARK: The brain and follow-up questions

    func testThePromptAsksForMathAnswersWithoutLatex() {
        let system = JarvisChatPrompt.systemPrompt(now: Date(), context: [])
        XCTAssertTrue(system.contains("intégrales"))
        XCTAssertTrue(system.contains("sans LaTeX"))
        XCTAssertTrue(system.contains("hors ligne"))
        XCTAssertTrue(system.contains("en français"))
    }

    func testAWhyQuestionAfterTheTrainExchangeReachesTheBrain() {
        let context = JarvisConversationContext()
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: UserDefaults(suiteName: "JarvisMathSolverTests.\(UUID().uuidString)")!), scene: JarvisSpatialSceneMemory(), context: context)
        guard case .answer = router.route("Le train part à 9 h et le bus à 11 h. Lequel part en premier ?") else {
            return XCTFail("The departures are answered natively")
        }
        // Before, any « pourquoi » after this exchange was answered with the timetable.
        guard case .openQuestion = router.route("Pourquoi le ciel est-il bleu ?") else {
            return XCTFail("« Pourquoi le ciel est-il bleu ? » must reach the local brain")
        }
        guard case .answer(let explained) = router.route("Pourquoi ?") else {
            return XCTFail("A bare « Pourquoi ? » still explains the departures")
        }
        XCTAssertTrue(explained.spokenResponse.contains("train"), explained.spokenResponse)
    }
}
