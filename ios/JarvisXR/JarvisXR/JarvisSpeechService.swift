import AVFoundation

enum JarvisVoiceProfile: String {
    static let ordered: [JarvisVoiceProfile] = [.natural, .friendly, .crisp, .quiet, .formal]

    case natural
    case friendly
    case formal
    case crisp
    case quiet

    var displayName: String {
        switch self {
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
    private var suppressNextCallbacks = false
    private var visionQueue = VisionSpeechPriorityQueue()
    private var activeVisionItem: VisionSpeechQueueItem?
    private var activeVisionUtterance: AVSpeechUtterance?
    private var visionQueuePaused = false
    private var visionWasPausedByAudioInterruption = false
    private var quietVisionGuideEnabled = false
    var onSpeechStart: (() -> Void)?
    var onSpeechFinish: (() -> Void)?

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
            case .natural: return 1.03
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
                return .natural
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
        if quietVisionGuideEnabled && narration.priority < .target {
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

    func speak(_ text: String, notifyState: Bool = true) {
        guard isEnabled else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        activeVisionItem = nil
        activeVisionUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = makeUtterance(text, profile: profile)
        suppressNextCallbacks = !notifyState
        activateAudioSession()
        synthesizer.speak(utterance)
    }

    func stop() {
        visionQueue.cancelAll()
        activeVisionItem = nil
        activeVisionUtterance = nil
        visionQueuePaused = false
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSessionIfIdle()
    }

    func testPhrase() -> String {
        "Bonjour, je suis JARVIS. Ma voix française est prête."
    }

    /// Language spoken by Jarvis. The voice is chosen by language and quality rather
    /// than by a hard-coded voice name, because installed voices differ per iPhone.
    static let outputLanguage = "fr-FR"

    /// Ranks installed voices: exact language first, then any French variant, then by
    /// quality (premium > enhanced > default). Returns nil when no French voice exists.
    static func bestVoice(
        from voices: [AVSpeechSynthesisVoice],
        language: String = JarvisSpeechService.outputLanguage
    ) -> AVSpeechSynthesisVoice? {
        let languagePrefix = String(language.prefix(2))
        func qualityRank(_ voice: AVSpeechSynthesisVoice) -> Int {
            switch voice.quality {
            case .premium: return 3
            case .enhanced: return 2
            default: return 1
            }
        }
        func isUsable(_ voice: AVSpeechSynthesisVoice) -> Bool {
            if #available(iOS 17.0, *) {
                // Novelty voices (Bells, Bubbles…) and personal voices are never a default.
                return !voice.voiceTraits.contains(.isNoveltyVoice) && !voice.voiceTraits.contains(.isPersonalVoice)
            }
            return true
        }
        let candidates = voices.filter { $0.language.hasPrefix(languagePrefix) && isUsable($0) }
        return candidates.max { lhs, rhs in
            let lhsExact = lhs.language == language ? 1 : 0
            let rhsExact = rhs.language == language ? 1 : 0
            if lhsExact != rhsExact { return lhsExact < rhsExact }
            return qualityRank(lhs) < qualityRank(rhs)
        }
    }

    /// Short description of the voice Jarvis will use, for Settings and Diagnostics.
    func currentVoiceDescription() -> String {
        guard let voice = preferredVoice(for: profile) else {
            return "Aucune voix française installée : la voix par défaut d'iOS sera utilisée."
        }
        let quality: String
        switch voice.quality {
        case .premium: quality = "premium"
        case .enhanced: quality = "améliorée"
        default: quality = "standard"
        }
        return "Voix \(voice.name) (\(voice.language), qualité \(quality))."
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
        let utterance = AVSpeechUtterance(string: text)
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
        case .natural: return 0.46
        case .friendly: return 0.47
        case .formal: return 0.42
        case .crisp: return 0.51
        case .quiet: return 0.38
        }
    }

    private func pitch(for utteranceProfile: JarvisVoiceProfile) -> Float {
        switch utteranceProfile {
        case .natural: return 1.03
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
        // output; switching to `.playback` here would silently cut the capture.
        guard !JarvisVoiceInputService.shared.isListening else { return }
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
        guard !JarvisVoiceInputService.shared.isListening else { return }
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
        guard !suppressNextCallbacks else { return }
        onSpeechStart?()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
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
