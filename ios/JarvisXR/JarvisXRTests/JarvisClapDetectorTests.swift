import XCTest
@testable import JarvisXR

/// Two hand claps call Jarvis while it waits for « Jarvis ». The detector is fed with
/// synthetic sound (a quiet room, claps with an echo, spoken syllables), the same cases
/// as the Python replica that was checked before this file was written.
final class JarvisClapDetectorTests: XCTestCase {
    private let rate = 48_000.0

    /// Deterministic noise, identical to the Python replica's.
    private struct Noise {
        var state: Int

        mutating func next() -> Float {
            state = (state * 1_103_515_245 + 12_345) % 2_147_483_648
            return Float(Double(state) / 2_147_483_648 * 2 - 1)
        }
    }

    private func room(_ seconds: Double, level: Float = 0.002) -> [Float] {
        var noise = Noise(state: 12_345)
        return (0..<Int(seconds * rate)).map { _ in noise.next() * level }
    }

    /// A clap: a burst decaying in about 3 ms, then the room's echo for a quarter second.
    private func addClap(_ signal: inout [Float], at time: Double, amplitude: Float = 0.5, echo: Float = 0.03) {
        var noise = Noise(state: 99)
        let start = Int(time * rate)
        let burstLength = Int(0.03 * rate)
        for k in 0..<Int(0.25 * rate) where start + k < signal.count {
            let burst: Float = k < burstLength ? amplitude * Float(exp(-Double(k) / (0.003 * rate))) : 0
            let tail = echo * Float(exp(-Double(k) / (0.08 * rate)))
            signal[start + k] += (burst + tail) * noise.next()
        }
    }

    /// A spoken syllable: a voiced tone that lasts.
    private func addSyllable(_ signal: inout [Float], at time: Double, duration: Double = 0.25) {
        let start = Int(time * rate)
        for k in 0..<Int(duration * rate) where start + k < signal.count {
            let envelope = min(1.0, Double(k) / (0.01 * rate))
            signal[start + k] += 0.25 * Float(envelope * sin(2 * Double.pi * 220 * Double(k) / rate))
        }
    }

    /// Fed like the microphone, 1024 samples at a time.
    private func detections(in signal: [Float]) -> Int {
        var detector = JarvisClapDetector(sampleRate: rate)
        var count = 0
        var index = 0
        while index < signal.count {
            let end = min(index + 1024, signal.count)
            if detector.ingest(signal[index..<end]) { count += 1 }
            index = end
        }
        return count
    }

    func testADoubleClapIsHeardOnce() {
        var signal = room(2.0)
        addClap(&signal, at: 0.6)
        addClap(&signal, at: 0.95)
        XCTAssertEqual(detections(in: signal), 1)
    }

    func testOneClapOrClapsFarApartDoNotCount() {
        var single = room(2.0)
        addClap(&single, at: 0.6)
        XCTAssertEqual(detections(in: single), 0)
        var apart = room(2.5)
        addClap(&apart, at: 0.5)
        addClap(&apart, at: 1.8)
        XCTAssertEqual(detections(in: apart), 0)
    }

    func testATripleClapCountsOnce() {
        var signal = room(2.5)
        addClap(&signal, at: 0.5)
        addClap(&signal, at: 0.85)
        addClap(&signal, at: 1.2)
        XCTAssertEqual(detections(in: signal), 1)
    }

    func testSpeechIsNotAClap() {
        var signal = room(2.0)
        addSyllable(&signal, at: 0.5)
        addSyllable(&signal, at: 0.9)
        XCTAssertEqual(detections(in: signal), 0)
    }

    func testEchoingAndNoisyRoomsStillWork() {
        var echoing = room(2.0)
        addClap(&echoing, at: 0.6, echo: 0.08)
        addClap(&echoing, at: 0.95, echo: 0.08)
        XCTAssertEqual(detections(in: echoing), 1)
        var noisy = room(2.0, level: 0.02)
        addClap(&noisy, at: 0.6)
        addClap(&noisy, at: 0.95)
        XCTAssertEqual(detections(in: noisy), 1)
    }

    func testFaintTapsAreIgnored() {
        var signal = room(2.0)
        addClap(&signal, at: 0.6, amplitude: 0.02)
        addClap(&signal, at: 0.95, amplitude: 0.02)
        XCTAssertEqual(detections(in: signal), 0)
    }

    func testClapsAreOnByDefault() {
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: JarvisWakeWordSettings.clapsKey)
        defer {
            if let original {
                defaults.set(original, forKey: JarvisWakeWordSettings.clapsKey)
            } else {
                defaults.removeObject(forKey: JarvisWakeWordSettings.clapsKey)
            }
        }
        defaults.removeObject(forKey: JarvisWakeWordSettings.clapsKey)
        XCTAssertTrue(JarvisWakeWordSettings.clapsEnabled)
        JarvisWakeWordSettings.clapsEnabled = false
        XCTAssertFalse(JarvisWakeWordSettings.clapsEnabled)
    }
}

/// The « Jarvis » voice profile: the default, calm and a little deeper.
final class JarvisVoiceProfileTests: XCTestCase {
    func testTheJarvisVoiceIsTheDefault() {
        let defaults = UserDefaults.standard
        let key = "JarvisXR.voiceProfile"
        let original = defaults.string(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: key)
        let speech = JarvisSpeechService.shared
        XCTAssertEqual(speech.profile, .jarvis)
        XCTAssertEqual(speech.speechRate, 0.47, accuracy: 0.0001)
        XCTAssertEqual(speech.pitch, 0.95, accuracy: 0.0001)
        XCTAssertEqual(JarvisVoiceProfile.ordered.first, .jarvis)
        XCTAssertEqual(JarvisVoiceProfile.jarvis.displayName, "Jarvis")
    }
}
