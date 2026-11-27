import ActivityKit
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

    enum ListeningMode: Equatable {
        /// A request: ends after a short silence, 7 s without speech, or 30 s.
        case command
        /// Waiting for « Jarvis » (Réveil par la voix): long turns, on-device recognition
        /// only, other audio not ducked; the turn ends after the request that follows
        /// « Jarvis », and the home screen starts the next one.
        case wake
    }

    var onStateChange: ((JarvisVoiceInputState) -> Void)?
    var onPartialTranscript: ((String) -> Void)?
    var onFinalTranscript: ((String) -> Void)?
    /// Two hand claps heard while waiting for « Jarvis » (option of the wake word).
    var onDoubleClap: (() -> Void)?
    /// Mode of the current or last turn.
    private(set) var mode: ListeningMode = .command
    let wakeListenDuration: TimeInterval = 50
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
    /// This turn listens through the conversation audio (echo cancellation), whose
    /// microphone stays open between turns (JarvisDuplexAudio).
    private var duplexTurn = false
    /// The user may have started speaking over Jarvis (conversation audio only).
    var onPossibleBargeIn: (() -> Void)?

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
        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStopBackgroundWatch), name: StopBackgroundWatchIntent.notification, object: nil)
        // The button may run in the widget extension: its Darwin notification is turned into the app's own.
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), nil, { _, _, _, _, _ in
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: StopBackgroundWatchIntent.notification, object: nil)
            }
        }, StopBackgroundWatchIntent.darwinName as CFString, nil, .deliverImmediately)
        JarvisDuplexAudio.shared.listener.setBargeInHandler { [weak self] in
            self?.onPossibleBargeIn?()
        }
        JarvisDuplexAudio.shared.onStopped = { [weak self] in
            // iOS took the conversation audio (a call, another route): end this turn cleanly.
            guard let self, self.duplexTurn, self.capturing else { return }
            self.finishRecognition(process: true, turn: self.generation)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func toggleListening() {
        isListening ? stopListening(process: true) : startListening()
    }

    /// Checks both permissions in order (speech recognition, then microphone), asking
    /// only when iOS has not decided yet, then opens the microphone.
    func startListening(mode: ListeningMode = .command) {
        guard !isListening else { return }
        self.mode = mode
        if mode == .wake {
            // Waiting for « Jarvis » and the claps uses the plain microphone (no echo cancellation).
            closeConversationAudio()
        }
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
                // Waiting for « Jarvis » never streams the room's sound to a server.
                guard self.mode == .command || recognizer.supportsOnDeviceRecognition else {
                    self.fail(.make(.recognizerUnavailable, diagnostic: "wake word needs on-device recognition"), turn: turn)
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
        duplexTurn = false

        // A request in conversation: the microphone already open, with echo cancellation.
        if mode == .command, openConversationAudio() {
            beginConversationRecognition(with: recognizer, turn: turn)
            return
        }
        // The background watch keeps one microphone open, without echo cancellation.
        if mode == .wake, JarvisWakeWordSettings.watchesInBackground, openWatchAudio() {
            beginConversationRecognition(with: recognizer, turn: turn)
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            // `.duckOthers` is only valid with play-and-record style categories; with
            // `.record` iOS may reject it. `.defaultToSpeaker` keeps Jarvis's reply on the
            // loudspeaker if it starts before the session is released.
            // Waiting for « Jarvis » must not lower the user's music for minutes on end.
            let options: AVAudioSession.CategoryOptions = mode == .wake ? [.mixWithOthers, .defaultToSpeaker] : [.duckOthers, .defaultToSpeaker]
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: options)
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

        let (recognitionRequest, onDevice) = makeRequest(for: recognizer)
        request = recognitionRequest

        inputNode.removeTap(onBus: 0)
        var levelCounter = 0
        // Only the level of each 10 ms is measured, on the audio thread; nothing is kept.
        let clapDetector: JarvisClapDetectorBox? = mode == .wake && JarvisWakeWordSettings.clapsEnabled
            ? JarvisClapDetectorBox(sampleRate: format.sampleRate)
            : nil
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self, weak recognitionRequest] buffer, _ in
            recognitionRequest?.append(buffer)
            guard let channel = buffer.floatChannelData?[0] else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            if let clapDetector, clapDetector.ingest(samples) {
                DispatchQueue.main.async {
                    guard let self, self.generation == turn, self.capturing else { return }
                    self.onDoubleClap?()
                }
            }
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
        startRecognitionTask(with: recognizer, request: recognitionRequest, onDevice: onDevice, turn: turn)
    }

    /// The speech request of a turn: French, partial results as they come, punctuation (it
    /// helps to hear the end of a sentence), and the words the recognizer must not miss.
    private func makeRequest(for recognizer: SFSpeechRecognizer) -> (SFSpeechAudioBufferRecognitionRequest, Bool) {
        let recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.addsPunctuation = true
        recognitionRequest.taskHint = .dictation
        recognitionRequest.contextualStrings = Self.contextualStrings
        let onDevice = mode == .wake || (recognizer.supportsOnDeviceRecognition && !preferServerRecognition)
        recognitionRequest.requiresOnDeviceRecognition = onDevice
        return (recognitionRequest, onDevice)
    }

    /// Words of Jarvis's commands that a general recognizer tends to write otherwise.
    static let contextualStrings = [
        "Jarvis", "JARVIS", "Jarvis PC", "sur le PC", "YouTube", "Spotify", "Netflix", "Wikipédia", "minuteur", "rappelle-moi",
        "envoie un message", "prends une note", "souviens-toi", "c'est tout",
    ]

    /// Same handling for both microphones: the text so far, the end of the turn, the errors.
    private func startRecognitionTask(with recognizer: SFSpeechRecognizer, request recognitionRequest: SFSpeechAudioBufferRecognitionRequest, onDevice: Bool, turn: Int) {
        task = recognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            let transcript = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                guard let self, self.generation == turn, self.capturing else { return }
                if let transcript {
                    self.lastTranscript = transcript
                    self.onPartialTranscript?(transcript)
                    // While waiting for « Jarvis », other voices (a TV, a conversation)
                    // do not end the turn: only the request that follows the wake word does.
                    let addressed = self.mode == .command || JarvisWakeWord.command(in: transcript) != nil
                    if addressed, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                        if onDevice && failure.kind != .dictationDisabled && self.mode == .command {
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

    // MARK: - Conversation audio (echo cancellation)

    /// The conversation's microphone stays open, with Apple's echo cancellation, so the
    /// user can interrupt Jarvis by speaking (Réglages › Voix › Interrompre Jarvis en parlant).
    var usesConversationAudio: Bool { JarvisDuplexAudio.shared.isRunning }

    /// The microphone hears the user over Jarvis's voice (echo cancellation on).
    var hearsOverJarvis: Bool { JarvisDuplexAudio.shared.isRunning && JarvisDuplexAudio.shared.usesVoiceProcessing }

    /// Opens the conversation audio when the setting allows it. False keeps the classic
    /// microphone, opened for each turn (setting off, or failure). In the background, the
    /// microphone the watch keeps open is used as it is (iOS does not let it start again).
    @discardableResult
    func openConversationAudio() -> Bool {
        let audio = JarvisDuplexAudio.shared
        let onScreen = UIApplication.shared.applicationState == .active
        if audio.isRunning {
            // On screen, the watch's plain microphone gives way to echo cancellation.
            guard onScreen, !audio.usesVoiceProcessing, JarvisConversationSettings.interruptsByVoice, !(capturing && duplexTurn) else { return true }
            audio.stop()
        }
        guard JarvisConversationSettings.interruptsByVoice, onScreen else { return false }
        // The plain microphone of the wake word must be closed first.
        guard audioEngine == nil else { return false }
        let opened = audio.start(voiceRate: JarvisSpeechService.shared.voiceSampleRate, voiceProcessing: true)
        lastDiagnostic = opened
            ? "Son de conversation ouvert (annulation d'écho) : vous pouvez interrompre Jarvis en parlant."
            : "Son de conversation indisponible (\(audio.lastFailure ?? "cause inconnue")) : micro classique."
        if !opened, JarvisWakeWordSettings.watchesInBackground {
            // Without echo cancellation, the watch's microphone still serves the conversation.
            return openWatchAudio()
        }
        return opened
    }

    /// The microphone of the background watch: plain (the claps are heard best without echo
    /// cancellation) and kept open, so the watch goes on once Jarvis leaves the screen.
    @discardableResult
    func openWatchAudio() -> Bool {
        let audio = JarvisDuplexAudio.shared
        let onScreen = UIApplication.shared.applicationState == .active
        if audio.isRunning {
            guard onScreen, audio.usesVoiceProcessing, !(capturing && duplexTurn) else { return true }
            audio.stop()
        }
        guard onScreen, audioEngine == nil else { return false }
        let opened = audio.start(voiceRate: JarvisSpeechService.shared.voiceSampleRate, voiceProcessing: false)
        if !opened {
            lastDiagnostic = "Micro de veille indisponible (\(audio.lastFailure ?? "cause inconnue"))."
        }
        return opened
    }

    /// Closes the conversation audio, unless a turn is listening through it. With the
    /// background watch on, the microphone stays open (plain again, on screen).
    func closeConversationAudio() {
        let audio = JarvisDuplexAudio.shared
        guard audio.isRunning, !(capturing && duplexTurn) else { return }
        if JarvisWakeWordSettings.watchesInBackground {
            if audio.usesVoiceProcessing, UIApplication.shared.applicationState == .active {
                openWatchAudio()
            }
            return
        }
        audio.stop()
    }

    /// Two claps call Jarvis whatever it is doing (listening, speaking, idle), as long as the
    /// conversation audio is open; `always` arms them even with the claps setting off.
    private func armClaps(always: Bool) {
        let audio = JarvisDuplexAudio.shared
        let on = always || JarvisWakeWordSettings.clapsEnabled
        audio.listener.detectClaps(sampleRate: on ? audio.microphoneSampleRate : nil) { [weak self] in
            self?.onDoubleClap?()
        }
    }

    /// The on-device recognizer failed off screen once: until the next return to the
    /// background, only the claps are listened to there.
    private var wakeRecognitionFailedOffScreen = false
    /// When the app left the screen, or the last request off screen was heard.
    private var lastBackgroundUse = Date()

    /// In the background, on the microphone kept open: « Jarvis » (on-device recognition,
    /// nothing leaves the iPhone) and the two claps; only the claps when the recognizer is
    /// not allowed off screen. False when the microphone is not open (iOS does not let an
    /// app open it from the background).
    @discardableResult
    func startBackgroundWatch() -> Bool {
        guard JarvisWakeWordSettings.watchesInBackground, JarvisDuplexAudio.shared.isRunning else { return false }
        if capturing || starting {
            // A request being said goes on, and so does a wait for « Jarvis ».
            return mode == .wake
        }
        let recent = Date().timeIntervalSince(lastBackgroundUse) < JarvisWakeWordSettings.backgroundRecognitionWindow
        if !wakeRecognitionFailedOffScreen, recent {
            startListening(mode: .wake)
            if isListening { return true }
        }
        return startClapsOnlyWatch()
    }

    /// Only the two claps, without speech recognition.
    @discardableResult
    private func startClapsOnlyWatch() -> Bool {
        guard JarvisDuplexAudio.shared.isRunning else { return false }
        if capturing || starting { cancel() }
        clearTimers()
        mode = .wake
        generation += 1
        lastTranscript = ""
        meter = JarvisVoiceSignalMeter()
        duplexTurn = true
        starting = false
        capturing = true
        JarvisDuplexAudio.shared.listener.detach()
        armClaps(always: true)
        lastDiagnostic = "Veille en arrière-plan : seuls les deux clappements sont écoutés, rien n'est enregistré."
        onStateChange?(.listening)
        return true
    }

    /// Listens for the user speaking over Jarvis while it talks (`onPossibleBargeIn`).
    func monitorBargeIn(_ on: Bool) {
        JarvisDuplexAudio.shared.listener.monitor(on && JarvisDuplexAudio.shared.isRunning)
    }

    private func beginConversationRecognition(with recognizer: SFSpeechRecognizer, turn: Int) {
        let (recognitionRequest, onDevice) = makeRequest(for: recognizer)
        request = recognitionRequest
        duplexTurn = true
        let counter = JarvisLevelCounter()
        let listener = JarvisDuplexAudio.shared.listener
        listener.setLevelHandler { [weak self] level, nonZero, sound, peak in
            let publishLevel = counter.next() % 3 == 0
            DispatchQueue.main.async {
                guard let self, self.generation == turn, self.capturing, self.duplexTurn else { return }
                self.meter.record(nonZero: nonZero, sound: sound, peakDecibels: peak)
                if sound && !self.reportedSound {
                    self.reportedSound = true
                    self.onStateChange?(.hearingSound)
                }
                if publishLevel { self.onInputLevel?(level) }
            }
        }
        // The last second heard comes first: words said as the turn started are kept,
        // unless it may hold Jarvis's own voice (plain microphone, Jarvis just spoke).
        listener.attach(recognitionRequest, withPreRoll: JarvisDuplexAudio.shared.preRollIsFreeOfJarvis)
        armClaps(always: false)
        starting = false
        capturing = true
        let audio = JarvisDuplexAudio.shared
        let echo = audio.usesVoiceProcessing ? "son de conversation (annulation d'écho)" : "micro de veille"
        let recovered = audio.recoveries > 0 ? ", micro relancé \(audio.recoveries) fois après un changement audio" : ""
        let place = UIApplication.shared.applicationState == .active ? "" : ", en arrière-plan"
        lastDiagnostic = "Écoute \(locale.identifier), moteur \(onDevice ? "local (sur l'iPhone)" : "Apple en ligne"), \(echo)\(recovered)\(place)."
        onStateChange?(.listening)
        startEndpointTimers(turn: turn)
        startRecognitionTask(with: recognizer, request: recognitionRequest, onDevice: onDevice, turn: turn)
    }

    private static let fillers: Set<String> = ["euh", "heu", "hum", "hmm", "mmh", "mm", "ah", "oh", "bah", "ben", "pff"]

    /// Only hesitation sounds, which the recognizer writes for a breath or a noise.
    static func isOnlyFiller(_ text: String) -> Bool {
        let words = text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
        return !words.isEmpty && words.allSatisfy { fillers.contains($0) }
    }

    private func finishRecognition(process: Bool, turn: Int) {
        guard turn == generation, capturing else { return }
        generation += 1
        var final = lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        // A noise written as « Euh. » or « Hum » is not a request.
        if Self.isOnlyFiller(final) { final = "" }
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
            if UIApplication.shared.applicationState != .active { lastBackgroundUse = Date() }
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
        if mode == .wake, UIApplication.shared.applicationState != .active {
            wakeRecognitionFailedOffScreen = true
        }
        tearDownAudio(endRequest: true, cancelTask: true)
        lastTranscript = ""
        lastDiagnostic = "Échec : \(failure.diagnostic)."
        onStateChange?(.unavailable(failure))
    }

    private func tearDownAudio(endRequest: Bool, cancelTask: Bool) {
        clearTimers()
        let conversationTurn = duplexTurn
        if conversationTurn {
            // The conversation audio stays open for the reply and the next turn: only this
            // turn's request stops receiving the microphone.
            // The claps stay heard between turns (armClaps): they call Jarvis at any moment.
            JarvisDuplexAudio.shared.listener.detach()
            JarvisDuplexAudio.shared.listener.setLevelHandler(nil)
        } else if let engine = audioEngine {
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
        duplexTurn = false
        if wasCapturing && !conversationTurn {
            // Release the microphone before any reply is spoken so the speech service can
            // take the session with its own playback category.
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    // MARK: - Endpointing

    private func startEndpointTimers(turn: Int) {
        let noSpeechTimeout = mode == .wake ? wakeListenDuration : self.noSpeechTimeout
        let maximumListenDuration = mode == .wake ? wakeListenDuration + 5 : self.maximumListenDuration
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

    /// The silence that ends this turn, from what was said so far: short after a finished
    /// sentence, longer after « et », « de » or a bare verb (JarvisTurnEndDetector).
    func silenceNeeded(after transcript: String) -> TimeInterval {
        guard mode == .wake else { return JarvisTurnEndDetector.silence(after: transcript) }
        guard let request = JarvisWakeWord.command(in: transcript) else { return silenceAfterSpeech }
        // « Jarvis ? » alone: answer « Oui ? » quickly.
        return request.isEmpty ? 1.0 : JarvisTurnEndDetector.silence(after: request)
    }

    private func scheduleSilenceEndpoint(turn: Int) {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceNeeded(after: lastTranscript), repeats: false) { [weak self] _ in
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
            // The background watch keeps waiting (it becomes claps-only in the background).
            if self.mode == .wake, self.duplexTurn, JarvisWakeWordSettings.watchesInBackground { return }
            self.stopListening(process: false)
        }
    }

    /// « Arrêter la veille » (Dynamic Island, lock screen): the setting turns off (no
    /// reactivation when Jarvis is opened again: Réglages › Veille en arrière-plan turns it
    /// back on), the microphone closes and the island goes away. Both notifications may
    /// come: the second finds nothing left to stop.
    @objc private func handleStopBackgroundWatch() {
        DispatchQueue.main.async { [weak self] in
            JarvisWakeWordSettings.worksInBackground = false
            if self?.isListening == true { self?.cancel() }
            JarvisDuplexAudio.shared.stop()
            JarvisLiveActivity.shared.stop()
            for stale in Activity<JarvisActivityAttributes>.activities {
                Task { await stale.end(nil, dismissalPolicy: .immediate) }
            }
            self?.lastDiagnostic = "Veille en arrière-plan arrêtée depuis la Dynamic Island : micro fermé."
        }
    }

    @objc private func handleDidEnterBackground() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Background watch: « Jarvis » and the claps, on the microphone kept open.
            if JarvisWakeWordSettings.watchesInBackground {
                self.wakeRecognitionFailedOffScreen = false
                self.lastBackgroundUse = Date()
                self.startBackgroundWatch()
                return
            }
            // Otherwise Jarvis does not listen in the background: the conversation audio closes.
            guard !self.capturing else { return }
            self.closeConversationAudio()
        }
    }
}

/// Counts the microphone buffers on the audio thread (one in three updates the level shown).
final class JarvisLevelCounter {
    private var count = 0

    func next() -> Int {
        count += 1
        return count
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
