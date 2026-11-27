import AVFoundation
import Speech

/// The audio of a hands-free conversation: one engine for the microphone, with Apple's
/// echo cancellation (voice processing), and for Jarvis's voice, played through the same
/// engine so the cancellation knows what to take out. The user can then speak over
/// Jarvis: the microphone hears the user, not Jarvis. The microphone also stays open
/// between turns, so the first words after Jarvis's reply are not lost.
///
/// Nothing is recorded: each microphone buffer goes to the speech recognizer and to a
/// level meter, and only the last second stays in memory (JarvisDuplexListener).
final class JarvisDuplexAudio {
    static let shared = JarvisDuplexAudio()

    /// Receives each microphone buffer, on the audio thread.
    let listener = JarvisDuplexListener()
    private(set) var isRunning = false
    /// Echo cancellation on (a conversation) or off (the claps' watch, heard best raw).
    private(set) var usesVoiceProcessing = false
    /// The microphone's sample rate while running (the clap detector needs it).
    private(set) var microphoneSampleRate: Double = 48_000
    /// Why the last start failed (Diagnostics), without any audio.
    private(set) var lastFailure: String?
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var converterInput: AVAudioFormat?
    private var configurationObserver: NSObjectProtocol?
    /// Called on the main queue when iOS stops the engine (a call, a route change).
    var onStopped: (() -> Void)?

    /// Opens the microphone, with echo cancellation when `voiceProcessing`, and Jarvis's voice
    /// output. `voiceRate` is the sample rate of the voice that will speak (its buffers are
    /// played without resampling). Without echo cancellation the user's music is not
    /// lowered (the claps' watch can last for hours). Main thread.
    @discardableResult
    func start(voiceRate: Double = 22_050, voiceProcessing: Bool = true) -> Bool {
        if isRunning { return true }
        let session = AVAudioSession.sharedInstance()
        do {
            if voiceProcessing {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            } else {
                try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            }
            try session.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            // Must come before any format is read or any node is connected.
            if voiceProcessing {
                try input.setVoiceProcessingEnabled(true)
            }
            let microphoneFormat = input.outputFormat(forBus: 0)
            guard microphoneFormat.sampleRate > 0, microphoneFormat.channelCount > 0,
                  let voiceFormat = AVAudioFormat(standardFormatWithSampleRate: voiceRate > 0 ? voiceRate : 22_050, channels: 1) else {
                lastFailure = "entrée micro \(Int(microphoneFormat.sampleRate)) Hz / \(microphoneFormat.channelCount) voie(s)"
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
                return false
            }
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: voiceFormat)
            let listener = self.listener
            input.installTap(onBus: 0, bufferSize: 1024, format: microphoneFormat) { buffer, _ in
                listener.ingest(buffer)
            }
            engine.prepare()
            try engine.start()
            player.play()
            self.engine = engine
            self.player = player
            playerFormat = voiceFormat
            converter = nil
            converterInput = nil
            isRunning = true
            usesVoiceProcessing = voiceProcessing
            microphoneSampleRate = microphoneFormat.sampleRate
            lastFailure = nil
            recentRecoveries = []
            configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
                // Turning echo cancellation on makes iOS post this right after the start: the
                // microphone is started again, never closed (that cut every turn at once).
                self?.recoverAfterConfigurationChange()
            }
            return true
        } catch {
            let nsError = error as NSError
            lastFailure = "\(nsError.domain) \(nsError.code)"
            stop()
            return false
        }
    }

    /// When Jarvis's voice was last heard through this engine (main queue).
    private(set) var lastVoiceAt = Date.distantPast

    /// The last second kept before a turn holds only the user, not Jarvis's own voice:
    /// echo cancellation takes Jarvis out, or Jarvis has been quiet long enough.
    var preRollIsFreeOfJarvis: Bool {
        usesVoiceProcessing || Date().timeIntervalSince(lastVoiceAt) > 1.5
    }

    /// Times the engine was started again after iOS changed the audio (Diagnostics).
    private(set) var recoveries = 0
    private var recentRecoveries: [Date] = []

    /// iOS changed the audio hardware or its processing and may have stopped the engine: it
    /// starts again with the microphone's new format, the turn's speech request still
    /// attached. Only when that fails, or keeps happening, is the audio closed.
    private func recoverAfterConfigurationChange() {
        guard isRunning, let engine else { return }
        if engine.isRunning { return }
        let now = Date()
        recentRecoveries = recentRecoveries.filter { now.timeIntervalSince($0) < 10 } + [now]
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard recentRecoveries.count <= 5, format.sampleRate > 0, format.channelCount > 0 else {
            lastFailure = recentRecoveries.count > 5 ? "changements audio répétés" : "entrée micro \(Int(format.sampleRate)) Hz après changement"
            stop()
            onStopped?()
            return
        }
        // Voice buffers still queued are dropped (their callbacks run) instead of waiting forever.
        player?.stop()
        let listener = self.listener
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            listener.ingest(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            player?.play()
            microphoneSampleRate = format.sampleRate
            recoveries += 1
        } catch {
            let nsError = error as NSError
            lastFailure = "redémarrage \(nsError.domain) \(nsError.code)"
            stop()
            onStopped?()
        }
    }

    /// Closes the microphone and the voice output, and gives the audio back to iOS.
    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        listener.detach()
        listener.monitor(false)
        listener.detectClaps(sampleRate: nil, handler: nil)
        listener.clearPreRoll()
        player?.stop()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        let wasRunning = isRunning
        engine = nil
        player = nil
        playerFormat = nil
        converter = nil
        converterInput = nil
        isRunning = false
        usesVoiceProcessing = false
        if wasRunning {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: Jarvis's voice

    /// Queues one buffer of Jarvis's voice after the others. `played` runs on the main
    /// queue once the buffer has been heard, or dropped by `stopVoice`. False when it
    /// cannot be played (the caller speaks the classic way instead).
    func play(_ buffer: AVAudioPCMBuffer, played: @escaping () -> Void) -> Bool {
        guard isRunning, let engine, let player, let ready = playable(buffer, engine: engine, player: player) else { return false }
        player.scheduleBuffer(ready, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            DispatchQueue.main.async {
                self?.lastVoiceAt = Date()
                played()
            }
        }
        if !player.isPlaying { player.play() }
        return true
    }

    /// Silences Jarvis at once; the buffers still queued are dropped.
    func stopVoice() {
        guard let player else { return }
        player.stop()
        player.volume = 1
        player.play()
    }

    /// Lowers Jarvis's voice while the user may be speaking over it, as a person would.
    func setVoiceLowered(_ lowered: Bool) {
        player?.volume = lowered ? 0.35 : 1
    }

    private func playable(_ buffer: AVAudioPCMBuffer, engine: AVAudioEngine, player: AVAudioPlayerNode) -> AVAudioPCMBuffer? {
        let source = buffer.format
        if playerFormat?.sampleRate != source.sampleRate || playerFormat?.channelCount != source.channelCount {
            // Another voice: the player follows its sample rate.
            guard let format = AVAudioFormat(standardFormatWithSampleRate: source.sampleRate, channels: source.channelCount) else { return nil }
            player.stop()
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            playerFormat = format
            player.play()
        }
        guard let target = playerFormat else { return nil }
        if source == target { return buffer }
        // Same rate, other sample type (16-bit integers): a plain conversion, no resampling.
        if converterInput != source {
            converter = AVAudioConverter(from: source, to: target)
            converterInput = source
        }
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: buffer.frameLength) else { return nil }
        do {
            try converter.convert(to: output, from: buffer)
        } catch {
            return nil
        }
        return output.frameLength > 0 ? output : nil
    }

    /// A copy of `buffer` that stays valid after the callback that delivered it.
    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard buffer.frameLength > 0, let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return nil }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let target = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        guard source.count == target.count else { return nil }
        for index in 0..<source.count {
            guard let from = source[index].mData, let to = target[index].mData else { return nil }
            memcpy(to, from, Int(min(source[index].mDataByteSize, target[index].mDataByteSize)))
        }
        return copy
    }
}

/// What the conversation audio's microphone feeds, on the audio thread: the speech request
/// of the current turn, the last second of sound (so the first words of a turn are not
/// lost), and the detector that hears the user speak over Jarvis.
final class JarvisDuplexListener {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollDuration: TimeInterval = 0
    private let maximumPreRoll: TimeInterval = 1.2
    private var detector = JarvisBargeInDetector()
    private var monitoring = false
    /// Level of each buffer (0...1, non-zero samples, sound heard, dB), on the audio thread.
    private var onLevel: ((Float, Bool, Bool, Float) -> Void)?
    /// The user may have started speaking over Jarvis (main queue).
    private var onPossibleBargeIn: (() -> Void)?

    func setLevelHandler(_ handler: ((Float, Bool, Bool, Float) -> Void)?) {
        lock.lock()
        onLevel = handler
        lock.unlock()
    }

    func setBargeInHandler(_ handler: (() -> Void)?) {
        lock.lock()
        onPossibleBargeIn = handler
        lock.unlock()
    }

    /// Two hand claps call Jarvis (`handler` on the main queue); nil `sampleRate` stops it.
    private var clapDetector: JarvisClapDetectorBox?
    private var onDoubleClap: (() -> Void)?

    func detectClaps(sampleRate: Double?, handler: (() -> Void)?) {
        lock.lock()
        clapDetector = sampleRate.map { JarvisClapDetectorBox(sampleRate: $0) }
        onDoubleClap = sampleRate == nil ? nil : handler
        lock.unlock()
    }

    func ingest(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
        var meter = JarvisVoiceSignalMeter()
        let level = meter.ingest(samples)
        let duration = Double(buffer.frameLength) / max(buffer.format.sampleRate, 1)
        lock.lock()
        let current = request
        if current == nil, let copy = JarvisDuplexAudio.copy(buffer) {
            preRoll.append(copy)
            preRollDuration += duration
            while preRollDuration > maximumPreRoll, preRoll.count > 1 {
                let dropped = preRoll.removeFirst()
                preRollDuration -= Double(dropped.frameLength) / max(dropped.format.sampleRate, 1)
            }
        }
        var fired = false
        if monitoring {
            fired = detector.ingest(level: meter.peakDecibels, duration: duration)
        }
        let onLevel = self.onLevel
        let onPossibleBargeIn = self.onPossibleBargeIn
        let clapDetector = self.clapDetector
        let onDoubleClap = self.onDoubleClap
        lock.unlock()
        current?.append(buffer)
        onLevel?(level, meter.nonZeroBufferCount > 0, meter.hasHeardSound, meter.peakDecibels)
        if fired, let onPossibleBargeIn {
            DispatchQueue.main.async(execute: onPossibleBargeIn)
        }
        // Only the level of each 10 ms is measured; nothing is kept.
        if let clapDetector, clapDetector.ingest(samples), let onDoubleClap {
            DispatchQueue.main.async(execute: onDoubleClap)
        }
    }

    /// The turn's speech request receives the microphone from now on, after the last second
    /// heard when `withPreRoll`.
    func attach(_ newRequest: SFSpeechAudioBufferRecognitionRequest, withPreRoll: Bool) {
        lock.lock()
        let earlier = withPreRoll ? preRoll : []
        preRoll = []
        preRollDuration = 0
        request = newRequest
        lock.unlock()
        earlier.forEach { newRequest.append($0) }
    }

    func detach() {
        lock.lock()
        request = nil
        lock.unlock()
    }

    func clearPreRoll() {
        lock.lock()
        preRoll = []
        preRollDuration = 0
        lock.unlock()
    }

    /// Listens for the user speaking over Jarvis (from the start of each reply).
    func monitor(_ on: Bool) {
        lock.lock()
        monitoring = on
        detector.reset()
        lock.unlock()
    }
}
