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
}
