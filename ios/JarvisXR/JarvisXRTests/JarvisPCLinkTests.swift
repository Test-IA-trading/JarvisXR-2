import XCTest
@testable import JarvisXR

/// The link with Jarvis PC: addresses, the streamed answer, the shared first name and
/// notes, and « Sur le PC, … » requests. No network is used: the PC side has its own
/// tests (pc/tests) and its --autotest, run on the real PC.
final class JarvisPCLinkTests: XCTestCase {
    private var defaults: UserDefaults!
    private var account: String!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "JarvisPCLinkTests.\(UUID().uuidString)")
        account = "JarvisPCLinkTests.\(UUID().uuidString)"
        // The CI's simulator build is unsigned: its keychain refuses writes.
        JarvisKeychain.fallback = defaults
    }

    override func tearDown() {
        JarvisKeychain.set(nil, for: account)
        JarvisKeychain.fallback = .standard
        super.tearDown()
    }

    func testAddressesBecomeThePCsURL() {
        XCTAssertEqual(JarvisPCLink.url(address: "192.168.1.23", path: "/v1/health")?.absoluteString, "http://192.168.1.23:8765/v1/health")
        XCTAssertEqual(JarvisPCLink.url(address: " 192.168.1.23:9000 ", path: "/v1/ask")?.absoluteString, "http://192.168.1.23:9000/v1/ask")
        XCTAssertEqual(JarvisPCLink.url(address: "http://192.168.1.23:8765/", path: "/v1/ask")?.absoluteString, "http://192.168.1.23:8765/v1/ask")
        XCTAssertEqual(JarvisPCLink.url(address: "pc.tail1234.ts.net", path: "/v1/inbox")?.absoluteString, "http://pc.tail1234.ts.net:8765/v1/inbox")
        XCTAssertNil(JarvisPCLink.url(address: "", path: "/v1/health"))
        XCTAssertNil(JarvisPCLink.url(address: "192.168.1.23:99999", path: "/v1/health"))
    }

    func testPairingIsNeededBeforeAnyExchange() {
        let link = JarvisPCLink(defaults: defaults, codeAccount: account)
        XCTAssertFalse(link.isConfigured)
        XCTAssertTrue(link.usesPCBrain)
        link.address = "192.168.1.23"
        XCTAssertFalse(link.isConfigured, "The code is needed too")
        link.pairingCode = "k7p2-9xq4"
        XCTAssertTrue(link.isConfigured)
        XCTAssertEqual(link.pairingCode, "K7P2-9XQ4")
        XCTAssertEqual(link.request("/v1/health")?.value(forHTTPHeaderField: "Authorization"), "Bearer K7P2-9XQ4")
        var refusedForLackOfPairing = false
        let unpaired = JarvisPCLink(defaults: UserDefaults(suiteName: "JarvisPCLinkTests.empty.\(UUID().uuidString)")!, codeAccount: account + ".empty")
        unpaired.checkConnection { result in
            if case .failure(.notConfigured) = result { refusedForLackOfPairing = true }
        }
        XCTAssertTrue(refusedForLackOfPairing, "Nothing is sent before the PC is paired")
    }

    func testTheStreamedAnswerIsRead() {
        XCTAssertEqual(JarvisPCLink.parseLine(#"{"partial": "Bonjour."}"#)?.partial, "Bonjour.")
        XCTAssertEqual(JarvisPCLink.parseLine(#"{"final": "Bonjour. Je suis Jarvis.", "tokens_per_second": 45}"#)?.final, "Bonjour. Je suis Jarvis.")
        XCTAssertEqual(JarvisPCLink.parseLine(#"{"error": "Le cerveau du PC n'est pas prêt."}"#)?.error, "Le cerveau du PC n'est pas prêt.")
        XCTAssertNil(JarvisPCLink.parseLine("pas du JSON"))
    }

    func testMemoryIsSharedWithoutDuplicates() {
        let memory = JarvisMemoryStore(defaults: defaults)
        let profile = JarvisUserProfile(defaults: defaults)
        _ = memory.saveNote("note de l'iPhone")
        profile.name = "Tony"
        let payload = JarvisPCLink.memoryPayload(memory: memory, profile: profile)
        XCTAssertEqual(payload["name"] as? String, "Tony")
        XCTAssertEqual((payload["notes"] as? [[String: String]])?.first?["text"], "note de l'iPhone")

        let fromPC: [String: Any] = [
            "name": "Pepper",
            "name_updated": "2099-01-01T00:00:00Z",
            "notes": [
                ["id": "8D6E2C1A-1111-4A4A-9B9B-123456789ABC", "text": "note du PC", "created": "2026-11-25T10:00:00Z"],
                ["id": memory.loadNotes()[0].id.uuidString, "text": "note de l'iPhone", "created": "2026-11-25T09:00:00Z"],
            ],
        ]
        XCTAssertEqual(JarvisPCLink.adopt(fromPC, memory: memory, profile: profile), 1)
        XCTAssertEqual(Set(memory.loadNotes().map(\.text)), ["note de l'iPhone", "note du PC"])
        XCTAssertEqual(profile.name, "Pepper", "The PC's more recent first name wins")
        XCTAssertEqual(JarvisPCLink.adopt(fromPC, memory: memory, profile: profile), 0, "A note is never imported twice")

        let older: [String: Any] = ["name": "Happy", "name_updated": "2001-01-01T00:00:00Z", "notes": []]
        JarvisPCLink.adopt(older, memory: memory, profile: profile)
        XCTAssertEqual(profile.name, "Pepper", "An older first name does not replace a newer one")
    }

    private func route(_ phrase: String) -> JarvisResponse? {
        let router = JarvisFrenchCommandRouter(memory: JarvisMemoryStore(defaults: defaults), scene: JarvisSpatialSceneMemory(), context: JarvisConversationContext(), profile: JarvisUserProfile(defaults: defaults))
        guard case .answer(let response) = router.route(phrase) else { return nil }
        return response
    }

    func testRequestsForThePC() {
        let open = route("Sur le PC, ouvre Spotify")
        XCTAssertEqual(open?.data["action"], "pc_command")
        XCTAssertEqual(open?.data["text"], "ouvre Spotify")
        let reversed = route("Jarvis, ouvre YouTube sur le PC")
        XCTAssertEqual(reversed?.data["action"], "pc_command")
        XCTAssertEqual(reversed?.data["text"], "ouvre YouTube")
        let say = route("Dis sur le PC que le dîner est prêt")
        XCTAssertEqual(say?.data["action"], "pc_say")
        XCTAssertEqual(say?.data["text"], "le dîner est prêt")
        XCTAssertEqual(route("Dis sur le PC quelqu'un sonne")?.data["text"], "quelqu'un sonne")
        XCTAssertNotEqual(route("Je l'ai mis sur le PC")?.data["action"], "pc_command", "A statement about the PC is not a command")
        XCTAssertTrue(JarvisLifeActionPerformer.handles(open!))
    }

    func testAnUnpairedPCIsExplained() {
        guard !JarvisPCLink.shared.isConfigured else { return }
        var outcome: JarvisResponse?
        JarvisLifeActionPerformer.perform(.ok("Je demande au PC.", data: ["action": "pc_command", "text": "ouvre Spotify"])) { outcome = $0 }
        XCTAssertEqual(outcome?.status, .unavailable)
        XCTAssertTrue(outcome?.spokenResponse.contains("Réglages › Jarvis PC") == true)
    }
}
