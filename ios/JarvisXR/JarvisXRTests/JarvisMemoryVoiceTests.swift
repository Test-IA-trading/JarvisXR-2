import AVFoundation
import XCTest
@testable import JarvisXR

/// V10: Jarvis's memory copied from the PC, the PC's voice played on the iPhone, and the
/// personality shared with Jarvis PC.
final class JarvisMemoryVoiceTests: XCTestCase {
    private func freshStore() -> (JarvisKnowledgeStore, URL, UserDefaults) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Mémoire-\(UUID().uuidString)", isDirectory: true)
        let defaults = UserDefaults(suiteName: "JarvisMemoryVoiceTests")!
        defaults.removePersistentDomain(forName: "JarvisMemoryVoiceTests")
        return (JarvisKnowledgeStore(folder: folder, defaults: defaults), folder, defaults)
    }

    func testTheIPhoneLearnsByItselfInMarkdown() {
        let (store, folder, defaults) = freshStore()
        XCTAssertEqual(store.learn(said: "J'habite à Paris").map(\.text), ["L'utilisateur habite Paris."])
        store.learn(said: "J'habite à Lyon maintenant")
        XCTAssertEqual(store.notes.filter { $0.kind == "fait" }.count, 1, "a new value replaces the old one")
        XCTAssertTrue(store.notes[0].text.contains("Lyon"))
        XCTAssertEqual(store.learn(said: "Ma sœur s'appelle Julie").map(\.text), ["Sœur de l'utilisateur : Julie."])
        XCTAssertEqual(store.learn(said: "Tous les matins, je cours au parc").map(\.kind), ["habitude"])
        XCTAssertTrue(store.learn(said: "Comment s'appelle ma sœur ?").isEmpty, "a question teaches nothing")
        XCTAssertEqual(store.learn(said: "Non, c'est 1873", previousQuestion: "En quelle année l'arrêt Blanco ?").map(\.kind), ["correction"])
        XCTAssertTrue(store.contextLines(for: "Comment s'appelle ma sœur ?").contains { $0.contains("Julie") })
        XCTAssertTrue(store.contextLines(for: "Combien font deux et deux ?").isEmpty, "only what is relevant")
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        XCTAssertEqual(files.filter { $0.hasSuffix(".md") }.count, store.notes.count, "one Markdown note per memory (an Obsidian vault)")
        XCTAssertEqual(JarvisKnowledgeStore(folder: folder, defaults: defaults).notes.count, store.notes.count, "read back from the files")
    }

    func testTheMemoryTravelsBothWaysOverWiFi() {
        let (store, _, _) = freshStore()
        store.learn(said: "J'aime le café noir")
        XCTAssertNotNil(store.forget("le café"))
        XCTAssertTrue(store.syncPayload().contains { $0["deleted"] as? Bool == true }, "the deletion is sent to the PC")
        store.learn(said: "Je préfère les réponses courtes")
        XCTAssertTrue(store.syncPayload().contains { ($0["text"] as? String)?.contains("courtes") == true }, "the notes too")
        store.adopt([
            ["id": "pc1", "kind": "preference", "text": "L'utilisateur aime le jazz.", "updated": "2026-11-27T10:00:00+00:00"],
        ])
        XCTAssertTrue(store.notes.contains { $0.text.contains("jazz") })
        XCTAssertFalse(store.syncPayload().contains { $0["deleted"] as? Bool == true }, "deletions are sent once")
        store.adopt([["id": "pc1", "deleted": true]])
        XCTAssertFalse(store.notes.contains { $0.text.contains("jazz") }, "a memory forgotten on the PC goes away")
    }

    func testThePCVoiceIsReadFromItsWAV() {
        var data = Data("RIFF".utf8)
        func append32(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8 & 0xff), UInt8(value >> 16 & 0xff), UInt8(value >> 24 & 0xff)]) }
        func append16(_ value: Int) { data.append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8 & 0xff)]) }
        append32(36 + 8)
        data.append(Data("WAVEfmt ".utf8))
        append32(16); append16(1); append16(1); append32(22_050); append32(44_100); append16(2); append16(16)
        data.append(Data("data".utf8))
        append32(8)
        for sample in [0, 1000, -1000, 32767] { append16(sample & 0xffff) }
        let buffer = JarvisPCVoice.pcmBuffer(wav: data)
        XCTAssertEqual(buffer?.frameLength, 4)
        XCTAssertEqual(buffer?.format.sampleRate, 22_050)
        XCTAssertEqual(buffer?.int16ChannelData?[0][2], -1000)
        XCTAssertNil(JarvisPCVoice.pcmBuffer(wav: Data("not a wav".utf8)))
    }

    func testJarvisVoicePackageIsCheckedAndUnpacked() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Voix-\(UUID().uuidString)/v1", isDirectory: true)
        let files: [(String, Data)] = [("model.onnx", Data([1, 2, 3])), ("tokens.txt", Data("a 1".utf8)), ("espeak-ng-data/fr_dict", Data([9]))]
        var offset = 0
        var index: [[String: Any]] = []
        for (path, data) in files {
            index.append(["path": path, "offset": offset, "size": data.count])
            offset += data.count
        }
        let voice: [String: Any] = ["speaker_id": 1, "length_scale": 1.1, "pitch_semitones": 1.5, "sentence_silence": 0.3]
        let header = try JSONSerialization.data(withJSONObject: ["files": index, "voice": voice])
        var pack = Data()
        var length = UInt64(header.count).littleEndian
        pack.append(Data(bytes: &length, count: 8))
        pack.append(header)
        files.forEach { pack.append($0.1) }
        let packURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pack")
        try pack.write(to: packURL)
        let sha = try JarvisModelDownloader.sha256(of: packURL)
        let voiceEngine = JarvisLocalVoice(folder: folder)
        XCTAssertNotNil(voiceEngine.unpack(packURL, expectedSize: Int64(pack.count), expectedSHA256: String(repeating: "0", count: 64)), "a different file is refused")
        XCTAssertNil(voiceEngine.unpack(packURL, expectedSize: Int64(pack.count), expectedSHA256: sha))
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("espeak-ng-data/fr_dict")), Data([9]))
        XCTAssertTrue(JarvisLocalVoice(folder: folder).isInstalled, "found again at the next launch")
        // The pitch change keeps the pace: 1.5 semitone higher = 9 % fewer samples.
        let shifted = JarvisLocalVoice.resample([Float](repeating: 0.5, count: 1000), by: pow(2, 1.5 / 12))
        XCTAssertTrue(abs(shifted.count - 916) <= 2)
    }

    func testThePersonalityIsTheValidatedOne() {
        XCTAssertEqual(JarvisPersonality.profile, ["humour": 60, "sarcasme": 45, "formalite": 90, "initiative": 80, "longueur": 45, "adaptation": 100])
        let simple = JarvisPersonality.rules(for: "Quelle heure est-il ?")
        XCTAssertTrue(simple.contains(JarvisPersonality.lengthSimple))
        XCTAssertTrue(simple.contains(JarvisPersonality.humour))
        let serious = JarvisPersonality.rules(for: "J'ai mal à la poitrine depuis ce matin, que dois-je faire ?")
        XCTAssertTrue(serious.contains(JarvisPersonality.serious), "no irony about health")
        XCTAssertFalse(serious.contains(JarvisPersonality.humour))
        let system = JarvisChatPrompt.systemPrompt(now: Date(), context: [], question: "Bonjour")
        XCTAssertTrue(system.contains("Monsieur") && system.contains("Vouvoie") && system.contains("hors ligne"))
    }

    // MARK: Refonte §8 — a memory that really answers

    func testARepeatedQuestionIsAnsweredFromTheMemoryWithItsProvenance() {
        let (store, folder, defaults) = freshStore()
        let answer = "La photosynthèse est la fabrication de sucres par les plantes à partir de la lumière, de l'eau et du gaz carbonique."
        XCTAssertNotNil(store.keepAnswer(question: "Qu'est-ce que la photosynthèse ?", answer: answer, source: "Wikipédia", verified: true))
        XCTAssertEqual(store.keptAnswer(for: "C'est quoi la photosynthèse ?")?.text, answer, "another wording of the same question")
        XCTAssertEqual(store.keptAnswer(for: "Explique-moi la photosynthèse.")?.text, answer)
        XCTAssertNil(store.keptAnswer(for: "Qu'est-ce que la respiration ?"))
        XCTAssertTrue(JarvisKnowledgeStore.provenance(of: store.keptAnswer(for: "C'est quoi la photosynthèse ?")!).contains("Wikipédia"))
        XCTAssertEqual(JarvisKnowledgeStore(folder: folder, defaults: defaults).keptAnswer(for: "C'est quoi la photosynthèse ?")?.text, answer,
                       "found again after the app is closed")
        XCTAssertFalse(store.syncPayload().contains { ($0["text"] as? String) == answer }, "kept answers are not sent to the PC as facts")
        // Contradicted by the person: not reused any more.
        store.learn(said: "Non, c'est faux, elle produit aussi de l'oxygène", previousQuestion: "Qu'est-ce que la photosynthèse ?")
        XCTAssertNil(store.keptAnswer(for: "C'est quoi la photosynthèse ?"))
    }

    func testOnlyAnswersThatDoNotDependOnThePersonOrTheMomentAreKept() {
        let (store, _, _) = freshStore()
        let answer = "Une réponse assez longue pour être gardée en mémoire."
        XCTAssertNil(store.keepAnswer(question: "Quel temps fait-il à Paris aujourd'hui ?", answer: answer, source: "test", verified: true))
        XCTAssertNil(store.keepAnswer(question: "Qu'est-ce que je dois faire demain ?", answer: answer, source: "test", verified: true))
        XCTAssertNil(store.keepAnswer(question: "Et celle-là, elle sert à quoi ?", answer: answer, source: "test", verified: true))
        XCTAssertNil(store.keepAnswer(question: "Pourquoi ?", answer: answer, source: "test", verified: true))
        XCTAssertNil(store.keepAnswer(question: "Comment fonctionne une pile ?", answer: "Court.", source: "test", verified: true))
        XCTAssertNotNil(store.keepAnswer(question: "Pourquoi le ciel est-il bleu ?", answer: answer, source: "test", verified: false))
        let expired = store.keepAnswer(question: "Qui a écrit Les Misérables ?", answer: answer, source: "test", verified: false,
                                       now: Date().addingTimeInterval(-8 * 86_400))
        XCTAssertNotNil(expired)
        XCTAssertNil(store.keptAnswer(for: "Qui a écrit Les Misérables ?"), "an answer not verified is reused 7 days at most")
    }

    func testTheMemoryIsFoundUnderAnotherWording() {
        let (store, _, _) = freshStore()
        store.learn(said: "J'habite à Lyon")
        store.learn(said: "Ma sœur s'appelle Julie")
        XCTAssertEqual(store.relevant(to: "Où est-ce que j'habite ?").first?.text, "L'utilisateur habite Lyon.")
        XCTAssertEqual(store.relevant(to: "Comment s'appelle ma sœur ?").first?.text, "Sœur de l'utilisateur : Julie.")
        if JarvisLanguageTools.lemmas("habitez").first?.lowercased() != "habitez" {
            // French lemmas: « habitez » and « habite » are the same verb.
            XCTAssertEqual(store.relevant(to: "Vous savez où j'habitais ?").first?.text, "L'utilisateur habite Lyon.")
        }
        XCTAssertTrue(store.relevant(to: "Combien font deux et deux ?").isEmpty)
    }

    func testJarvisSaysItsMemoriesToThePerson() {
        XCTAssertEqual(JarvisKnowledgeStore.spokenToUser("L'utilisateur aime le jazz."), "vous aimez le jazz")
        XCTAssertEqual(JarvisKnowledgeStore.spokenToUser("Sœur de l'utilisateur : Julie."), "votre sœur : Julie")
        XCTAssertEqual(JarvisKnowledgeStore.spokenToUser("L'utilisateur n'aime pas les épinards."), "vous n'aimez pas les épinards")
        XCTAssertEqual(JarvisKnowledgeStore.spokenToUser("La réunion est à midi."), "La réunion est à midi")
    }

    func testTheRouterAnswersAboutItsOwnMemory() {
        let (store, folder, defaults) = freshStore()
        let journal = JarvisConversationJournal(memoryFolder: folder, defaults: defaults)
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: defaults), context: JarvisConversationContext(),
                                               profile: JarvisUserProfile(defaults: defaults), knowledge: store, journal: journal)
        func spoken(_ phrase: String) -> String {
            guard case .answer(let response) = router.route(phrase) else { return "" }
            return response.spokenResponse
        }
        XCTAssertTrue(spoken("Tu as accès à ta mémoire Obsidian ?").contains("aucun souvenir"))
        store.learn(said: "J'aime le jazz")
        store.learn(said: "J'habite à Lyon")
        let overview = spoken("Est-ce que tu as accès à Obsidian ?")
        XCTAssertTrue(overview.contains("Mémoire Jarvis") && overview.contains("2 souvenirs"), overview)
        XCTAssertTrue(spoken("Tu te souviens de Lyon ?").contains("vous habitez Lyon"))
        XCTAssertTrue(spoken("Cherche dans ta mémoire le tennis").contains("ne contient rien"))
        guard case .openQuestion = router.route("Que sais-tu de la photosynthèse ?") else {
            return XCTFail("A knowledge question the memory cannot answer goes to the brain.")
        }
        XCTAssertTrue(spoken("Ne garde plus nos conversations").contains("ne garde plus"))
        XCTAssertFalse(journal.isEnabled)
    }

    func testTheCompleteResetWaitsForConfirmation() {
        let (store, folder, defaults) = freshStore()
        let journal = JarvisConversationJournal(memoryFolder: folder, defaults: defaults)
        let profile = JarvisUserProfile(defaults: defaults)
        profile.name = "Tony"
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: defaults), context: JarvisConversationContext(),
                                               profile: profile, knowledge: store, journal: journal)
        store.learn(said: "J'aime le jazz")
        guard case .answer(let asked) = router.route("Réinitialise complètement ta mémoire") else { return XCTFail("reset not understood") }
        XCTAssertEqual(asked.status, .confirmationRequired)
        XCTAssertEqual(store.notes.count, 1, "nothing is erased before the confirmation")
        guard case .answer(let refused) = router.route("Non") else { return XCTFail("cancel not understood") }
        XCTAssertTrue(refused.spokenResponse.contains("n'efface rien"))
        XCTAssertEqual(store.notes.count, 1)
        _ = router.route("Efface toute ta mémoire")
        guard case .answer(let done) = router.route("Je confirme") else { return XCTFail("confirmation not understood") }
        XCTAssertTrue(done.spokenResponse.contains("repars de zéro"), done.spokenResponse)
        XCTAssertTrue(store.notes.isEmpty)
        XCTAssertNil(profile.name)
        XCTAssertNil(JarvisConfirmations.shared.confirm(), "a confirmation is used once")
    }

    func testTheConversationJournalIsMarkdownAndCanBeErased() {
        let (_, folder, defaults) = freshStore()
        let journal = JarvisConversationJournal(memoryFolder: folder, defaults: defaults)
        let written = expectation(description: "written")
        journal.record(user: "Quelle heure est-il ?", jarvis: "Il est midi.", channel: "voix") { written.fulfill() }
        wait(for: [written], timeout: 2)
        let page = (try? String(contentsOf: journal.file(for: Date()), encoding: .utf8)) ?? ""
        XCTAssertTrue(page.hasPrefix("# Conversations du ") && page.contains("**Vous :** Quelle heure est-il ?") && page.contains("**Jarvis :** Il est midi."))
        XCTAssertEqual(journal.days().count, 1)
        XCTAssertEqual(journal.eraseAll(), 1)
        XCTAssertTrue(journal.days().isEmpty)
        journal.isEnabled = false
        let skipped = expectation(description: "skipped")
        journal.record(user: "Bonjour", jarvis: "Bonjour.", channel: "clavier") { skipped.fulfill() }
        wait(for: [skipped], timeout: 2)
        XCTAssertTrue(journal.days().isEmpty, "nothing is kept when the person said no")
    }

    // MARK: Refonte §7, §17 — the person's control

    func testTheEmergencyStopIsHeardBeforeAnythingElse() {
        XCTAssertTrue(JarvisEmergencyStop.isStopRequest("Jarvis, arrêt d'urgence !"))
        XCTAssertTrue(JarvisEmergencyStop.isStopRequest("Arrête tout immédiatement"))
        XCTAssertFalse(JarvisEmergencyStop.isStopRequest("Arrête le minuteur"))
        XCTAssertTrue(JarvisEmergencyStop.isReleaseRequest("Jarvis, reprends."))
        JarvisEmergencyStop.shared.engage()
        defer { JarvisEmergencyStop.shared.release() }
        XCTAssertTrue(JarvisEmergencyStop.shared.isEngaged)
        let brain = JarvisLocalBrain(downloader: JarvisModelDownloader(model: .qwen25Instruct1_5B, directory: FileManager.default.temporaryDirectory))
        let answered = expectation(description: "refused")
        brain.answerOpenQuestion("Pourquoi le ciel est-il bleu ?", context: JarvisConversationContext(), onPartial: { _ in }) { response in
            XCTAssertTrue(response.spokenResponse.contains("arrêt d'urgence"))
            answered.fulfill()
        }
        wait(for: [answered], timeout: 2)
    }

    func testOnlyFreeServicesCanBeCalled() {
        XCTAssertTrue(JarvisCostGuard.permits(JarvisInternetClient.url(host: "fr.wikipedia.org", path: "/w/api.php")))
        XCTAssertTrue(JarvisCostGuard.permits(JarvisInternetClient.url(host: "api.open-meteo.com", path: "/v1/forecast")))
        XCTAssertFalse(JarvisCostGuard.permits(JarvisInternetClient.url(host: "api.openai.com", path: "/v1/chat/completions")), "a paid API is refused")
        XCTAssertFalse(JarvisCostGuard.permits(URL(string: "http://fr.wikipedia.org/w/api.php")), "never without HTTPS")
        XCTAssertFalse(JarvisCostGuard.permits(nil))
    }
}
