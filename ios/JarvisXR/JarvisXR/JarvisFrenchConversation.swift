import UIKit
import AVFoundation

private final class NoChatRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class JarvisFrenchConversation: UIViewController, AVSpeechSynthesizerDelegate {
    private let url: URL
    private let code: String
    private let input = JarvisVoiceInputService(locale: Locale(identifier: "fr-FR"), maximumListenDuration: 55)
    private let speaker = AVSpeechSynthesizer()
    private let session: URLSession
    private let transcript = UITextView()
    private let status = UILabel()
    private let button = UIButton(type: .system)
    private var turns = [[String: String]]()
    private var request: URLSessionDataTask?
    private var generation = UUID()
    private var speaking: AVSpeechUtterance?
    private var active = false

    init(url: URL, code: String) {
        self.url = url
        self.code = code
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 185
        config.timeoutIntervalForResource = 190
        config.httpShouldSetCookies = false
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: NoChatRedirect(), delegateQueue: .main)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) indisponible") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Conversation avec Jarvis"
        view.backgroundColor = .systemBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .close, target: self, action: #selector(closeChat))
        transcript.isEditable = false
        transcript.font = .preferredFont(forTextStyle: .body)
        transcript.accessibilityLabel = "Conversation"
        status.numberOfLines = 0
        status.text = "Prêt à écouter en français."
        button.setTitle("Commencer à parler", for: .normal)
        button.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [transcript, status, button])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        speaker.delegate = self
        input.onPartialTranscript = { [weak self] text in self?.status.text = text }
        input.onFinalTranscript = { [weak self] text in self?.send(text) }
        input.onStateChange = { [weak self] state in
            guard let self, self.active else { return }
            switch state {
            case .listening: self.status.text = "Je t’écoute…"
            case .noSpeech: self.pause("Aucune parole entendue. Tu peux reprendre.")
            case .unavailable: self.pause("Écoute indisponible. Vérifie le micro et la reconnaissance vocale dans Réglages.")
            default: break
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(background),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)),
            name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private func audioInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              value == AVAudioSession.InterruptionType.began.rawValue else { return }
        DispatchQueue.main.async { [weak self] in self?.background() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        pause("Conversation en pause.")
    }

    deinit { session.invalidateAndCancel() }

    @objc private func closeChat() { dismiss(animated: true) }
    @objc private func background() { if active { pause("Conversation en pause.") } }

    private func pause(_ message: String) {
        active = false
        generation = UUID()
        request?.cancel()
        request = nil
        speaking = nil
        speaker.stopSpeaking(at: .immediate)
        input.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        status.text = message
        button.setTitle("Reprendre la parole", for: .normal)
    }

    @objc private func toggle() {
        if speaking != nil {
            speaking = nil
            speaker.stopSpeaking(at: .immediate)
            listen()
        } else if active {
            pause("Conversation en pause.")
        } else {
            active = true
            listen()
        }
    }

    private func listen() {
        guard active else { return }
        status.text = "Activation du micro…"
        button.setTitle("Mettre en pause", for: .normal)
        input.startListening()
    }

    private func send(_ text: String) {
        guard active, request == nil else { return }
        guard text.utf16.count <= 2000 else { pause("Cette demande est trop longue. Reformule-la en deux phrases."); return }
        let user = ["role": "user", "content": text]
        let messages = turns + [user]
        var post = URLRequest(url: url.appendingPathComponent("api/chat"))
        post.httpMethod = "POST"
        post.setValue(code, forHTTPHeaderField: "X-Jarvis-Code")
        post.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do { post.httpBody = try JSONSerialization.data(withJSONObject: ["messages": messages]) }
        catch { pause("Impossible de préparer la demande."); return }
        status.text = "Qwen réfléchit…"
        let attempt = generation
        request = session.dataTask(with: post) { [weak self] data, response, _ in
            guard let self, self.active, self.generation == attempt else { return }
            self.request = nil
            guard let http = response as? HTTPURLResponse, let data else {
                self.pause("PC inaccessible. Vérifie le Wi-Fi, l’adresse et le compagnon Windows.")
                return
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard http.statusCode == 200, let reply = body?["reply"] as? String,
                  !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                self.pause((body?["error"] as? String) ?? "Le PC a interrompu la demande.")
                return
            }
            var excerpt = String(reply.prefix(6000))
            while excerpt.utf16.count > 6000 { excerpt.removeLast() }
            self.turns = Array((messages + [["role": "assistant", "content": excerpt]]).suffix(8))
            self.transcript.text.append("Toi — \(text)\nJarvis — \(reply)\n\n")
            self.transcript.scrollRangeToVisible(NSRange(location: (self.transcript.text as NSString).length, length: 0))
            self.say(reply)
        }
        request?.resume()
    }

    private func say(_ reply: String) {
        let audio = AVAudioSession.sharedInstance()
        do {
            try audio.setCategory(.playback, mode: .spokenAudio)
            try audio.setActive(true)
        } catch { pause("Lecture audio indisponible. La réponse est affichée."); return }
        let utterance = AVSpeechUtterance(string: reply)
        guard let voice = AVSpeechSynthesisVoice(language: "fr-FR") else {
            pause("Voix française indisponible. La réponse est affichée.")
            return
        }
        utterance.voice = voice
        speaking = utterance
        status.text = "Jarvis parle…"
        button.setTitle("Interrompre et parler", for: .normal)
        speaker.speak(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard speaking === utterance, active else { return }
        speaking = nil
        listen()
    }
}
