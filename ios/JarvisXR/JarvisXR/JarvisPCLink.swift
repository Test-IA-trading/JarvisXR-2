import Foundation
import Network
import Security

/// The pairing code of Jarvis PC, kept in the iOS keychain rather than in preferences.
/// When the keychain refuses it (an unsigned build, such as the simulator's in CI), the
/// code stays in the app's own preferences, so pairing still works.
enum JarvisKeychain {
    private static let service = "JarvisXR"
    /// Swapped by the tests.
    static var fallback: UserDefaults = .standard

    private static func fallbackKey(_ account: String) -> String {
        "JarvisXR.keychainFallback.\(account)"
    }

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data {
            return String(data: data, encoding: .utf8)
        }
        return fallback.string(forKey: fallbackKey(account))
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        fallback.removeObject(forKey: fallbackKey(account))
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if SecItemAdd(attributes as CFDictionary, nil) != errSecSuccess {
            fallback.set(value, forKey: fallbackKey(account))
        }
    }
}

/// The link with Jarvis on the user's own PC (pc/jarvis_pc): its large brain (Qwen3 30B),
/// its commands (« Sur le PC, ouvre Spotify »), its voice, and the first name and notes
/// both share. Only the PC paired with its code is contacted, at the address the user
/// typed (home Wi-Fi or Tailscale); nothing goes to any other service.
final class JarvisPCLink {
    static let shared = JarvisPCLink()
    static let defaultPort = 8765

    enum LinkError: Error, Equatable {
        case notConfigured
        case refused
        case unreachable(String)
        case badAnswer

        var message: String {
            switch self {
            case .notConfigured: return "Jarvis PC n'est pas relié : saisissez son adresse et son code dans Réglages › Jarvis PC."
            case .refused: return "Jarvis PC refuse le code d'appairage : recopiez celui qu'affiche le PC dans Réglages › Jarvis PC."
            case .unreachable: return "Je n'arrive pas à joindre Jarvis PC : vérifiez qu'il est lancé et que l'iPhone est sur le même Wi-Fi (ou sur Tailscale)."
            case .badAnswer: return "Jarvis PC a répondu quelque chose d'illisible."
            }
        }
    }

    private let defaults: UserDefaults
    private let codeAccount: String
    private let session: URLSession
    private let addressKey = "JarvisXR.pcAddress"
    private let useBrainKey = "JarvisXR.pcUseBrain"
    private var browser: NWBrowser?
    private var resolver: NWConnection?
    private var discoveryCompletion: ((String?) -> Void)?
    private var discoveryGeneration = 0
    private var lastSynchronized: Date?

    init(defaults: UserDefaults = .standard, codeAccount: String = "JarvisXR.pcPairingCode", session: URLSession? = nil) {
        self.defaults = defaults
        self.codeAccount = codeAccount
        if let session {
            self.session = session
        } else {
            // No cache and no cookies: each exchange with the PC stands alone.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 300
            self.session = URLSession(configuration: configuration)
        }
    }

    // MARK: Pairing

    /// « 192.168.1.23 », « 192.168.1.23:8765 » or a Tailscale name « pc.xxxx.ts.net ».
    var address: String {
        get { defaults.string(forKey: addressKey) ?? "" }
        set {
            defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: addressKey)
            lastReachable = nil
        }
    }

    var pairingCode: String? {
        get { JarvisKeychain.string(for: codeAccount) }
        set {
            JarvisKeychain.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), for: codeAccount)
            lastReachable = nil
        }
    }

    /// Open questions go to the PC's brain when it answers (on by default once paired).
    var usesPCBrain: Bool {
        get { defaults.object(forKey: useBrainKey) == nil ? true : defaults.bool(forKey: useBrainKey) }
        set { defaults.set(newValue, forKey: useBrainKey) }
    }

    var isConfigured: Bool { !address.isEmpty && !(pairingCode ?? "").isEmpty }

    /// The PC's URL for `path`, built from the typed address (port 8765 by default).
    static func url(address: String, path: String) -> URL? {
        var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: "^[A-Za-z]+:/+", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !text.isEmpty, !text.contains("/") else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        var components = URLComponents()
        components.scheme = "http"
        components.host = parts[0]
        if parts.count > 1 {
            guard let port = Int(parts[1]), (1...65535).contains(port) else { return nil }
            components.port = port
        } else {
            components.port = defaultPort
        }
        components.path = path
        return components.url
    }

    func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 8) -> URLRequest? {
        guard let url = Self.url(address: address, path: path) else { return nil }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        if let code = pairingCode, !code.isEmpty {
            request.setValue("Bearer \(code)", forHTTPHeaderField: "Authorization")
        }
        if let body, let data = try? JSONSerialization.data(withJSONObject: body) {
            request.httpBody = data
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    // MARK: Exchanges

    private func send(_ request: URLRequest?, completion: @escaping (Result<[String: Any], LinkError>) -> Void) {
        guard isConfigured, let request else {
            completion(.failure(.notConfigured))
            return
        }
        session.dataTask(with: request) { data, response, error in
            let result: Result<[String: Any], LinkError>
            if let error {
                result = .failure(.unreachable(error.localizedDescription))
            } else if (response as? HTTPURLResponse)?.statusCode == 401 {
                result = .failure(.refused)
            } else if let data, let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                      (response as? HTTPURLResponse)?.statusCode == 200 {
                result = .success(object)
            } else {
                result = .failure(.badAnswer)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// « Relié à Jarvis PC » with its brain's name, or why not.
    func checkConnection(completion: @escaping (Result<String, LinkError>) -> Void) {
        send(request("/v1/health")) { [weak self] result in
            if case .success(let object) = result {
                self?.lastReachable = (Date(), object["paired"] as? Bool == true)
            }
            completion(result.flatMap { (object: [String: Any]) -> Result<String, LinkError> in
                guard object["paired"] as? Bool == true else { return .failure(.refused) }
                return .success((object["model"] as? String) ?? "cerveau inconnu")
            })
        }
    }

    /// A command run by the PC: « ouvre Spotify », « quel temps fait-il à Lyon ? ».
    func command(_ text: String, completion: @escaping (Result<(spoken: String, display: String), LinkError>) -> Void) {
        send(request("/v1/command", method: "POST", body: ["text": text], timeout: 120)) { result in
            completion(result.flatMap { (object: [String: Any]) -> Result<(spoken: String, display: String), LinkError> in
                guard let spoken = object["spoken"] as? String else { return .failure(.badAnswer) }
                return .success((spoken: spoken, display: (object["display"] as? String) ?? spoken))
            })
        }
    }

    /// Words said aloud by the PC.
    func say(_ text: String, completion: @escaping (Result<Void, LinkError>) -> Void) {
        send(request("/v1/say", method: "POST", body: ["text": text])) { result in
            completion(result.map { _ in () })
        }
    }

    /// One line of the PC's streamed answer: {"partial": …}, {"final": …} or {"error": …}.
    static func parseLine(_ line: String) -> (partial: String?, final: String?, error: String?)? {
        guard let data = line.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return (object["partial"] as? String, object["final"] as? String, object["error"] as? String)
    }

    private var lastReachable: (date: Date, reachable: Bool)?

    /// Whether the PC answers, checked in 2 s at most and remembered for 30 s, so a PC that
    /// is off costs no wait before the iPhone's own brain answers.
    func checkReachable(completion: @escaping (Bool) -> Void) {
        if let last = lastReachable, Date().timeIntervalSince(last.date) < 30 {
            completion(last.reachable)
            return
        }
        send(request("/v1/health", timeout: 2)) { [weak self] result in
            var reachable = false
            if case .success(let object) = result { reachable = object["paired"] as? Bool == true }
            self?.lastReachable = (Date(), reachable)
            completion(reachable)
        }
    }

    /// An open question for the PC's brain; `onPartial` receives the answer as it is written.
    /// With `commands`, the brain may answer « COMMANDE: appelle Paul » for a request the
    /// iPhone can run (JarvisBrainCommand).
    func ask(question: String, history: [JarvisChatTurn], context: [String], commands: Bool = false, onPartial: @escaping (String) -> Void, completion: @escaping (Result<String, LinkError>) -> Void) {
        guard isConfigured else {
            completion(.failure(.notConfigured))
            return
        }
        checkReachable { [weak self] reachable in
            guard let self, reachable else {
                completion(.failure(.unreachable("pas de réponse")))
                return
            }
            self.stream(question: question, history: history, context: context, commands: commands, onPartial: onPartial, completion: completion)
        }
    }

    static func askBody(question: String, history: [JarvisChatTurn], context: [String], commands: Bool) -> [String: Any] {
        let turns = history.suffix(6).map { ["user": $0.user, "assistant": $0.assistant] }
        var body: [String: Any] = ["question": question, "history": turns, "context": context]
        if commands { body["commands"] = "iphone" }
        return body
    }

    private func stream(question: String, history: [JarvisChatTurn], context: [String], commands: Bool, onPartial: @escaping (String) -> Void, completion: @escaping (Result<String, LinkError>) -> Void) {
        let body = Self.askBody(question: question, history: history, context: context, commands: commands)
        // The PC may need a few seconds to load its model the first time.
        guard let request = request("/v1/ask", method: "POST", body: body, timeout: 30) else {
            completion(.failure(.notConfigured))
            return
        }
        let session = self.session
        Task {
            let result: Result<String, LinkError>
            do {
                let (bytes, response) = try await session.bytes(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 { throw LinkError.refused }
                guard status == 200 else { throw LinkError.badAnswer }
                var answer: String?
                for try await line in bytes.lines {
                    guard let parsed = Self.parseLine(line) else { continue }
                    if let message = parsed.error { throw LinkError.unreachable(message) }
                    if let partial = parsed.partial {
                        await MainActor.run { onPartial(partial) }
                    }
                    if let text = parsed.final { answer = text }
                }
                guard let answer, !answer.isEmpty else { throw LinkError.badAnswer }
                result = .success(answer)
            } catch let error as LinkError {
                result = .failure(error)
            } catch {
                result = .failure(.unreachable(error.localizedDescription))
            }
            await MainActor.run {
                if case .failure(.unreachable) = result { self.lastReachable = nil }
                completion(result)
            }
        }
    }

    // MARK: Shared memory and messages from the PC

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// What the iPhone knows, in the PC's format.
    static func memoryPayload(memory: JarvisMemoryStore, profile: JarvisUserProfile) -> [String: Any] {
        var payload: [String: Any] = [
            "name_updated": isoFormatter.string(from: profile.nameUpdated),
            "notes": memory.loadNotes().map { note -> [String: String] in
                ["id": note.id.uuidString, "text": note.text, "created": isoFormatter.string(from: note.createdAt)]
            },
        ]
        if let name = profile.name {
            payload["name"] = name
        } else {
            payload["name"] = NSNull()
        }
        return payload
    }

    /// Takes in the PC's merged memory: its new notes, and its first name when more recent.
    @discardableResult
    static func adopt(_ merged: [String: Any], memory: JarvisMemoryStore, profile: JarvisUserProfile) -> Int {
        var added = 0
        for note in merged["notes"] as? [[String: Any]] ?? [] {
            guard let text = note["text"] as? String, !text.isEmpty else { continue }
            let id = (note["id"] as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            let created = (note["created"] as? String).flatMap { isoFormatter.date(from: $0) } ?? Date()
            if memory.importNote(id: id, text: text, createdAt: created) { added += 1 }
        }
        if let stamp = merged["name_updated"] as? String, let updated = isoFormatter.date(from: stamp), updated > profile.nameUpdated {
            profile.adoptName(merged["name"] as? String, updated: updated)
        }
        return added
    }

    /// Exchanges the first name and the notes with the PC, then hands over its messages.
    func synchronize(memory: JarvisMemoryStore = .shared, profile: JarvisUserProfile = .shared, messages: @escaping ([String]) -> Void) {
        guard isConfigured else { return }
        // Opening the app and showing the main screen often come together: one exchange.
        if let last = lastSynchronized, Date().timeIntervalSince(last) < 5 { return }
        lastSynchronized = Date()
        send(request("/v1/memory", method: "POST", body: Self.memoryPayload(memory: memory, profile: profile))) { [weak self] result in
            if case .success(let merged) = result {
                Self.adopt(merged, memory: memory, profile: profile)
            }
            self?.send(self?.request("/v1/inbox")) { inbox in
                guard case .success(let object) = inbox else { return }
                let texts = (object["messages"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
                if !texts.isEmpty { messages(texts) }
            }
        }
    }

    // MARK: Finding the PC on the home network

    /// Looks for « Jarvis PC » on the Wi-Fi (Bonjour) and gives its address, or nil.
    /// Everything runs on the main queue, so the search state needs no lock.
    func discover(timeout: TimeInterval = 6, completion: @escaping (String?) -> Void) {
        stopDiscovery()
        discoveryGeneration += 1
        let generation = discoveryGeneration
        discoveryCompletion = completion
        let browser = NWBrowser(for: .bonjour(type: "_jarvis._tcp", domain: nil), using: .tcp)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self, self.resolver == nil, let endpoint = results.first?.endpoint else { return }
            self.resolve(endpoint)
        }
        browser.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.discoveryGeneration == generation else { return }
            self.finishDiscovery(nil)
        }
    }

    /// The found service's IPv4 address, so it fits « host:port » in Settings.
    private func resolve(_ endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: parameters)
        resolver = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard case .ready = state else { return }
            guard case .hostPort(let host, let port)? = connection?.currentPath?.remoteEndpoint else {
                self?.finishDiscovery(nil)
                return
            }
            var hostText = "\(host)"
            if let percent = hostText.firstIndex(of: "%") { hostText = String(hostText[..<percent]) }
            self?.finishDiscovery(port.rawValue == UInt16(Self.defaultPort) ? hostText : "\(hostText):\(port.rawValue)")
        }
        connection.start(queue: .main)
    }

    private func finishDiscovery(_ address: String?) {
        guard let completion = discoveryCompletion else { return }
        discoveryCompletion = nil
        stopDiscovery()
        completion(address)
    }

    func stopDiscovery() {
        browser?.cancel()
        browser = nil
        resolver?.cancel()
        resolver = nil
    }
}
