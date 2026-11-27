import AVFoundation

/// Jarvis's voice made on the PC (Piper, pc/jarvis_pc/voice.py) and played on the iPhone:
/// each sentence is asked as soon as it is written, and the sentences are handed back in
/// their order, so the conversation audio plays them one after the other without a gap.
/// When the PC is away or slow, the iPhone's own voice says the sentence instead.
final class JarvisPCVoice {
    static let shared = JarvisPCVoice()

    static let enabledKey = "JarvisXR.pcVoice"

    /// « Utilise la voix du PC » / « Utilise la voix de l'iPhone ». On by default.
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) == nil ? true : UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// The PC is paired, answers and has a voice.
    var isUsable: Bool { Self.isEnabled && JarvisPCLink.shared.isConfigured && JarvisPCLink.shared.hasVoice && failedAt.map { Date().timeIntervalSince($0) > 60 } ?? true }

    private var failedAt: Date?
    private var queue: [(id: Int, buffer: AVAudioPCMBuffer?, ready: Bool, deliver: (AVAudioPCMBuffer?) -> Void)] = []
    private var nextID = 0

    /// Asks the PC to say `text`; `deliver` runs on the main queue, in the order of the
    /// calls, with the sound (nil: say it with the iPhone's voice).
    func render(_ text: String, deliver: @escaping (AVAudioPCMBuffer?) -> Void) {
        nextID += 1
        let id = nextID
        queue.append((id: id, buffer: nil, ready: false, deliver: deliver))
        JarvisPCLink.shared.speech(text) { [weak self] data in
            guard let self, let index = self.queue.firstIndex(where: { $0.id == id }) else { return }
            let buffer = data.flatMap(Self.pcmBuffer(wav:))
            if buffer == nil { self.failedAt = Date() }
            self.queue[index].buffer = buffer
            self.queue[index].ready = true
            self.flush()
        }
    }

    /// Drops what was still expected (an interruption, a new reply).
    func cancelAll() {
        queue = []
    }

    private func flush() {
        while let first = queue.first, first.ready {
            queue.removeFirst()
            first.deliver(first.buffer)
        }
    }

    /// A 16-bit PCM WAV file (what the PC sends) as a buffer the conversation audio plays.
    static func pcmBuffer(wav data: Data) -> AVAudioPCMBuffer? {
        let bytes = [UInt8](data)
        func u16(_ at: Int) -> Int { Int(bytes[at]) | Int(bytes[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        guard bytes.count > 44, bytes[0..<4].elementsEqual("RIFF".utf8), bytes[8..<12].elementsEqual("WAVE".utf8) else { return nil }
        var offset = 12
        var channels = 0, rate = 0, bits = 0
        while offset + 8 <= bytes.count {
            let size = u32(offset + 4)
            let body = offset + 8
            if bytes[offset..<offset + 4].elementsEqual("fmt ".utf8), body + 16 <= bytes.count {
                channels = u16(body + 2)
                rate = u32(body + 4)
                bits = u16(body + 14)
            } else if bytes[offset..<offset + 4].elementsEqual("data".utf8) {
                guard channels == 1, bits == 16, rate > 0 else { return nil }
                let count = min(size, bytes.count - body) / 2
                guard count > 0, let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: Double(rate), channels: 1, interleaved: true),
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
                      let target = buffer.int16ChannelData?[0] else { return nil }
                buffer.frameLength = AVAudioFrameCount(count)
                bytes.withUnsafeBufferPointer { source in
                    let raw = UnsafeRawPointer(source.baseAddress! + body)
                    for index in 0..<count {
                        target[index] = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))
                    }
                }
                return buffer
            }
            offset = body + size + (size % 2)
        }
        return nil
    }
}
