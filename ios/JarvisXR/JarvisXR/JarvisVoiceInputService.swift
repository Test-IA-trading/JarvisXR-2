import AVFoundation
import Foundation
import Speech
import UIKit

/// User-visible stages of one dictation turn. The root screen maps them to the
/// discreet "micro actif / son reçu / texte compris / réponse" indicator.
enum JarvisVoiceInputState: Equatable {
    case standby
    /// Permissions granted, audio session and engine running: the microphone is live.
    case listening
    /// At least one buffer above the speech-level threshold reached the recognizer.
    case hearingSound
    case heardYou(String)
    case processing
    /// The turn ended without recognised words, and no technical failure explains it.
    case noSpeech
    case unavailable(JarvisVoiceFailure)
}

/// A failure that stopped a dictation turn. `message` is French and actionable;
/// `diagnostic` keeps the technical cause (domain/code) without any audio or transcript.
struct JarvisVoiceFailure: Equatable {
    enum Kind: String {
        case microphoneDenied
        case speechDenied
        case speechRestricted
        case recognizerUnavailable
        case audioSessionFailed
        case invalidInputFormat
        case audioEngineFailed
        case noAudioBuffers
        case silentInput
        case dictationDisabled
        case languageAssetsMissing
        case recognitionFailed
        case interrupted
    }

    let kind: Kind
    let message: String
    let diagnostic: String

    var offersSettings: Bool {
        switch kind {
        case .microphoneDenied, .speechDenied, .silentInput, .dictationDisabled:
            return true
        default:
            return false
        }
    }

    static func make(_ kind: Kind, diagnostic: String = "") -> JarvisVoiceFailure {
        JarvisVoiceFailure(kind: kind, message: message(for: kind), diagnostic: diagnostic.isEmpty ? kind.rawValue : diagnostic)
    }

    static func message(for kind: Kind) -> String {
        switch kind {
        case .microphoneDenied:
            return "Accès au micro refusé. Activez-le dans Réglages > JarvisXR > Micro."
        case .speechDenied:
            return "Reconnaissance vocale refusée. Activez-la dans Réglages > JarvisXR > Reconnaissance vocale."
        case .speechRestricted:
            return "La reconnaissance vocale est restreinte sur cet iPhone (Temps d'écran ou profil)."
        case .recognizerUnavailable:
            return "La reconnaissance du français est indisponible pour le moment. Réessayez dans un instant ou utilisez le clavier."
        case .audioSessionFailed:
            return "Le micro n'a pas pu être ouvert. Fermez les apps qui l'utilisent (appel, enregistrement) puis réessayez."
        case .invalidInputFormat:
            return "Aucune entrée micro utilisable. Débranchez les écouteurs ou fermez les apps qui utilisent le micro, puis réessayez."
        case .audioEngineFailed:
            return "Le moteur audio n'a pas démarré. Réessayez ; si cela persiste, relancez JarvisXR."
        case .noAudioBuffers:
            return "Le micro ne transmet aucun flux audio. Réessayez ; si cela persiste, relancez JarvisXR."
        case .silentInput:
            return "Le micro transmet un silence total. Vérifiez Réglages > JarvisXR > Micro, puis réessayez."
        case .dictationDisabled:
            return "La dictée est désactivée. Activez-la dans Réglages > Général > Clavier > Activer la dictée."
        case .languageAssetsMissing:
            return "Les ressources de reconnaissance du français ne sont pas installées. Connectez-vous à Internet une fois, puis réessayez."
        case .recognitionFailed:
            return "La reconnaissance vocale a échoué. Réessayez ou utilisez le clavier."
        case .interrupted:
            return "Écoute interrompue par un autre son (appel, alarme…). Touchez l'orbe pour reprendre."
        }
    }

    /// Classifies an error delivered by `SFSpeechRecognitionTask`.
    /// Returns `nil` when the error only means "no words" or "cancelled": those turns are
    /// not technical failures and must keep the transcript or end as `.noSpeech`.
    static func fromRecognitionError(_ error: Error) -> JarvisVoiceFailure? {
        let nsError = error as NSError
        let diagnostic = "\(nsError.domain) \(nsError.code)"
        switch (nsError.domain, nsError.code) {
        case ("kAFAssistantErrorDomain", 1110), // No speech detected
             ("kAFAssistantErrorDomain", 216),  // Request cancelled
             ("kAFAssistantErrorDomain", 203),  // Retry / nothing usable recognised
             ("kLSRErrorDomain", 301):          // Request was cancelled
            return nil
        case ("kLSRErrorDomain", 201), ("kAFAssistantErrorDomain", 1700):
            return make(.dictationDisabled, diagnostic: diagnostic)
        case ("kLSRErrorDomain", 102), ("kLSRErrorDomain", 300):
            return make(.languageAssetsMissing, diagnostic: diagnostic)
        default:
            return make(.recognitionFailed, diagnostic: diagnostic)
        }
    }
}

/// Measures microphone buffers without keeping them. Distinguishes a live but quiet
/// room from a digitally silent input (all-zero samples), which iOS delivers when the
/// microphone is denied or the audio session was taken away.
struct JarvisVoiceSignalMeter {
    /// RMS level, in dBFS, above which a buffer counts as "son reçu".
    static let soundThresholdDecibels: Float = -50

    private(set) var bufferCount = 0
    private(set) var nonZeroBufferCount = 0
    private(set) var soundBufferCount = 0
    private(set) var peakDecibels: Float = -160

    var hasReceivedBuffers: Bool { bufferCount > 0 }
    var isDigitallySilent: Bool { bufferCount > 0 && nonZeroBufferCount == 0 }
    var hasHeardSound: Bool { soundBufferCount > 0 }

    /// Returns a 0...1 level for display.
    @discardableResult
    mutating func ingest(_ samples: UnsafeBufferPointer<Float>) -> Float {
        bufferCount += 1
        guard !samples.isEmpty else { return 0 }
        var sumOfSquares: Float = 0
        var anyNonZero = false
        for sample in samples {
            if sample != 0 { anyNonZero = true }
            sumOfSquares += sample * sample
        }
        if anyNonZero { nonZeroBufferCount += 1 }
        let rms = (sumOfSquares / Float(samples.count)).squareRoot()
        let decibels = rms > 0 ? 20 * log10(rms) : -160
        peakDecibels = max(peakDecibels, decibels)
        if decibels > Self.soundThresholdDecibels { soundBufferCount += 1 }
        return min(max((decibels + 60) / 60, 0), 1)
    }

    @discardableResult
    mutating func ingest(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { ingest($0) }
    }
}

/// Push-to-talk dictation in French. Main-thread owned: every public entry point and
/// every callback runs on the main queue. Each turn carries a generation number so a
/// late callback from a previous recognition task can never end or duplicate a new turn.
final class JarvisVoiceInputService: NSObject {
    static let shared = JarvisVoiceInputService()

    var onStateChange: ((JarvisVoiceInputState) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    /// Microphone level in 0...1, throttled, only while listening.
    var onInputLevel: ((Float) -> Void)?

    let locale: Locale
    // Created on the first turn, not at launch: building a recognizer talks to the
    // speech service, which must never delay the first frame of the app.
    private lazy var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: locale)
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastTranscript = ""
    private var listenStartedAt: Date?
    private var silenceTimer: Timer?
    private var maxListenTimer: Timer?
    private var noSpeechTimer: Timer?
    private var bufferWatchdog: Timer?
    private var generation = 0
    private var capturing = false
    private var starting = false
    private var meter = JarvisVoiceSignalMeter()
    private var reportedSound = false
    private var preferServerRecognition = false

    /// Short mid-sentence pauses must not end the turn.
    let silenceAfterSpeech: TimeInterval = 1.6
    let minimumListenDuration: TimeInterval = 0.8
    let maximumListenDuration: TimeInterval
    let noSpeechTimeout: TimeInterval = 7.0
    let bufferWatchdogDelay: TimeInterval = 1.5

    /// Last technical facts of a turn, for Diagnostics. Never contains audio or words.
    private(set) var lastDiagnostic = "Aucune écoute depuis le lancement."

    var isListening: Bool { capturing || starting }

    var currentTranscript: String { lastTranscript }

    var usesOnDeviceRecognition: Bool {
        guard let recognizer else { return false }
        return recognizer.supportsOnDeviceRecognition && !preferServerRecognition
    }

    init(locale: Locale = Locale(identifier: "fr-FR"), maximumListenDuration: TimeInterval = 30) {
        self.locale = locale
        self.maximumListenDuration = maximumListenDuration
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption(_:)), name: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(handleMediaServicesReset), name: AVAudioSession.mediaServicesWereResetNotification, object: AVAudioSession.sharedInstance())
        NotificationCenter.default.addObserver(self, selector: #selector(handleWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggleListening() {
        isListening ? stopListening(process: true) : startListening()
    }

    /// Checks both permissions in order (speech recognition, then microphone), asking
    /// only when iOS has not decided yet, then opens the microphone.
    func startListening() {
        guard !isListening else { return }
        starting = true
        generation += 1
        let turn = generation

        guard let recognizer else {
            fail(.make(.recognizerUnavailable, diagnostic: "SFSpeechRecognizer nil for \(locale.identifier)"), turn: turn)
            return
        }

        requestSpeechAuthorization { [weak self] speechStatus in
            guard let self, self.generation == turn, self.starting else { return }
            switch speechStatus {
            case .authorized:
                break
            case .denied:
                self.fail(.make(.speechDenied), turn: turn); return
            case .restricted:
                self.fail(.make(.speechRestricted), turn: turn); return
            case .notDetermined:
                self.fail(.make(.speechDenied, diagnostic: "speech authorization still notDetermined"), turn: turn); return
            @unknown default:
                self.fail(.make(.speechDenied, diagnostic: "speech authorization unknown"), turn: turn); return
            }
            self.requestMicrophonePermission { [weak self] granted in
                guard let self, self.generation == turn, self.starting else { return }
                guard granted else {
                    self.fail(.make(.microphoneDenied), turn: turn)
                    return
                }
                guard recognizer.isAvailable else {
                    self.fail(.make(.recognizerUnavailable, diagnostic: "recognizer.isAvailable == false (\(self.locale.identifier))"), turn: turn)
                    return
                }
                self.beginAudioRecognition(with: recognizer, turn: turn)
            }
        }
    }

    /// `process: true` ends the dictation and sends what was understood;
    /// `process: false` cancels the turn without running any command.
    func stopListening(process: Bool = true) {
        guard isListening else { return }
        if starting && !capturing {
            // Still waiting on a permission prompt: there is nothing to process yet.
            starting = false
            generation += 1
            onStateChange?(.standby)
            return
        }
        finishRecognition(process: process, turn: generation)
    }

    func cancel() {
        generation += 1
        starting = false
        tearDownAudio(endRequest: true, cancelTask: true)
        lastTranscript = ""
        onStateChange?(.standby)
    }

    // MARK: - Permissions

    private func requestSpeechAuthorization(_ completion: @escaping (SFSpeechRecognizerAuthorizationStatus) -> Void) {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else {
            completion(current)
            return
        }
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status) }
        }
    }

    private func requestMicrophonePermission(_ completion: @escaping (Bool) -> Void) {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            AVAudioApplication.requestRecordPermission { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        @unknown default:
            completion(false)
        }
    }

    // MARK: - Capture

    private func beginAudioRecognition(with recognizer: SFSpeechRecognizer, turn: Int) {
        clearTimers()
        task?.cancel()
        task = nil
        lastTranscript = ""
        meter = JarvisVoiceSignalMeter()
        reportedSound = false
        listenStartedAt = Date()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            // `.duckOthers` is only valid with play-and-record style categories; with
            // `.record` iOS may reject it. `.defaultToSpeaker` keeps Jarvis's reply on the
            // loudspeaker if it starts before the session is released.
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            let nsError = error as NSError
            fail(.make(.audioSessionFailed, diagnostic: "AVAudioSession \(nsError.code)"), turn: turn)
            return
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            fail(.make(.invalidInputFormat, diagnostic: "input format \(format.sampleRate) Hz / \(format.channelCount) ch"), turn: turn)
            return
        }

        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        recognitionRequest.contextualStrings = ["Jarvis", "JARVIS"]
        let onDevice = recognizer.supportsOnDeviceRecognition && !preferServerRecognition
        recognitionRequest.requiresOnDeviceRecognition = onDevice
        request = recognitionRequest

        inputNode.removeTap(onBus: 0)
        var levelCounter = 0
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            var local = JarvisVoiceSignalMeter()
            let level = local.ingest(samples)
            let nonZero = local.nonZeroBufferCount > 0
            let sound = local.hasHeardSound
            let peak = local.peakDecibels
            levelCounter += 1
            let publishLevel = levelCounter % 3 == 0
            DispatchQueue.main.async {
                guard let self, self.generation == turn, self.capturing else { return }
                self.meter.record(nonZero: nonZero, sound: sound, peakDecibels: peak)
                if sound && !self.reportedSound {
                    self.reportedSound = true
                    self.onStateChange?(.hearingSound)
                }
                if publishLevel { self.onInputLevel?(level) }
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            let nsError = error as NSError
            fail(.make(.audioEngineFailed, diagnostic: "AVAudioEngine \(nsError.code)"), turn: turn)
            return
        }
        audioEngine = engine
        starting = false
        capturing = true
        lastDiagnostic = "Écoute \(locale.identifier), moteur \(onDevice ? "local (sur l'iPhone)" : "Apple en ligne"), \(Int(format.sampleRate)) Hz, entrée \(audioSession.currentRoute.inputs.first?.portType.rawValue ?? "inconnue")."

        onStateChange?(.listening)
        startEndpointTimers(turn: turn)

        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                guard let self, self.generation == turn, self.capturing else { return }
                if let transcript {
                    self.lastTranscript = transcript
                    self.onPartialTranscript?(transcript)
                    if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.scheduleSilenceEndpoint(turn: turn)
                    }
                }
                if isFinal {
                    self.finishRecognition(process: true, turn: turn)
                    return
                }
                if let error {
                    let hasText = !self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if let failure = JarvisVoiceFailure.fromRecognitionError(error), !hasText {
                        if onDevice && failure.kind != .dictationDisabled {
                            // The local French model failed: let the next turn use Apple's server engine.
                            self.preferServerRecognition = true
                        }
                        self.fail(failure, turn: turn)
                    } else {
                        self.finishRecognition(process: true, turn: turn)
                    }
                }
            }
        }
    }

    private func finishRecognition(process: Bool, turn: Int) {
        guard turn == generation, capturing else { return }
        generation += 1
        let final = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        let silent = meter.isDigitallySilent
        let noBuffers = !meter.hasReceivedBuffers
        let heardSound = meter.hasHeardSound
        let peak = meter.peakDecibels
        tearDownAudio(endRequest: true, cancelTask: !process || final.isEmpty)
        lastTranscript = ""

        if !process {
            onStateChange?(.standby)
        } else if !final.isEmpty {
            lastDiagnostic += " Texte reçu."
            onStateChange?(.heardYou(final))
            onStateChange?(.processing)
            onFinalTranscript?(final)
        } else if noBuffers {
            onStateChange?(.unavailable(.make(.noAudioBuffers)))
        } else if silent {
            onStateChange?(.unavailable(.make(.silentInput)))
        } else {
            lastDiagnostic += heardSound
                ? " Son reçu (pic \(Int(peak)) dB) mais aucun mot reconnu."
                : " Niveau trop faible (pic \(Int(peak)) dB)."
            onStateChange?(.noSpeech)
        }
    }

    private func fail(_ failure: JarvisVoiceFailure, turn: Int) {
        guard turn == generation else { return }
        generation += 1
        starting = false
        tearDownAudio(endRequest: true, cancelTask: true)
        lastTranscript = ""
        lastDiagnostic = "Échec : \(failure.diagnostic)."
        onStateChange?(.unavailable(failure))
    }

    private func tearDownAudio(endRequest: Bool, cancelTask: Bool) {
        clearTimers()
        if let engine = audioEngine {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        audioEngine = nil
        if endRequest { request?.endAudio() }
        if cancelTask { task?.cancel() } else { task?.finish() }
        request = nil
        task = nil
        let wasCapturing = capturing
        capturing = false
        starting = false
        if wasCapturing {
            // Release the microphone before any reply is spoken so the speech service can
            // take the session with its own playback category.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Endpointing

    private func startEndpointTimers(turn: Int) {
        noSpeechTimer = Timer.scheduledTimer(withTimeInterval: noSpeechTimeout, repeats: false) { [weak self] _ in
            guard let self, self.generation == turn else { return }
            if self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.finishRecognition(process: true, turn: turn)
            }
        }
        maxListenTimer = Timer.scheduledTimer(withTimeInterval: maximumListenDuration, repeats: false) { [weak self] _ in
            self?.finishRecognition(process: true, turn: turn)
        }
        bufferWatchdog = Timer.scheduledTimer(withTimeInterval: bufferWatchdogDelay, repeats: false) { [weak self] _ in
            guard let self, self.generation == turn, self.capturing else { return }
            if !self.meter.hasReceivedBuffers {
                self.fail(.make(.noAudioBuffers), turn: turn)
            }
        }
    }

    private func scheduleSilenceEndpoint(turn: Int) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceAfterSpeech, repeats: false) { [weak self] _ in
            guard let self, self.generation == turn else { return }
            let elapsed = Date().timeIntervalSince(self.listenStartedAt ?? Date())
            if elapsed < self.minimumListenDuration {
                self.scheduleSilenceEndpoint(turn: turn)
            } else {
                self.finishRecognition(process: true, turn: turn)
            }
        }
    }

    private func clearTimers() {
        silenceTimer?.invalidate()
        maxListenTimer?.invalidate()
        noSpeechTimer?.invalidate()
        bufferWatchdog?.invalidate()
        silenceTimer = nil
        maxListenTimer = nil
        noSpeechTimer = nil
        bufferWatchdog = nil
    }

    // MARK: - System events

    @objc private func handleInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.capturing else { return }
            if self.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.fail(.make(.interrupted), turn: self.generation)
            } else {
                self.finishRecognition(process: true, turn: self.generation)
            }
        }
    }

    @objc private func handleRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.capturing else { return }
            // The input format can change with the route; end this turn cleanly.
            self.finishRecognition(process: true, turn: self.generation)
        }
    }

    @objc private func handleMediaServicesReset() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isListening else { return }
            self.fail(.make(.audioEngineFailed, diagnostic: "mediaServicesWereReset"), turn: self.generation)
        }
    }

    @objc private func handleWillResignActive() {
        DispatchQueue.main.async { [weak self] in
            // A permission prompt also resigns the app: only stop an open microphone,
            // never a turn that is waiting for the user's answer to iOS.
            guard let self, self.capturing else { return }
            self.stopListening(process: false)
        }
    }
}

extension JarvisVoiceSignalMeter {
    /// Merges the summary of one buffer measured on the audio thread.
    mutating func record(nonZero: Bool, sound: Bool, peakDecibels: Float) {
        bufferCount += 1
        if nonZero { nonZeroBufferCount += 1 }
        if sound { soundBufferCount += 1 }
        self.peakDecibels = max(self.peakDecibels, peakDecibels)
    }
}
