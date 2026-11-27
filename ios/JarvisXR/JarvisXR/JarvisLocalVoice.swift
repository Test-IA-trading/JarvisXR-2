import AVFoundation
import CryptoKit
import Foundation
import SherpaOnnx

/// Jarvis's own voice, made on the iPhone itself: the same Piper voice as Jarvis PC
/// (« pierre », set to the measured reference style: +1.5 semitone, pace 1.10, 0.3 s between
/// sentences), run by sherpa-onnx with espeak-ng for the French phonemes. No PC, no network
/// once installed. The voice package (77 Mo) is downloaded once, with the user's approval,
/// from the JarvisXR release « voix-jarvis-v1 », and checked by size and SHA-256 before
/// use; nothing is sent. Sentences are rendered one after the other on a background queue
/// and handed back in their order, so the conversation audio plays them without a gap.
final class JarvisLocalVoice {
    static let shared = JarvisLocalVoice()

    static let enabledKey = "JarvisXR.localVoice"
    /// « Utilise ta voix » / « Utilise la voix de l'iPhone ». On by default.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static let pitchKey = "JarvisXR.localVoicePitch"
    static let defaultPitch = -2.0
    /// The pitch the voice is played at, in semitones. The package's +1,5 sounded too high
    /// and young to the owner (docs/VISION_JARVIS.md §23): −2 by default, deeper and more
    /// mature, at the same pace; « voix plus grave » / « plus aiguë » move it by one, −5 to +3.
    static var pitchSemitones: Double {
        get { UserDefaults.standard.object(forKey: pitchKey) == nil ? defaultPitch : UserDefaults.standard.double(forKey: pitchKey) }
        set { UserDefaults.standard.set(min(max(newValue, -5), 3), forKey: pitchKey) }
    }

    // The pinned package (pc/tools_pack_voice.py), published with the app's releases.
    static let packSize: Int64 = 77_396_355
    static let packSHA256 = "f3411c49b876e940b33ffa244c3407dd11fc85caf97c70ae324c6022d22bf1f6"
    static var packURL: URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = "/Test-IA-trading/JarvisXR-2/releases/download/voix-jarvis-v1/jarvis-voix-pierre-v1.pack"
        return components.url
    }

    enum State: Equatable {
        case notInstalled
        case downloading
        case installing
        case ready
        case failed(String)
    }

    struct Settings: Codable, Equatable {
        var speakerID: Int
        var lengthScale: Double
        var pitchSemitones: Double
        var sentenceSilence: Double

        enum CodingKeys: String, CodingKey {
            case speakerID = "speaker_id"
            case lengthScale = "length_scale"
            case pitchSemitones = "pitch_semitones"
            case sentenceSilence = "sentence_silence"
        }
    }

    let folder: URL
    private(set) var state: State
    private var tts: SherpaOnnxOfflineTtsWrapper?
    private var settings: Settings?
    private let queue = DispatchQueue(label: "jarvis.local-voice", qos: .userInitiated)
    private let generationLock = NSLock()
    private var generation = 0

    init(folder: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        self.folder = folder ?? support.appendingPathComponent("JarvisVoice/v1", isDirectory: true)
        state = .notInstalled
        if let data = try? Data(contentsOf: self.folder.appendingPathComponent("voice.json")),
           let stored = try? JSONDecoder().decode(Settings.self, from: data),
           FileManager.default.fileExists(atPath: self.folder.appendingPathComponent("model.onnx").path) {
            settings = stored
            state = .ready
        }
    }

    var isInstalled: Bool { state == .ready }
    /// Installed and chosen: Jarvis speaks with it.
    var isUsable: Bool { Self.isEnabled && isInstalled }

    // MARK: Installing

    /// Downloads, checks and unpacks the voice once. `completion` (main queue): nil when
    /// installed, else a short French reason.
    func install(completion: @escaping (String?) -> Void) {
        guard state != .ready else { return completion(nil) }
        guard state != .downloading, state != .installing, let url = Self.packURL else { return completion(nil) }
        state = .downloading
        let task = URLSession.shared.downloadTask(with: url) { [weak self] location, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, let location, (200...299).contains(status) else {
                return self.finish("Téléchargement de la voix impossible. Vérifiez le Wi-Fi puis réessayez.", completion)
            }
            let staged = self.folder.deletingLastPathComponent().appendingPathComponent("voix.pack")
            try? FileManager.default.createDirectory(at: staged.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: staged)
            guard (try? FileManager.default.moveItem(at: location, to: staged)) != nil else {
                return self.finish("Le fichier de la voix n'a pas pu être enregistré.", completion)
            }
            DispatchQueue.main.async { self.state = .installing }
            self.queue.async {
                let problem = self.unpack(staged)
                try? FileManager.default.removeItem(at: staged)
                self.finish(problem, completion)
            }
        }
        task.resume()
    }

    private func finish(_ problem: String?, _ completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            if let problem {
                self.state = .failed(problem)
            } else {
                self.state = .ready
            }
            completion(problem)
        }
    }

    /// Checks the package and writes its files (an 8-byte header length, a JSON index, the files).
    func unpack(_ pack: URL, expectedSize: Int64 = packSize, expectedSHA256: String = packSHA256) -> String? {
        let size = ((try? FileManager.default.attributesOfItem(atPath: pack.path))?[.size] as? NSNumber)?.int64Value ?? -1
        guard size == expectedSize, (try? JarvisModelDownloader.sha256(of: pack)) == expectedSHA256 else {
            return "Le fichier de la voix est incomplet ou différent de celui attendu. Réessayez."
        }
        guard let data = try? Data(contentsOf: pack, options: .alwaysMapped), data.count > 8 else { return "Voix illisible." }
        var length: UInt64 = 0
        for index in 0..<8 { length |= UInt64(data[data.startIndex + index]) << (8 * UInt64(index)) }
        let headerEnd = 8 + Int(length)
        guard headerEnd <= data.count,
              let header = (try? JSONSerialization.jsonObject(with: data.subdata(in: 8..<headerEnd))) as? [String: Any],
              let files = header["files"] as? [[String: Any]], let voice = header["voice"] as? [String: Any],
              let voiceData = try? JSONSerialization.data(withJSONObject: voice),
              let decoded = try? JSONDecoder().decode(Settings.self, from: voiceData) else { return "Voix illisible." }
        try? FileManager.default.removeItem(at: folder)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in files {
                guard let path = file["path"] as? String, !path.contains(".."), let offset = file["offset"] as? Int, let count = file["size"] as? Int,
                      headerEnd + offset + count <= data.count else { return "Voix illisible." }
                let target = folder.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.subdata(in: (headerEnd + offset)..<(headerEnd + offset + count)).write(to: target)
            }
            try voiceData.write(to: folder.appendingPathComponent("voice.json"))
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var installed = folder
            try? installed.setResourceValues(values)
        } catch {
            return "La voix n'a pas pu être installée."
        }
        settings = decoded
        return nil
    }

    // MARK: Speaking

    /// Renders `text` with Jarvis's voice; `deliver` runs on the main queue, in the order of
    /// the calls, with the sound (nil: the iPhone's own voice says it instead).
    func render(_ text: String, deliver: @escaping (AVAudioPCMBuffer?) -> Void) {
        generationLock.lock()
        let mine = generation
        generationLock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            let buffer = self.isCurrent(mine) ? self.synthesize(text) : nil
            DispatchQueue.main.async {
                guard self.isCurrent(mine) else { return }
                deliver(buffer)
            }
        }
    }

    /// Drops the sentences not yet rendered (an interruption, a new reply).
    func cancelAll() {
        generationLock.lock()
        generation += 1
        generationLock.unlock()
    }

    private func isCurrent(_ value: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return value == generation
    }

    /// On the voice's queue only.
    private func synthesize(_ text: String) -> AVAudioPCMBuffer? {
        guard let settings, let engine = loadEngine(settings) else { return nil }
        let audio = engine.generate(text: text, sid: settings.speakerID, speed: 1.0)
        let rate = Double(audio.sampleRate)
        let samples = audio.samples
        guard rate > 0, !samples.isEmpty else { return nil }
        // Spoken slower by `factor` (lengthScale), played `factor` times faster: another pitch, same pace.
        let factor = pow(2, (enginePitch ?? Self.pitchSemitones) / 12)
        let shifted = Self.resample(samples, by: factor)
        let silence = Int(rate * settings.sentenceSilence)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(shifted.count + silence)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(shifted.count + silence)
        for index in 0..<shifted.count { channel[index] = shifted[index] }
        for index in shifted.count..<(shifted.count + silence) { channel[index] = 0 }
        return buffer
    }

    /// Pitch the loaded engine was built for (its pace depends on it). On the voice's queue.
    private var enginePitch: Double?

    private func loadEngine(_ settings: Settings) -> SherpaOnnxOfflineTtsWrapper? {
        let pitch = Self.pitchSemitones
        if let tts, enginePitch == pitch { return tts }
        tts = nil
        enginePitch = pitch
        let factor = pow(2, pitch / 12)
        let vits = sherpaOnnxOfflineTtsVitsModelConfig(
            model: folder.appendingPathComponent("model.onnx").path,
            lexicon: "",
            tokens: folder.appendingPathComponent("tokens.txt").path,
            dataDir: folder.appendingPathComponent("espeak-ng-data").path,
            lengthScale: Float(settings.lengthScale * factor)
        )
        let model = sherpaOnnxOfflineTtsModelConfig(vits: vits, numThreads: 2, debug: 0)
        var config = sherpaOnnxOfflineTtsConfig(model: model)
        let engine = SherpaOnnxOfflineTtsWrapper(config: &config)
        guard engine.tts != nil else { return nil }
        tts = engine
        return engine
    }

    /// `samples` played `factor` times faster (linear interpolation).
    static func resample(_ samples: [Float], by factor: Double) -> [Float] {
        guard abs(factor - 1) > 0.001, samples.count > 1 else { return samples }
        let count = Int(Double(samples.count - 1) / factor)
        var out = [Float](repeating: 0, count: max(count, 0))
        for index in 0..<out.count {
            let position = Double(index) * factor
            let low = Int(position)
            let fraction = Float(position - Double(low))
            out[index] = samples[low] * (1 - fraction) + samples[min(low + 1, samples.count - 1)] * fraction
        }
        return out
    }
}
