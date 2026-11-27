import XCTest
@testable import JarvisXR

/// Réveil par la voix: what is a request to Jarvis in a transcript, and the defaults that
/// keep the microphone closed unless the user turns the option on.
final class JarvisWakeWordTests: XCTestCase {
    func testTheRequestAfterJarvisIsKept() {
        XCTAssertEqual(JarvisWakeWord.command(in: "Jarvis, quelle heure est-il ?"), "quelle heure est-il")
        XCTAssertEqual(JarvisWakeWord.command(in: "Hey Jarvis mets un minuteur de 5 minutes"), "mets un minuteur de 5 minutes")
        XCTAssertEqual(JarvisWakeWord.command(in: "JARVIS. Ouvre la caméra."), "Ouvre la caméra")
        XCTAssertEqual(JarvisWakeWord.command(in: "Bonjour Jarvis, bonjour Jarvis, combien font 2 plus 2"), "combien font 2 plus 2", "The last call counts")
    }

    func testARequestBeforeJarvisIsKeptToo() {
        XCTAssertEqual(JarvisWakeWord.command(in: "Quelle heure est-il, Jarvis ?"), "Quelle heure est-il")
    }

    func testCallingJarvisAloneAsksForTheRequest() {
        XCTAssertEqual(JarvisWakeWord.command(in: "Jarvis ?"), "")
        XCTAssertEqual(JarvisWakeWord.command(in: "Hey Jarvis"), "")
        XCTAssertEqual(JarvisWakeWord.command(in: "Dis Jarvis."), "")
    }

    func testWhatTheRecognizerMayWriteForJarvis() {
        XCTAssertEqual(JarvisWakeWord.command(in: "Dijarvis, mets un minuteur de 10 minutes"), "mets un minuteur de 10 minutes", "« Dis Jarvis » run together")
        XCTAssertEqual(JarvisWakeWord.command(in: "Jarvos, quelle heure est-il ?"), "quelle heure est-il", "One letter off")
        XCTAssertNil(JarvisWakeWord.command(in: "Rendez-vous sur le parvis de la gare"), "« parvis » is a word")
        XCTAssertNil(JarvisWakeWord.command(in: "J'invite mes amis demain soir"))
        XCTAssertNil(JarvisWakeWord.command(in: "Il est ravi de venir"))
        XCTAssertEqual(JarvisWakeWord.distance("jardvis", "jarvis"), 1)
        XCTAssertEqual(JarvisWakeWord.distance("parvis", "jarvis"), 1)
        XCTAssertEqual(JarvisWakeWord.distance("", "jarvis"), 6)
    }

    func testOtherConversationsAreIgnored() {
        XCTAssertNil(JarvisWakeWord.command(in: "On regardait un film hier soir"))
        XCTAssertNil(JarvisWakeWord.command(in: "J'arrive dans cinq minutes"))
        XCTAssertNil(JarvisWakeWord.command(in: ""))
    }

    func testTheWakeWordIsOffByDefault() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: JarvisWakeWordSettings.enabledKey)
        defer {
            if let original {
                defaults.set(original, forKey: JarvisWakeWordSettings.enabledKey)
            } else {
                defaults.removeObject(forKey: JarvisWakeWordSettings.enabledKey)
            }
        }
        defaults.removeObject(forKey: JarvisWakeWordSettings.enabledKey)
        XCTAssertFalse(JarvisWakeWordSettings.isEnabled)
        JarvisWakeWordSettings.isEnabled = true
        XCTAssertTrue(JarvisWakeWordSettings.isEnabled)
    }

    func testRequestsStayInCommandModeUnlessTheScreenAsksForTheWakeWord() {
        let service = JarvisVoiceInputService()
        XCTAssertEqual(service.mode, .command)
        XCTAssertEqual(service.wakeListenDuration, 50)
        XCTAssertFalse(service.isListening)
    }
}
