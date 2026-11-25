import AVFoundation
import XCTest
@testable import JarvisXR

/// Regression tests for the French voice path: "il ne détecte pas ma voix".
final class JarvisVoiceFrenchTests: XCTestCase {
    private var defaults: UserDefaults!
    private var memory: JarvisMemoryStore!
    private var french: JarvisFrenchCommandRouter!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "JarvisVoiceFrenchTests.\(UUID().uuidString)")
        memory = JarvisMemoryStore(defaults: defaults)
        french = JarvisFrenchCommandRouter(memory: memory)
    }

    // MARK: Recognition configuration

    func testDictationListensInFrenchWithRoomForPauses() {
        let service = JarvisVoiceInputService()
        XCTAssertEqual(service.locale.identifier, "fr-FR")
        XCTAssertGreaterThanOrEqual(service.silenceAfterSpeech, 1.5, "A short pause mid-sentence must not end the turn.")
        XCTAssertGreaterThanOrEqual(service.maximumListenDuration, 20)
        XCTAssertGreaterThan(service.noSpeechTimeout, 4, "The previous 4 s cut-off was too short for a first French turn.")
    }

    func testCancelReturnsToStandbyAndStopWhenIdleIsHarmless() {
        let service = JarvisVoiceInputService()
        var states: [JarvisVoiceInputState] = []
        service.onStateChange = { states.append($0) }
        service.stopListening(process: true)
        XCTAssertTrue(states.isEmpty, "Stopping an idle service must not emit a fake result.")
        service.cancel()
        XCTAssertEqual(states, [.standby])
        XCTAssertFalse(service.isListening)
    }

    // MARK: Errors are not silence

    func testRecognitionErrorIsNotReportedAsNoSpeech() {
        let failure = JarvisVoiceFailure.fromRecognitionError(NSError(domain: "kAFAssistantErrorDomain", code: 1101))
        XCTAssertEqual(failure?.kind, .recognitionFailed)
        XCTAssertEqual(failure?.diagnostic, "kAFAssistantErrorDomain 1101")
        XCTAssertFalse(failure?.message.isEmpty ?? true)
    }

    func testNoSpeechAndCancellationErrorsAreNotFailures() {
        XCTAssertNil(JarvisVoiceFailure.fromRecognitionError(NSError(domain: "kAFAssistantErrorDomain", code: 1110)))
        XCTAssertNil(JarvisVoiceFailure.fromRecognitionError(NSError(domain: "kAFAssistantErrorDomain", code: 216)))
        XCTAssertNil(JarvisVoiceFailure.fromRecognitionError(NSError(domain: "kLSRErrorDomain", code: 301)))
    }

    func testDisabledDictationPointsToTheRightSetting() {
        let failure = JarvisVoiceFailure.fromRecognitionError(NSError(domain: "kLSRErrorDomain", code: 201))
        XCTAssertEqual(failure?.kind, .dictationDisabled)
        XCTAssertTrue(failure?.message.contains("dictée") ?? false)
        XCTAssertTrue(failure?.offersSettings ?? false)
    }

    func testPermissionFailuresAreFrenchAndActionable() {
        let mic = JarvisVoiceFailure.make(.microphoneDenied)
        XCTAssertTrue(mic.message.contains("Micro"))
        XCTAssertTrue(mic.offersSettings)
        let speech = JarvisVoiceFailure.make(.speechDenied)
        XCTAssertTrue(speech.message.contains("Reconnaissance vocale"))
    }

    // MARK: Signal meter

    func testDigitallySilentInputIsDetected() {
        var meter = JarvisVoiceSignalMeter()
        for _ in 0..<20 { meter.ingest([Float](repeating: 0, count: 1024)) }
        XCTAssertTrue(meter.hasReceivedBuffers)
        XCTAssertTrue(meter.isDigitallySilent, "All-zero buffers mean a muted or denied microphone, not a quiet room.")
        XCTAssertFalse(meter.hasHeardSound)
    }

    func testSpeechLevelSoundIsDetected() {
        var meter = JarvisVoiceSignalMeter()
        let tone = (0..<1024).map { Float(sin(Double($0) * 0.06)) * 0.2 }
        let level = meter.ingest(tone)
        XCTAssertTrue(meter.hasHeardSound)
        XCTAssertFalse(meter.isDigitallySilent)
        XCTAssertGreaterThan(level, 0.3)
    }

    func testQuietRoomIsNeitherSoundNorDigitalSilence() {
        var meter = JarvisVoiceSignalMeter()
        let hiss = (0..<1024).map { Float(sin(Double($0) * 1.7)) * 0.0002 }
        meter.ingest(hiss)
        XCTAssertFalse(meter.hasHeardSound)
        XCTAssertFalse(meter.isDigitallySilent)
    }

    // MARK: French commands

    func testFieldTestSentenceGetsAFrenchAnswerShowingTheTranscript() {
        guard case .answer(let response) = french.route("Bonjour Jarvis, est-ce que tu m’entends ?") else {
            return XCTFail("The field-test sentence must be answered natively.")
        }
        XCTAssertEqual(response.status, .ok)
        XCTAssertTrue(response.shouldSpeak)
        XCTAssertTrue(response.spokenResponse.contains("entends"))
        XCTAssertTrue(response.displayResponse.contains("Bonjour Jarvis, est-ce que tu m’entends ?"))
    }

    func testTimeIsAnsweredInFrenchFromTheClock() {
        var components = DateComponents()
        components.year = 2026; components.month = 11; components.day = 24
        components.hour = 9; components.minute = 5
        let date = Calendar.current.date(from: components)!
        guard case .answer(let response) = french.route("Quelle heure est-il ?", now: date) else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertEqual(response.spokenResponse, "Il est 9 h 05.")
        components.hour = 17; components.minute = 42
        guard case .answer(let later) = french.route("Jarvis, il est quelle heure ?", now: Calendar.current.date(from: components)!) else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertEqual(later.spokenResponse, "Il est 17 h 42.", "The answer must follow the clock, not a demo string.")
    }

    func testNotesKeepTheUsersOwnWording() {
        guard case .answer(let saved) = french.route("Prends une note : acheter du pain complet") else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertEqual(saved.status, .ok)
        guard case .answer = french.route("Souviens-toi que la réunion est à midi") else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertEqual(memory.loadNotes().map(\.text).sorted(), ["acheter du pain complet", "la réunion est à midi"].sorted())
        guard case .answer(let list) = french.route("Montre mes notes") else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertEqual(list.spokenResponse, "Vous avez 2 notes.")
    }

    func testEmptyNotesAreReportedAsZero() {
        guard case .answer(let list) = french.route("mes notes") else {
            return XCTFail("Expected a native answer")
        }
        XCTAssertTrue(list.spokenResponse.contains("aucune note"))
    }

    func testFrenchActionsForwardToTheExistingRouter() {
        guard case .forward(let command, let spoken, _) = french.route("Ouvre la caméra") else {
            return XCTFail("Expected a forwarded action")
        }
        XCTAssertEqual(command, "open camera")
        XCTAssertEqual(spoken, "J'ouvre la caméra.")
        XCTAssertEqual(JarvisFrenchCommandRouter.translateAction("Qu'est-ce que tu vois ?")?.command, "describe this")
        XCTAssertEqual(JarvisFrenchCommandRouter.translateAction("ouvre les réglages")?.command, "open settings")
    }

    func testAssistantExecutesFrenchActionWithFrenchSpeech() {
        let decision = JarvisAssistantCore().decide("Ouvre la caméra")
        XCTAssertNotNil(decision.plan?.visionLaunchRequest, "The French phrase must open Vision like « open camera ».")
        XCTAssertEqual(decision.response.status, .ok)
        XCTAssertEqual(decision.response.spokenResponse, "J'ouvre la caméra.")
    }

    func testEnglishCommandsStillReachTheExistingRouter() {
        guard case .notHandled = french.route("help") else { return XCTFail("English command was intercepted") }
        guard case .notHandled = french.route("take over springboard") else { return XCTFail("English command was intercepted") }
        guard case .notHandled = french.route("save note first field test") else { return XCTFail("English command was intercepted") }
    }

    func testUnknownFrenchRequestGoesToTheLocalBrainWithAFrenchFallback() {
        guard case .openQuestion(let question) = french.route("Raconte-moi une histoire de pirates") else {
            return XCTFail("An open French question must reach the local brain, not the English hint")
        }
        XCTAssertEqual(question, "Raconte-moi une histoire de pirates")
        let decision = JarvisAssistantCore(conversation: JarvisConversationContext()).decide("Raconte-moi une histoire de pirates")
        XCTAssertEqual(decision.response.data["action"], "local_brain")
        XCTAssertEqual(decision.response.data["question"], "Raconte-moi une histoire de pirates")
        XCTAssertTrue(decision.response.displayResponse.contains("J'ai compris : « Raconte-moi une histoire de pirates »"))
    }

    // MARK: Spoken voice

    func testChosenVoiceIsFrenchWheneverOneIsInstalled() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let picked = JarvisSpeechService.bestVoice(from: voices)
        if voices.contains(where: { $0.language.hasPrefix("fr") }) {
            XCTAssertEqual(picked?.language.hasPrefix("fr"), true)
        } else {
            XCTAssertNil(picked, "No English voice may be chosen as a French fallback.")
        }
        XCTAssertTrue(JarvisSpeechService.shared.testPhrase().contains("française"))
    }
}
