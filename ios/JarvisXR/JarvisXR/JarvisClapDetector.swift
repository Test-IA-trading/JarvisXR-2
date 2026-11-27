import Foundation

/// Two hand claps in a row, heard while Jarvis waits to be called (Réveil par la voix).
///
/// A clap is short, loud and sudden: within one 10 ms frame the sound jumps far above
/// the room's level, then falls by at least 12 dB within 60 ms (the room's echo is much
/// quieter than the clap itself). Two claps 0.15 to 0.8 s apart make a double clap.
/// Speech and music keep their energy for longer than a clap; a single knock has no
/// partner. A clap is also bright (its energy is mostly above 1 kHz), where a knock on a
/// door or a desk is dull, and the two claps of a pair are about as loud as each other
/// (docs/specs/voix.md §5). Pure logic, fed with audio samples, so it is tested without a
/// microphone; nothing is stored, only the level of the last frames is kept.
struct JarvisClapDetector {
    let sampleRate: Double
    let minimumGap: Double = 0.15
    let maximumGap: Double = 0.8
    /// The fall of 12 dB must happen within this time after the start of the sound.
    let decayWindow: Double = 0.06
    /// The echo of a clap is ignored for at most this long.
    let tailDuration: Double = 0.12
    /// No new double clap right after one (a third clap, an echo).
    let cooldown: Double = 1.0
    /// A clap's onset is bright: the « centre » of its spectrum is above this frequency.
    let minimumBrightness: Double = 1000
    /// The two claps of a pair differ by 8 dB at most.
    let maximumLevelRatio: Float = 2.5

    private enum Phase {
        case idle
        case rising(start: Double, peak: Float)
        case tail(until: Double)
        case sustained
    }

    private(set) var noiseFloor: Float = 0.003
    private var phase: Phase = .idle
    private var clock: Double = 0
    private var frame: [Float] = []
    private let frameSize: Int
    private var previousRMS: Float = 0
    private var lastClap: (time: Double, level: Float)?
    private var quietUntil: Double = 0

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        frameSize = max(64, Int(sampleRate * 0.01))
        frame.reserveCapacity(frameSize)
    }

    /// Feeds microphone samples; true when they complete a double clap.
    mutating func ingest<Samples: Collection>(_ samples: Samples) -> Bool where Samples.Element == Float {
        var detected = false
        for sample in samples {
            frame.append(sample)
            if frame.count == frameSize {
                if processFrame() { detected = true }
                frame.removeAll(keepingCapacity: true)
            }
        }
        return detected
    }

    private mutating func processFrame() -> Bool {
        var peak: Float = 0
        var sumOfSquares: Float = 0
        var sumOfSteps: Float = 0
        var previous = frame.first ?? 0
        for value in frame {
            peak = max(peak, abs(value))
            sumOfSquares += value * value
            sumOfSteps += (value - previous) * (value - previous)
            previous = value
        }
        let rms = (sumOfSquares / Float(frame.count)).squareRoot()
        // Spectral « centre » from the energy of the sample-to-sample steps (a high-pass).
        let brightness = sumOfSquares > 0 ? sampleRate / (2 * Double.pi) * Double((sumOfSteps / sumOfSquares).squareRoot()) : 0
        let start = clock
        clock += Double(frame.count) / sampleRate
        defer { previousRMS = rms }

        switch phase {
        case .tail(let until):
            if start >= until || rms < noiseFloor * 4 {
                phase = .idle
            }
            return false
        case .sustained:
            if rms < noiseFloor * 4 {
                phase = .idle
            }
            return false
        case .rising(let eventStart, let eventPeak):
            let highest = max(eventPeak, rms)
            if rms < highest / 4 {
                // Fell by 12 dB quickly: a clap. Its echo is skipped, then the next one counts.
                phase = .tail(until: eventStart + tailDuration)
                return registerClap(at: eventStart, level: highest)
            }
            phase = start - eventStart > decayWindow ? .sustained : .rising(start: eventStart, peak: highest)
            return false
        case .idle:
            let sudden = rms > max(previousRMS, noiseFloor) * 3
            if peak > max(0.04, noiseFloor * 15), rms > noiseFloor * 5, sudden {
                // A dull knock is let pass like a sustained sound.
                phase = brightness >= minimumBrightness ? .rising(start: start, peak: rms) : .sustained
                return false
            }
            // The room's level, learnt only outside loud sounds.
            noiseFloor = min(0.2, max(0.0005, noiseFloor * 0.995 + rms * 0.005))
            return false
        }
    }

    private mutating func registerClap(at time: Double, level: Float) -> Bool {
        guard time >= quietUntil else { return false }
        if let last = lastClap {
            let gap = time - last.time
            let ratio = level / max(last.level, 1e-6)
            if gap >= minimumGap && gap <= maximumGap && ratio <= maximumLevelRatio && ratio >= 1 / maximumLevelRatio {
                lastClap = nil
                quietUntil = time + cooldown
                return true
            }
        }
        lastClap = (time, level)
        return false
    }
}

/// Holds a detector for the microphone's audio thread, which feeds it buffer by buffer.
final class JarvisClapDetectorBox {
    private var detector: JarvisClapDetector

    init(sampleRate: Double) {
        detector = JarvisClapDetector(sampleRate: sampleRate)
    }

    func ingest(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        detector.ingest(samples)
    }
}
