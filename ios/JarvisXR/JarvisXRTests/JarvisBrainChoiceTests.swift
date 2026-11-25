import XCTest
@testable import JarvisXR

/// Standard or Avancé brain: both pinned files, the choice kept in Settings, the right
/// downloader and model followed, memory checked before loading, thinking never spoken.
final class JarvisBrainChoiceTests: XCTestCase {
    private var originalSelection: String?

    override func setUp() {
        super.setUp()
        originalSelection = UserDefaults.standard.string(forKey: JarvisLocalModel.selectionKey)
    }

    override func tearDown() {
        if let originalSelection {
            UserDefaults.standard.set(originalSelection, forKey: JarvisLocalModel.selectionKey)
        } else {
            UserDefaults.standard.removeObject(forKey: JarvisLocalModel.selectionKey)
        }
        super.tearDown()
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JarvisBrainChoiceTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testBothBrainsArePinnedApacheFilesOnHuggingFace() {
        XCTAssertEqual(JarvisLocalModel.catalog, [.qwen25Instruct1_5B, .qwen3Instruct4B])
        for model in JarvisLocalModel.catalog {
            XCTAssertEqual(model.downloadURL.scheme, "https", model.identifier)
            XCTAssertEqual(model.downloadURL.host, "huggingface.co", model.identifier)
            XCTAssertEqual(model.downloadURL.lastPathComponent, model.fileName, model.identifier)
            XCTAssertEqual(model.sha256.count, 64, model.identifier)
            XCTAssertTrue(model.sha256.allSatisfy { "0123456789abcdef".contains($0) }, model.identifier)
            XCTAssertEqual(model.license, "Apache 2.0", model.identifier)
        }
        let advanced = JarvisLocalModel.qwen3Instruct4B
        XCTAssertEqual(advanced.sizeBytes, 2_270_751_840)
        XCTAssertEqual(advanced.sizeDescription, "2,3 Go")
        XCTAssertNotEqual(advanced.fileName, JarvisLocalModel.qwen25Instruct1_5B.fileName, "Both brains can stay installed side by side")
        XCTAssertTrue(advanced.isAdvanced)
        XCTAssertFalse(JarvisLocalModel.qwen25Instruct1_5B.isAdvanced)
        XCTAssertEqual(JarvisLocalModel.gigabytes(advanced.requiredMemoryBytes), "2,7 Go")
    }

    func testTheStandardBrainIsTheDefaultAndTheChoiceIsFollowed() {
        UserDefaults.standard.removeObject(forKey: JarvisLocalModel.selectionKey)
        XCTAssertEqual(JarvisLocalModel.selected, .qwen25Instruct1_5B)
        XCTAssertTrue(JarvisModelDownloader.shared === JarvisModelDownloader.standard)

        JarvisLocalModel.selected = .qwen3Instruct4B
        XCTAssertEqual(JarvisLocalModel.selected, .qwen3Instruct4B)
        XCTAssertTrue(JarvisModelDownloader.shared === JarvisModelDownloader.advanced)
        XCTAssertEqual(JarvisModelDownloader.shared.model, .qwen3Instruct4B)
        XCTAssertEqual(JarvisLocalBrain().model, .qwen3Instruct4B)

        JarvisLocalModel.selected = .qwen25Instruct1_5B
        XCTAssertTrue(JarvisModelDownloader.shared === JarvisModelDownloader.standard)
    }

    func testAFixedDownloaderDecidesTheModel() {
        let downloader = JarvisModelDownloader(model: .qwen3Instruct4B, directory: temporaryDirectory())
        let brain = JarvisLocalBrain(downloader: downloader)
        XCTAssertEqual(brain.model, .qwen3Instruct4B)
        XCTAssertNotEqual(brain.availability, .ready, "Nothing is installed in a fresh folder")
    }

    func testLackOfMemoryIsExplainedInsteadOfCrashing() {
        let message = JarvisBrainError.notEnoughMemory(available: 1_500_000_000, required: 2_720_751_840).message
        XCTAssertTrue(message.contains("1,5 Go"), message)
        XCTAssertTrue(message.contains("2,7 Go"), message)
        XCTAssertTrue(message.contains("Standard"), message)
    }

    func testThinkingIsNeverShownNorSpoken() {
        XCTAssertEqual(JarvisAnswerCleaner.clean("<think>Je calcule 2 + 2.</think>La réponse est 4."), "La réponse est 4.")
        XCTAssertEqual(JarvisAnswerCleaner.clean("Voici.<think>je réfléchis encore"), "Voici.")
    }
}
