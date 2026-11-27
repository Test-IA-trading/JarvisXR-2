import AVFoundation
import XCTest
@testable import JarvisXR

/// V10: Jarvis's memory copied from the PC, the PC's voice played on the iPhone, and the
/// personality shared with Jarvis PC.
final class JarvisMemoryVoiceTests: XCTestCase {
    func testTheMemoryFromThePCReachesTheIPhoneBrain() {
        let defaults = UserDefaults(suiteName: "JarvisMemoryVoiceTests")!
        defaults.removePersistentDomain(forName: "JarvisMemoryVoiceTests")
        let store = JarvisKnowledgeStore(defaults: defaults)
        store.adopt([
            ["id": "a", "kind": "fait", "text": "Sœur de l'utilisateur : Julie.", "updated": "2026-11-27T10:00:00+00:00"],
            ["id": "b", "kind": "preference", "text": "L'utilisateur aime le café noir.", "updated": "2026-11-27T11:00:00+00:00"],
        ])
        let lines = store.contextLines(for: "Comment s'appelle ma sœur ?")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[1].contains("Julie"))
        XCTAssertTrue(store.contextLines(for: "Combien font deux et deux ?").isEmpty, "only what is relevant")
        store.adopt([["id": "a", "deleted": true]])
        XCTAssertFalse(store.notes.contains { $0.text.contains("Julie") }, "a memory forgotten on the PC goes away")
        XCTAssertEqual(JarvisKnowledgeStore(defaults: defaults).notes.count, 1, "kept between launches")
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
