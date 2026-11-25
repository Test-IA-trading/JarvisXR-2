import AVFoundation

enum JarvisVoiceProfile: String {
    static let ordered: [JarvisVoiceProfile] = [.jarvis, .natural, .friendly, .crisp, .quiet, .formal]

    /// The default: a calm, measured assistant voice, a little slower and deeper than
    /// iOS's own, with a male voice preferred when one is installed. It evokes the style
    /// of a film assistant without imitating anyone's real voice.
    case jarvis
    case natural
    case friendly
    case formal
    case crisp
    case quiet

    var displayName: String {
        switch self {
        case .jarvis: return "Jarvis"
        case .natural: return "Naturelle"
        case .friendly: return "Chaleureuse"
        case .formal: return "Posée"
        case .crisp: return "Nette"
        case .quiet: return "Douce"
        }
    }
}

/// UIKit-owned speech adapter. Production callers and notification recovery enter
/// through the main thread; AVSpeechSynthesizer remains encapsulated here.
final class JarvisSpeechService: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = JarvisSpeechService()

    private let synthesizer = AVSpeechSynthesizer()
    private let enabledKey = "JarvisXR.speechEnabled"
    private let rateKey = "JarvisXR.speechRate"
    private let pitchKey = "JarvisXR.speechPitch"
    private let volumeKey = "JarvisXR.speechVolume"
    private let profileKey = "JarvisXR.voiceProfile"
    private let personalVoiceKey = "JarvisXR.preferPersonalVoice"
    private let chosenVoiceKey = "JarvisXR.chosenVoiceIdentifier"
    private var suppressNextCallbacks = false
    private var visionQueue = VisionSpeechPriorityQueue()
    private var activeVisionItem: VisionSpeechQueueItem?
    private var activeVisionUtterance: AVSpeechUtterance?
    private var visionQueuePaused = false
    private var visionWasPausedByAudioInterruption = false
    private var quietVisionGuideEnabled = false
    var onSpeechStart: (() -> Void)?
    var onSpeechFinish: (() -> Void)?

    /// Renders Jarvis's voice into buffers for the conversation audio (JarvisDuplexAudio),
    /// which plays them with echo cancellation so the user can interrupt by speaking.
    private let renderer = AVSpeechSynthesizer()
    private var duplexGeneration = 0
    private var duplexRendering = 0
    private var duplexPendingBuffers = 0
    private var duplexActive = false
    private var duplexStarted = false
    private var duplexIsStream = false
    /// What Jarvis is saying in the current reply, to tell its echo from the user's words.
    private(set) var currentReplyText = ""

    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: enabledKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
        }
    }

    var speechRate: Float {
        get {
            switch profile {
            case .jarvis: return 0.47
            case .natural: return 0.46
            case .friendly: return 0.47
            case .formal: return 0.42
            case .crisp: return 0.51
            case .quiet: return 0.38
            }
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0.35), 0.55), forKey: rateKey)
        }
    }

    var pitch: Float {
        get {
            switch profile {
            // A slight lowering only (under one semitone): larger shifts make the enhanced
            // and premium voices sound metallic, so Naturelle keeps the voice's own pitch.
            case .jarvis: return 0.95
            case .natural: return 1.0
            case .friendly: return 1.05
            case .formal: return 0.98
            case .crisp: return 1.04
            case .quiet: return 0.98
            }
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0.85), 1.08), forKey: pitchKey)
        }
    }

    var volume: Float {
        get {
            if profile == .quiet {
                return 0.58
            }
            let stored = UserDefaults.standard.float(forKey: volumeKey)
            return stored > 0 ? stored : 0.88
        }
        set {
            UserDefaults.standard.set(min(max(newValue, 0.4), 1.0), forKey: volumeKey)
        }
    }

    var profile: JarvisVoiceProfile {
        get {
            guard let raw = UserDefaults.standard.string(forKey: profileKey),
                  let value = JarvisVoiceProfile(rawValue: raw) else {
                return .jarvis
            }
            return value
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: profileKey)
        }
    }

    var prefersPersonalVoice: Bool {
        get { UserDefaults.standard.bool(forKey: personalVoiceKey) }
        set { UserDefaults.standard.set(newValue, forKey: personalVoiceKey) }
    }

    /// Voice picked in Settings; nil means the best French voice installed.
    var chosenVoiceIdentifier: String? {
        get { UserDefaults.standard.string(forKey: chosenVoiceKey) }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: chosenVoiceKey)
            } else {
                UserDefaults.standard.removeObject(forKey: chosenVoiceKey)
            }
        }
    }

    /// French voices offered in Settings, best first.
    func frenchVoiceChoices() -> [JarvisVoiceCandidate] {
        JarvisVoiceRanking.ranked(AVSpeechSynthesisVoice.speechVoices().map { JarvisVoiceCandidate($0) })
    }

    /// How to get a natural voice: Apple's enhanced and premium voices are free, work
    /// offline once downloaded, and an app cannot download them itself.
    static let betterVoiceHint = "Pour une voix bien plus naturelle, téléchargez une voix « Améliorée » ou « Premium » : Réglages iOS › Accessibilité › Contenu énoncé › Voix › Français. Jarvis la prend ensuite tout seul."

    /// Says a short sentence with one voice (nil: the automatic choice), so it can be
    /// heard before it is kept. Works even when spoken replies are off.
    func previewVoice(identifier: String?) {
        activeVisionItem = nil
        activeVisionUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = makeUtterance("Bonjour, je suis Jarvis. Voici ma voix.", profile: profile)
        if let identifier, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        suppressNextCallbacks = true
        activateAudioSession()
        synthesizer.speak(utterance)
    }

    private override init() {
        super.init()
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Begins a new vision narration scope. Starting another scope invalidates queued
    /// results from the previous mode so an old frame cannot speak after a mode change.
    @MainActor
    func beginVisionNarrationSession() -> UUID {
        let sessionID = UUID()
        let wasSpeakingVision = activeVisionItem != nil
        activeVisionItem = nil
        activeVisionUtterance = nil
        visionQueue.beginSession(sessionID)
        visionQueuePaused = false
        if wasSpeakingVision {
            synthesizer.stopSpeaking(at: .immediate)
        }
        return sessionID
    }

    @MainActor
    func setQuietVisionGuideEnabled(_ enabled: Bool) {
        quietVisionGuideEnabled = enabled
        if enabled {
            // Preserve only target and warning results already waiting to speak.
            let sessionID = visionQueue.activeSessionID
            visionQueue.cancelAll()
            if let sessionID {
                visionQueue.beginSession(sessionID)
            }
        }
    }

    @MainActor
    @discardableResult
    func enqueueVisionNarration(
        _ narration: SceneNarration,
        sessionID: UUID,
        at date: Date = Date()
    ) -> VisionSpeechEnqueueDisposition {
        guard isEnabled else { return .rejectedExpired }
        // Quiet Live Guide drops ambient descriptions but keeps confirmed changes: Live Guide
        // only emits debounced appear/move/leave events (VisionLiveGuideEngine), each once.
        if quietVisionGuideEnabled && narration.priority < .change {
            return .suppressedQuietMode
        }

        let item = VisionSpeechQueueItem(sessionID: sessionID, narration: narration)
        let disposition = visionQueue.enqueue(item, current: activeVisionItem, at: date)
        switch disposition {
        case .queued:
            speakNextVisionItemIfPossible()
        case .interruptCurrent:
            activeVisionItem = nil
            activeVisionUtterance = nil
            if synthesizer.stopSpeaking(at: .immediate) {
                DispatchQueue.main.async { [weak self] in
                    self?.speakNextVisionItemIfPossible()
                }
            } else {
                speakNextVisionItemIfPossible()
            }
        case .suppressedDuplicate, .suppressedQuietMode, .rejectedStaleSession, .rejectedExpired:
            break
        }
        return disposition
    }

    @MainActor
    func pauseVisionNarration() {
        visionQueuePaused = true
        if activeVisionItem != nil, synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
        }
    }

    @MainActor
    func resumeVisionNarration() {
        visionQueuePaused = false
        if activeVisionItem != nil, synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            speakNextVisionItemIfPossible()
        }
    }

    @MainActor
    func cancelVisionNarrationSession(_ sessionID: UUID) {
        visionQueue.cancelSession(sessionID)
        guard activeVisionItem?.sessionID == sessionID else { return }
        activeVisionItem = nil
        activeVisionUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSessionIfIdle()
    }

    @MainActor
    var lastCompletedVisionNarrationText: String? {
        visionQueue.lastCompletedText
    }

    /// When the last reply was requested and when speech actually started, for the
    /// « la voix ne démarre pas » check and Diagnostics. No text is kept.
    private(set) var lastSpeakRequestAt: Date?
    private(set) var lastSpeechStartAt: Date?

    /// True when a reply was requested more than `delay` ago and speech never started.
    func speechFailedToStart(after delay: TimeInterval, now: Date = Date()) -> Bool {
        guard let requested = lastSpeakRequestAt, now.timeIntervalSince(requested) >= delay else { return false }
        if let started = lastSpeechStartAt, started >= requested { return false }
        return !isSpeaking
    }

    var speechDiagnostic: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "HH:mm:ss"
        guard let requested = lastSpeakRequestAt else { return "aucune réponse parlée depuis le lancement" }
        if let started = lastSpeechStartAt, started >= requested {
            return String(format: "dernière réponse démarrée en %.1f s (%@)", started.timeIntervalSince(requested), formatter.string(from: started))
        }
        return "dernière réponse demandée à \(formatter.string(from: requested)), pas encore démarrée"
    }

    func speak(_ text: String, notifyState: Bool = true) {
        guard isEnabled else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        activeVisionItem = nil
        activeVisionUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        stopConversationVoice(reportFinish: false)
        let utterance = makeUtterance(text, profile: profile)
        suppressNextCallbacks = !notifyState
        if notifyState {
            lastSpeakRequestAt = Date()
        }
        currentReplyText = text
        // In a conversation, the voice goes through the echo-cancelled audio (interruptions).
        if notifyState, speakThroughConversationAudio(utterance, text: text) { return }
        activateAudioSession()
        synthesizer.speak(utterance)
    }

    func stop() {
        visionQueue.cancelAll()
        activeVisionItem = nil
        activeVisionUtterance = nil
        visionQueuePaused = false
        // A streamed reply ends with the utterance being cancelled now: its didCancel
        // reports the end once, through the ordinary path.
        streamUtterances = []
        streamPending = []
        streamOpen = false
        synthesizer.stopSpeaking(at: .immediate)
        stopConversationVoice(reportFinish: true)
        deactivateAudioSessionIfIdle()
    }

    // MARK: Voice through the conversation audio

    /// The sample rate of the voice that will speak, so the conversation audio plays it as is.
    var voiceSampleRate: Double {
        let settings = preferredVoice(for: profile)?.audioFileSettings ?? [:]
        if let rate = settings[AVSampleRateKey] as? NSNumber { return rate.doubleValue }
        return 22_050
    }

    /// Lowers Jarvis's voice while the user may be speaking over it, as a person would.
    func setVoiceLowered(_ lowered: Bool) {
        JarvisDuplexAudio.shared.setVoiceLowered(lowered)
    }

    /// Speaks `utterance` through the conversation audio when it is open, its buffers
    /// following each other without a gap. False otherwise: the synthesizer speaks.
    private func speakThroughConversationAudio(_ utterance: AVSpeechUtterance, text: String, stream: Bool = false) -> Bool {
        guard JarvisDuplexAudio.shared.isRunning else { return false }
        let generation = duplexGeneration
        duplexActive = true
        duplexIsStream = stream
        duplexRendering += 1
        renderer.write(utterance) { [weak self] buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            let ended = pcm.frameLength == 0
            let copy = ended ? nil : JarvisDuplexAudio.copy(pcm)
            DispatchQueue.main.async {
                guard let self, self.duplexGeneration == generation else { return }
                if ended {
                    self.duplexRendering = max(0, self.duplexRendering - 1)
                    self.finishConversationVoiceIfDone()
                    return
                }
                guard let copy else { return }
                let accepted = JarvisDuplexAudio.shared.play(copy) { [weak self] in
                    guard let self, self.duplexGeneration == generation else { return }
                    self.duplexPendingBuffers = max(0, self.duplexPendingBuffers - 1)
                    self.finishConversationVoiceIfDone()
                }
                guard accepted else { return }
                self.duplexPendingBuffers += 1
                if !self.duplexStarted {
                    self.duplexStarted = true
                    self.lastSpeechStartAt = Date()
                    self.onSpeechStart?()
                }
            }
        }
        // A voice that renders nothing: the synthesizer says the text instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.duplexGeneration == generation, self.duplexActive, !self.duplexStarted else { return }
            self.stopConversationVoice(reportFinish: false)
            self.activateAudioSession()
            let fallback = self.makeUtterance(self.currentReplyText.isEmpty ? text : self.currentReplyText, profile: self.profile)
            self.synthesizer.speak(fallback)
        }
        return true
    }

    private func finishConversationVoiceIfDone() {
        guard duplexActive, duplexRendering == 0, duplexPendingBuffers == 0, !(duplexIsStream && streamOpen) else { return }
        duplexActive = false
        duplexStarted = false
        duplexIsStream = false
        onSpeechFinish?()
    }

    /// Silences the voice of the conversation audio. With `reportFinish`, the end of the
    /// reply is reported once, after the current call returns (as didCancel does).
    private func stopConversationVoice(reportFinish: Bool) {
        guard duplexActive else { return }
        duplexGeneration += 1
        duplexActive = false
        duplexStarted = false
        duplexIsStream = false
        duplexRendering = 0
        duplexPendingBuffers = 0
        renderer.stopSpeaking(at: .immediate)
        JarvisDuplexAudio.shared.stopVoice()
        if reportFinish {
            DispatchQueue.main.async { [weak self] in
                self?.onSpeechFinish?()
            }
        }
    }

    // MARK: Streamed replies (local brain)

    /// Sentences of the reply being written, queued in the synthesizer and not finished.
    private var streamUtterances: [AVSpeechUtterance] = []
    /// Sentences that arrived while another was being said: they are said together, queued
    /// just before the current one ends, so the voice flows instead of starting over at
    /// every sentence.
    private var streamPending: [String] = []
    private var streamOpen = false
    private var streamStarted = false

    var isStreamingReply: Bool { streamOpen || !streamUtterances.isEmpty || !streamPending.isEmpty || (duplexActive && duplexIsStream) }

    /// True while any utterance is being spoken (the wake word waits for silence).
    var isSpeaking: Bool { synthesizer.isSpeaking || duplexActive }

    /// Starts a reply that will arrive sentence by sentence. `onSpeechStart` fires once
    /// for the first sentence and `onSpeechFinish` once, after the last one.
    func beginStreamedReply() {
        guard isEnabled else { return }
        activeVisionItem = nil
        activeVisionUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        stopConversationVoice(reportFinish: false)
        suppressNextCallbacks = false
        streamUtterances = []
        streamPending = []
        streamOpen = true
        streamStarted = false
        currentReplyText = ""
        lastSpeakRequestAt = Date()
    }

    /// Queues one more sentence without interrupting the one being spoken.
    func appendStreamedReply(_ text: String) {
        guard isEnabled, streamOpen else { return }
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        currentReplyText = currentReplyText.isEmpty ? sentence : currentReplyText + " " + sentence
        // The conversation audio plays the sentences one after the other, without a gap.
        if duplexActive || streamUtterances.isEmpty,
           speakThroughConversationAudio(makeUtterance(sentence, profile: profile), text: sentence, stream: true) {
            return
        }
        if streamUtterances.isEmpty {
            queueStreamUtterance(sentence)
        } else {
            streamPending.append(sentence)
        }
    }

    private func queueStreamUtterance(_ text: String) {
        let utterance = makeUtterance(text, profile: profile)
        utterance.postUtteranceDelay = 0
        streamUtterances.append(utterance)
        activateAudioSession()
        synthesizer.speak(utterance)
    }

    private func flushStreamPending() {
        guard !streamPending.isEmpty else { return }
        let text = streamPending.joined(separator: " ")
        streamPending = []
        queueStreamUtterance(text)
    }

    /// No more sentences will come. If everything was already spoken, the reply ends now.
    func endStreamedReply() {
        guard streamOpen else { return }
        streamOpen = false
        if duplexActive {
            finishConversationVoiceIfDone()
            return
        }
        if streamUtterances.isEmpty {
            if !streamPending.isEmpty {
                flushStreamPending()
                return
            }
            onSpeechFinish?()
            deactivateAudioSessionIfIdle()
        }
    }

    /// Handles a stream utterance's end; returns false for any other utterance.
    private func finishStreamUtterance(_ utterance: AVSpeechUtterance) -> Bool {
        guard let index = streamUtterances.firstIndex(where: { $0 === utterance }) else { return false }
        streamUtterances.remove(at: index)
        if streamUtterances.isEmpty, !streamPending.isEmpty {
            flushStreamPending()
            return true
        }
        if streamUtterances.isEmpty && !streamOpen {
            onSpeechFinish?()
            deactivateAudioSessionIfIdle()
        }
        return true
    }

    /// Near the end of the sentence being said, the sentences written meanwhile are queued,
    /// so the next one starts without a pause.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        guard !streamPending.isEmpty, let last = streamUtterances.last, last === utterance else { return }
        let length = (utterance.speechString as NSString).length
        guard length > 0, characterRange.location + characterRange.length >= length * 3 / 5 else { return }
        flushStreamPending()
    }

    func testPhrase() -> String {
        "Bonjour, je suis JARVIS. Ma voix française est prête."
    }

    /// Language spoken by Jarvis. The voice is chosen by language and quality rather
    /// than by a hard-coded voice name, because installed voices differ per iPhone.
    static let outputLanguage = "fr-FR"

    /// Best installed French voice (see JarvisVoiceRanking): France first, then premium >
    /// enhanced > standard, then a male voice; the robotic Eloquence voices (Eddy,
    /// Jacques…) only when nothing else speaks French. Returns nil when no French voice
    /// exists. Before, equal voices were taken in list order, which could pick Eloquence.
    static func bestVoice(
        from voices: [AVSpeechSynthesisVoice],
        language: String = JarvisSpeechService.outputLanguage
    ) -> AVSpeechSynthesisVoice? {
        guard let best = JarvisVoiceRanking.ranked(voices.map { JarvisVoiceCandidate($0) }, language: language).first else {
            return nil
        }
        return voices.first { $0.identifier == best.identifier }
    }

    /// Short description of the voice Jarvis will use, for Settings and Diagnostics.
    func currentVoiceDescription() -> String {
        guard let voice = preferredVoice(for: profile) else {
            return "Aucune voix française installée : la voix par défaut d'iOS sera utilisée."
        }
        let candidate = JarvisVoiceCandidate(voice)
        let origin = chosenVoiceIdentifier == voice.identifier ? "choisie dans les Réglages" : "choisie automatiquement"
        var text = "Voix \(voice.name) (\(voice.language), qualité \(candidate.qualityLabel)), \(origin)."
        if candidate.quality < 2 || candidate.isSynthetic {
            text += " " + Self.betterVoiceHint
        }
        return text
    }

    func previewAllProfiles() {
        guard isEnabled else { return }
        synthesizer.stopSpeaking(at: .immediate)
        let current = profile
        for previewProfile in JarvisVoiceProfile.ordered {
            let utterance = makeUtterance("Voix \(previewProfile.displayName). JARVIS est prêt.", profile: previewProfile)
            utterance.postUtteranceDelay = 0.16
            synthesizer.speak(utterance)
        }
        profile = current
    }

    func personalVoiceStatusText(completion: @escaping (String) -> Void) {
        guard #available(iOS 17.0, *) else {
            completion("Personal Voice requires iOS 17 or later.")
            return
        }

        func describe(_ status: AVSpeechSynthesizer.PersonalVoiceAuthorizationStatus) -> String {
            switch status {
            case .authorized:
                let count = personalVoices().count
                return count > 0
                    ? "Personal Voice authorized. Available personal voices: \(count)."
                    : "Personal Voice authorized, but no personal voice is currently available to JARVIS."
            case .denied:
                return "Personal Voice access denied. Enable it in iOS Settings, Accessibility, Personal Voice."
            case .notDetermined:
                return "Personal Voice permission has not been decided."
            case .unsupported:
                return "Personal Voice is unsupported on this device or configuration."
            @unknown default:
                return "Personal Voice status is unknown."
            }
        }

        let current = AVSpeechSynthesizer.personalVoiceAuthorizationStatus
        if current == .notDetermined {
            AVSpeechSynthesizer.requestPersonalVoiceAuthorization { updated in
                DispatchQueue.main.async {
                    completion(describe(updated))
                }
            }
        } else {
            completion(describe(current))
        }
    }

    private func makeUtterance(_ text: String, profile utteranceProfile: JarvisVoiceProfile) -> AVSpeechUtterance {
        // Formulas are read as words: « x³/3 » becomes « x au cube sur 3 ».
        let utterance = AVSpeechUtterance(string: JarvisSpokenMath.speakable(text))
        utterance.rate = speechRate(for: utteranceProfile)
        utterance.pitchMultiplier = pitch(for: utteranceProfile)
        utterance.volume = volume(for: utteranceProfile)
        if let voice = preferredVoice(for: utteranceProfile) {
            utterance.voice = voice
        }
        return utterance
    }

    private func speechRate(for utteranceProfile: JarvisVoiceProfile) -> Float {
        switch utteranceProfile {
        case .jarvis: return 0.47
        case .natural: return 0.46
        case .friendly: return 0.47
        case .formal: return 0.42
        case .crisp: return 0.51
        case .quiet: return 0.38
        }
    }

    private func pitch(for utteranceProfile: JarvisVoiceProfile) -> Float {
        switch utteranceProfile {
        case .jarvis: return 0.95
        case .natural: return 1.0
        case .friendly: return 1.05
        case .formal: return 0.98
        case .crisp: return 1.04
        case .quiet: return 0.98
        }
    }

    private func volume(for utteranceProfile: JarvisVoiceProfile) -> Float {
        if utteranceProfile == .quiet {
            return 0.58
        }
        let stored = UserDefaults.standard.float(forKey: volumeKey)
        return stored > 0 ? stored : 0.88
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        preferredVoice(for: profile)
    }

    private func preferredVoice(for voiceProfile: JarvisVoiceProfile) -> AVSpeechSynthesisVoice? {
        if prefersPersonalVoice, let personal = personalVoices().first {
            return personal
        }
        // A voice picked in Settings wins while it is installed.
        if let identifier = chosenVoiceIdentifier, let chosen = AVSpeechSynthesisVoice(identifier: identifier) {
            return chosen
        }
        // Profiles change rate, pitch and volume; every profile speaks French.
        return Self.bestVoice(from: AVSpeechSynthesisVoice.speechVoices()) ??
            AVSpeechSynthesisVoice(language: Self.outputLanguage)
    }

    private func personalVoices() -> [AVSpeechSynthesisVoice] {
        guard #available(iOS 17.0, *) else { return [] }
        return AVSpeechSynthesisVoice.speechVoices().filter { voice in
            voice.voiceTraits.contains(.isPersonalVoice)
        }
    }

    private func speakNextVisionItemIfPossible() {
        guard isEnabled, !visionQueuePaused else { return }
        guard activeVisionItem == nil else { return }
        guard !synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        guard let item = visionQueue.next() else {
            deactivateAudioSessionIfIdle()
            return
        }

        let utterance = makeUtterance(item.narration.text, profile: profile)
        activeVisionItem = item
        activeVisionUtterance = utterance
        let delay = max(0, Date().timeIntervalSince(item.narration.createdAt))
        VisionDiagnosticsStore.shared.recordNarrationDelay(delay)
        activateAudioSession()
        synthesizer.speak(utterance)
    }

    private func activateAudioSession() {
        // While the microphone is open, its play-and-record session already allows
        // output; switching to `.playback` here would silently cut the capture. The
        // conversation audio keeps its own session between turns.
        guard !JarvisVoiceInputService.shared.isListening, !JarvisDuplexAudio.shared.isRunning else { return }
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers, .allowBluetoothA2DP]
            )
            try audioSession.setActive(true)
        } catch {
            // AVSpeechSynthesizer can still use the system route when explicit session
            // activation is unavailable, so this remains a recoverable degradation.
        }
    }

    private func deactivateAudioSessionIfIdle() {
        guard activeVisionItem == nil, !synthesizer.isSpeaking, !synthesizer.isPaused else { return }
        // Never release the shared session under an open microphone. Before this guard,
        // `stop()` (called when listening starts) and the asynchronous didCancel callback
        // deactivated the session the dictation had just activated, leaving the
        // recognizer with no usable audio ("Aucune parole détectée").
        guard !JarvisVoiceInputService.shared.isListening, !JarvisDuplexAudio.shared.isRunning else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            switch type {
            case .began:
                self.visionWasPausedByAudioInterruption = self.activeVisionItem != nil
                if self.visionWasPausedByAudioInterruption {
                    self.visionQueuePaused = true
                    self.synthesizer.pauseSpeaking(at: .word)
                }
            case .ended:
                let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                if self.visionWasPausedByAudioInterruption {
                    self.visionWasPausedByAudioInterruption = false
                    self.visionQueuePaused = false
                    if shouldResume, self.synthesizer.isPaused {
                        self.activateAudioSession()
                        self.synthesizer.continueSpeaking()
                    } else if shouldResume {
                        self.speakNextVisionItemIfPossible()
                    }
                }
            @unknown default:
                break
            }
        }
    }

    @objc private func handleAudioRouteChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activeVisionItem != nil else { return }
            self.activateAudioSession()
            if !self.visionQueuePaused {
                self.speakNextVisionItemIfPossible()
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        lastSpeechStartAt = Date()
        if streamUtterances.contains(where: { $0 === utterance }) {
            guard !streamStarted else { return }
            streamStarted = true
            onSpeechStart?()
            return
        }
        guard !suppressNextCallbacks else { return }
        onSpeechStart?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if finishStreamUtterance(utterance) { return }
        if activeVisionUtterance === utterance, let completed = activeVisionItem {
            visionQueue.markCompleted(completed)
            activeVisionItem = nil
            activeVisionUtterance = nil
            speakNextVisionItemIfPossible()
            if activeVisionItem == nil {
                onSpeechFinish?()
                deactivateAudioSessionIfIdle()
            }
            return
        }
        if suppressNextCallbacks {
            suppressNextCallbacks = false
            deactivateAudioSessionIfIdle()
            return
        }
        onSpeechFinish?()
        speakNextVisionItemIfPossible()
        deactivateAudioSessionIfIdle()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        if finishStreamUtterance(utterance) { return }
        if activeVisionUtterance === utterance {
            activeVisionItem = nil
            activeVisionUtterance = nil
            speakNextVisionItemIfPossible()
            if activeVisionItem == nil {
                onSpeechFinish?()
                deactivateAudioSessionIfIdle()
            }
            return
        }
        if suppressNextCallbacks {
            suppressNextCallbacks = false
            deactivateAudioSessionIfIdle()
            return
        }
        onSpeechFinish?()
        speakNextVisionItemIfPossible()
        deactivateAudioSessionIfIdle()
    }
}
