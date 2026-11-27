import Foundation
import os
import UIKit
#if canImport(llama)
import llama
#endif

// MARK: - Model catalogue

/// The language model JARVIS downloads once, with the user's consent, to answer open
/// questions on the iPhone without a network or a PC.
struct JarvisLocalModel: Equatable {
    let identifier: String
    let displayName: String
    let fileName: String
    let downloadURL: URL
    let sha256: String
    let sizeBytes: Int64
    let license: String
    let source: String

    /// Qwen2.5 1.5B Instruct, Q4_K_M quantisation: multilingual (French included),
    /// Apache 2.0, about 1.1 GB, fast enough on an A16 with Metal.
    static let qwen25Instruct1_5B = JarvisLocalModel(
        identifier: "qwen2.5-1.5b-instruct-q4_k_m",
        displayName: "Qwen2.5 1.5B Instruct",
        fileName: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
        downloadURL: URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf")!,
        sha256: "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
        sizeBytes: 1_117_320_736,
        license: "Apache 2.0",
        source: "Hugging Face (Qwen)"
    )

    /// Qwen3 4B Instruct (2507), IQ4_XS quantisation published by Unsloth: clearly better
    /// at reasoning, maths and French than the 1.5B model, but slower, 2.3 GB, and it needs
    /// about 2.7 GB of free memory. Optional: « Avancé » in Settings.
    static let qwen3Instruct4B = JarvisLocalModel(
        identifier: "qwen3-4b-instruct-2507-iq4_xs",
        displayName: "Qwen3 4B Instruct",
        fileName: "Qwen3-4B-Instruct-2507-IQ4_XS.gguf",
        downloadURL: URL(string: "https://huggingface.co/unsloth/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-IQ4_XS.gguf")!,
        sha256: "cfd15a69e4801abfa16f0263b77ffbf97cbb8af67782a70cc95cf627b3dfa27d",
        sizeBytes: 2_270_751_840,
        license: "Apache 2.0",
        source: "Hugging Face (Unsloth, modèle Qwen)"
    )

    /// Standard first, then Avancé, as in Settings.
    static let catalog: [JarvisLocalModel] = [.qwen25Instruct1_5B, .qwen3Instruct4B]
    static let selectionKey = "JarvisXR.brainModel"

    /// The brain chosen in Settings: the standard 1.5B model unless « Avancé » was picked.
    static var selected: JarvisLocalModel {
        get {
            let identifier = UserDefaults.standard.string(forKey: selectionKey)
            return catalog.first { $0.identifier == identifier } ?? .qwen25Instruct1_5B
        }
        set {
            UserDefaults.standard.set(newValue.identifier, forKey: selectionKey)
        }
    }

    var isAdvanced: Bool { self == .qwen3Instruct4B }

    /// Free memory needed before loading: the mapped file, the conversation cache (2,048
    /// tokens) and the work buffers.
    var requiredMemoryBytes: Int64 { sizeBytes + 450_000_000 }

    /// « 1,1 Go »
    var sizeDescription: String {
        JarvisLocalModel.gigabytes(sizeBytes)
    }

    static func gigabytes(_ bytes: Int64) -> String {
        String(format: "%.1f Go", Double(bytes) / 1_000_000_000).replacingOccurrences(of: ".", with: ",")
    }
}

// MARK: - Prompt

struct JarvisChatTurn: Equatable {
    let user: String
    let assistant: String
}

/// Builds the ChatML prompt understood by Qwen2.5 instruct models.
enum JarvisChatPrompt {
    static let defaultCharacterBudget = 4_500

    static func systemPrompt(now: Date, context: [String]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        var lines = [
            "Tu es JARVIS, l'assistant personnel de l'utilisateur sur son iPhone : cultivé, précis et calme, avec une pointe d'humour discret.",
            "Vouvoie toujours l'utilisateur, avec la courtoisie d'un majordome.",
            "Réponds toujours en français, comme dans une vraie conversation à voix haute : des phrases complètes, fluides et bien reliées entre elles, comme le dirait une personne cultivée, jamais un style télégraphique. Va droit à l'essentiel en deux ou trois phrases, sauf si l'utilisateur demande plus de détails ou si un calcul demande quelques étapes.",
            "Ta réponse est lue à voix haute : pas de listes, pas de titres, pas de markdown, pas d'émoji. Écris les formules en texte simple, sans LaTeX, par exemple x³/3 + C.",
            "Tu sais faire des mathématiques (calculs, dérivées, intégrales, équations), de la physique, de la chimie, de l'histoire, du code et de la culture générale : réponds à ces questions même difficiles, en donnant d'abord le résultat puis une courte explication.",
            "Tu fonctionnes hors ligne : tu n'as accès ni à Internet, ni aux actualités, ni à la météo, ni aux données de l'iPhone en dehors du contexte ci-dessous.",
            "Pour un fait récent ou qui change souvent (actualités, prix, résultats sportifs), dis que tu ne peux pas le vérifier hors ligne au lieu d'inventer. Si tu n'es pas sûr d'un calcul, dis-le.",
            "Tu ne remplaces ni un médecin, ni un professionnel, ni la vigilance de l'utilisateur pour sa sécurité.",
            "Nous sommes le \(formatter.string(from: now))."
        ]
        lines.append(contentsOf: context.filter { !$0.isEmpty })
        return lines.joined(separator: "\n")
    }

    /// Removes the chat-template control markers from user-provided text.
    static func sanitize(_ text: String) -> String {
        var value = text
        for marker in ["<|im_start|>", "<|im_end|>", "<|endoftext|>"] {
            value = value.replacingOccurrences(of: marker, with: " ")
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Keeps the most recent turns that fit in `characterBudget`, oldest first.
    static func recentTurns(_ history: [JarvisChatTurn], question: String, system: String, characterBudget: Int) -> [JarvisChatTurn] {
        var remaining = characterBudget - system.count - question.count
        var kept: [JarvisChatTurn] = []
        for turn in history.reversed() {
            let cost = turn.user.count + turn.assistant.count + 60
            guard remaining - cost >= 0 else { break }
            remaining -= cost
            kept.insert(turn, at: 0)
        }
        return kept
    }

    static func chatML(system: String, history: [JarvisChatTurn], question: String, characterBudget: Int = defaultCharacterBudget) -> String {
        let cleanQuestion = String(sanitize(question).prefix(1_500))
        let turns = recentTurns(history, question: cleanQuestion, system: system, characterBudget: characterBudget)
        var prompt = "<|im_start|>system\n\(sanitize(system))<|im_end|>\n"
        for turn in turns {
            prompt += "<|im_start|>user\n\(sanitize(turn.user))<|im_end|>\n"
            prompt += "<|im_start|>assistant\n\(sanitize(turn.assistant))<|im_end|>\n"
        }
        prompt += "<|im_start|>user\n\(cleanQuestion)<|im_end|>\n<|im_start|>assistant\n"
        return prompt
    }
}

// MARK: - Streaming text

/// Collects the UTF-8 bytes produced token by token. A character can be split across
/// two tokens; `decodedPrefix` holds back an incomplete trailing sequence so the
/// screen never shows a broken « é ».
struct JarvisUTF8Accumulator {
    private(set) var bytes: [UInt8] = []

    mutating func append<S: Sequence>(_ newBytes: S) where S.Element == UInt8 {
        bytes.append(contentsOf: newBytes)
    }

    var decodedPrefix: String {
        String(decoding: bytes[0..<completeLength], as: UTF8.self)
    }

    var finalText: String {
        String(decoding: bytes, as: UTF8.self)
    }

    private var completeLength: Int {
        var index = bytes.count - 1
        var continuationBytes = 0
        while index >= 0 && continuationBytes < 4 {
            let byte = bytes[index]
            if byte & 0b1100_0000 == 0b1000_0000 {
                continuationBytes += 1
                index -= 1
                continue
            }
            let needed: Int
            if byte & 0b1000_0000 == 0 { needed = 1 }
            else if byte & 0b1110_0000 == 0b1100_0000 { needed = 2 }
            else if byte & 0b1111_0000 == 0b1110_0000 { needed = 3 }
            else if byte & 0b1111_1000 == 0b1111_0000 { needed = 4 }
            else { needed = 1 }
            return bytes.count - index < needed ? index : bytes.count
        }
        return bytes.count
    }
}

/// Cuts the answer being written into sentences, so speech can start with the first
/// sentence instead of waiting for the whole answer.
struct JarvisSentenceStreamer {
    /// Characters of the text already handed out.
    private(set) var emittedCount = 0

    /// Complete sentences of `text` not handed out yet. With `final`, the remaining
    /// text is returned as the last sentence.
    mutating func newSentences(in text: String, final: Bool) -> [String] {
        let characters = Array(text)
        guard emittedCount < characters.count else { return [] }
        var sentences: [String] = []
        var start = emittedCount
        var index = emittedCount
        while index < characters.count {
            let character = characters[index]
            let isEnd = ".!?…".contains(character)
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            if isEnd, let next, next == " " || next == "\n" {
                let sentence = String(characters[start...index]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty { sentences.append(sentence) }
                start = index + 1
            }
            index += 1
        }
        if final {
            let rest = String(characters[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rest.isEmpty { sentences.append(rest) }
            start = characters.count
        }
        emittedCount = start
        return sentences
    }
}

/// Turns raw model output into a short spoken answer.
enum JarvisAnswerCleaner {
    static func clean(_ raw: String, maxCharacters: Int = 700) -> String {
        // LaTeX (\frac{x^3}{3}) becomes plain notation (x³/3) before anything else.
        var text = JarvisSpokenMath.plainMath(raw)
        // A model that thinks aloud wraps it in <think>…</think>: only the answer is kept.
        text = text.replacingRegex(#"(?s)<think>.*?</think>"#, with: "")
        if let open = text.range(of: "<think>") {
            text = String(text[..<open.lowerBound])
        }
        for marker in ["<|im_end|>", "<|im_start|>", "<|endoftext|>"] {
            if let range = text.range(of: marker) {
                text = String(text[..<range.lowerBound])
            }
        }
        for symbol in ["**", "__", "`", "#"] {
            text = text.replacingOccurrences(of: symbol, with: "")
        }
        let lines = text.components(separatedBy: .newlines).map { line -> String in
            var value = line.trimmingCharacters(in: .whitespaces)
            for bullet in ["- ", "* ", "• ", "– "] where value.hasPrefix(bullet) {
                value = String(value.dropFirst(bullet.count))
            }
            return value
        }
        text = lines.filter { !$0.isEmpty }.joined(separator: " ")
        text = text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        guard text.count > maxCharacters else { return text }
        let limited = String(text.prefix(maxCharacters))
        if let end = limited.lastIndex(where: { ".!?…".contains($0) }) {
            return String(limited[...end])
        }
        return limited + "…"
    }
}

// MARK: - Errors

enum JarvisBrainError: Error, Equatable {
    case unsupportedDevice
    case notInstalled
    case disabled
    case modelLoadFailed
    case generationFailed(String)
    case emptyAnswer
    case cancelled
    case notEnoughMemory(available: Int64, required: Int64)

    var message: String {
        switch self {
        case .notEnoughMemory(let available, let required):
            return "Pas assez de mémoire libre pour charger ce cerveau : \(JarvisLocalModel.gigabytes(available)) disponibles, il en faut environ \(JarvisLocalModel.gigabytes(required)). Fermez d'autres apps et réessayez, ou choisissez le cerveau Standard dans les Réglages."
        case .unsupportedDevice:
            return "Le cerveau local fonctionne sur iPhone, pas dans le simulateur."
        case .notInstalled:
            return "Pour répondre aux questions libres, installez le cerveau local : Réglages, puis Cerveau local. Il fait 1,1 Go et se télécharge une seule fois."
        case .disabled:
            return "Les réponses aux questions libres sont désactivées dans les Réglages."
        case .modelLoadFailed:
            return "Je n'ai pas pu charger le cerveau local. Fermez d'autres apps puis réessayez, ou réinstallez-le dans les Réglages."
        case .generationFailed:
            return "Le cerveau local a rencontré une erreur. Réessayez."
        case .emptyAnswer:
            return "Je n'ai pas trouvé quoi répondre. Pouvez-vous reformuler ?"
        case .cancelled:
            return "Réponse interrompue."
        }
    }
}

// MARK: - Engine (iPhone builds only)

#if canImport(llama)
/// Thin wrapper around the llama.cpp C API. Used only on the brain's serial queue.
final class JarvisLlamaEngine {
    let contextLength: Int32 = 2_048
    private var model: OpaquePointer?
    private var context: OpaquePointer?
    private var vocab: OpaquePointer?

    private static let backend: Void = {
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    init(modelPath: String) throws {
        _ = JarvisLlamaEngine.backend
        var modelParameters = llama_model_default_params()
        modelParameters.n_gpu_layers = 99
        guard let loadedModel = llama_model_load_from_file(modelPath, modelParameters) else {
            throw JarvisBrainError.modelLoadFailed
        }
        var contextParameters = llama_context_default_params()
        contextParameters.n_ctx = UInt32(contextLength)
        contextParameters.n_batch = 512
        contextParameters.n_ubatch = 512
        let threads = Int32(max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 2)))
        contextParameters.n_threads = threads
        contextParameters.n_threads_batch = threads
        guard let loadedContext = llama_init_from_model(loadedModel, contextParameters) else {
            llama_model_free(loadedModel)
            throw JarvisBrainError.modelLoadFailed
        }
        model = loadedModel
        context = loadedContext
        vocab = llama_model_get_vocab(loadedModel)
    }

    deinit {
        if let context { llama_free(context) }
        if let model { llama_model_free(model) }
    }

    /// Generates an answer for a complete ChatML prompt. `onText` receives the text
    /// decoded so far; `isCancelled` is checked before every token.
    func generate(prompt: String, maxTokens: Int, isCancelled: () -> Bool, onText: (String) -> Void) throws -> (text: String, tokens: Int) {
        guard let context, let vocab else { throw JarvisBrainError.modelLoadFailed }
        llama_memory_clear(llama_get_memory(context), true)

        var promptTokens = try tokenize(prompt, vocab: vocab)
        let limit = Int(contextLength) - maxTokens - 8
        guard limit > 0 else { throw JarvisBrainError.generationFailed("context too small") }
        if promptTokens.count > limit {
            promptTokens = Array(promptTokens.suffix(limit))
        }

        var start = 0
        while start < promptTokens.count {
            let end = min(start + 512, promptTokens.count)
            var chunk = Array(promptTokens[start..<end])
            let status = chunk.withUnsafeMutableBufferPointer { buffer in
                llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
            }
            guard status == 0 else { throw JarvisBrainError.generationFailed("prompt decode \(status)") }
            start = end
        }

        let sampler = makeSampler(vocab: vocab)
        defer { llama_sampler_free(sampler) }
        var accumulator = JarvisUTF8Accumulator()
        var piece = [CChar](repeating: 0, count: 256)
        var produced = 0
        while produced < maxTokens {
            if isCancelled() { break }
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            produced += 1
            let count = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, false)
            if count > 0 {
                accumulator.append(piece[0..<Int(count)].map { UInt8(bitPattern: $0) })
                let partial = accumulator.decodedPrefix
                if partial.contains("<|im_end|>") || partial.contains("<|im_start|>") { break }
                onText(partial)
            }
            let status = withUnsafeMutablePointer(to: &token) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            if status != 0 { break }
        }
        return (accumulator.finalText, produced)
    }

    private func tokenize(_ text: String, vocab: OpaquePointer) throws -> [llama_token] {
        let length = Int32(text.utf8.count)
        var tokens = [llama_token](repeating: 0, count: Int(length) + 16)
        var count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), true, true)
        if count < 0 {
            tokens = [llama_token](repeating: 0, count: Int(-count))
            count = llama_tokenize(vocab, text, length, &tokens, Int32(tokens.count), true, true)
        }
        guard count > 0 else { throw JarvisBrainError.generationFailed("tokenize \(count)") }
        return Array(tokens.prefix(Int(count)))
    }

    private func makeSampler(vocab: OpaquePointer) -> UnsafeMutablePointer<llama_sampler> {
        let chain = llama_sampler_chain_init(llama_sampler_chain_default_params())!
        llama_sampler_chain_add(chain, llama_sampler_init_penalties(llama_vocab_n_tokens(vocab), 64, 1.1, 0.0, 0.0))
        llama_sampler_chain_add(chain, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(chain, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(chain, llama_sampler_init_temp(0.6))
        llama_sampler_chain_add(chain, llama_sampler_init_dist(UInt32.random(in: 0...UInt32.max)))
        return chain
    }
}
#endif

// MARK: - Brain

/// Answers open questions with the on-device model. The deterministic French router
/// always runs first; the brain only gets what it could not handle, and never runs
/// actions. Public entry points and callbacks are on the main thread; the model runs
/// on a private serial queue.
final class JarvisLocalBrain {
    static let shared = JarvisLocalBrain()

    enum Availability: Equatable {
        case unsupported
        case notInstalled
        case disabled
        case ready
    }

    struct Measurement: Equatable {
        var loadSeconds: Double?
        var lastTokens = 0
        var lastSeconds: Double = 0
        var tokensPerSecond: Double { lastSeconds > 0 ? Double(lastTokens) / lastSeconds : 0 }
    }

    static var isEngineCompiled: Bool {
        #if canImport(llama)
        return true
        #else
        return false
        #endif
    }

    private let fixedModel: JarvisLocalModel?
    private let fixedDownloader: JarvisModelDownloader?
    /// The model in use: the one chosen in Settings, unless a test fixed it.
    var model: JarvisLocalModel { fixedDownloader?.model ?? fixedModel ?? JarvisLocalModel.selected }
    let maxAnswerTokens = 256
    private var downloader: JarvisModelDownloader { fixedDownloader ?? JarvisModelDownloader.downloader(for: model) }
    private let queue = DispatchQueue(label: "jarvis.local-brain", qos: .userInitiated)
    private let cancelLock = NSLock()
    private var cancelRequested = false
    private(set) var isGenerating = false
    private(set) var measurement = Measurement()
    #if canImport(llama)
    private var engine: JarvisLlamaEngine?
    /// File of the loaded engine: another brain chosen in Settings is loaded instead.
    private var enginePath: String?
    #endif

    private static let enabledKey = "JarvisXR.localBrainEnabled"

    init(model: JarvisLocalModel? = nil, downloader: JarvisModelDownloader? = nil) {
        self.fixedModel = model
        self.fixedDownloader = downloader
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.unloadIfIdle()
        }
    }

    /// « Répondre aux questions libres » (Réglages). On by default.
    var isEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Self.enabledKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.enabledKey)
            NotificationCenter.default.post(name: .jarvisLocalBrainStateChanged, object: nil)
        }
    }

    var availability: Availability {
        guard Self.isEngineCompiled else { return .unsupported }
        guard downloader.isInstalled else { return .notInstalled }
        return isEnabled ? .ready : .disabled
    }

    var statusDescription: String {
        switch availability {
        case .unsupported: return JarvisBrainError.unsupportedDevice.message
        case .notInstalled: return "Non installé. \(model.displayName), \(model.sizeDescription) à télécharger une seule fois (Wi-Fi conseillé)."
        case .disabled: return "Installé, mais désactivé pour les questions libres."
        case .ready:
            var text = "Prêt : \(model.displayName) (\(model.license)), fonctionne sans Internet."
            if measurement.lastTokens > 0 {
                text += String(format: " Dernière réponse : %.0f mots-jetons/s.", measurement.tokensPerSecond)
            }
            let available = Int64(os_proc_available_memory())
            if model.isAdvanced, available > 0 {
                text += " Mémoire libre pour Jarvis : \(JarvisLocalModel.gigabytes(available)) (il faut environ \(JarvisLocalModel.gigabytes(model.requiredMemoryBytes)))."
            }
            return text
        }
    }

    /// Shared entry point for every screen: answers an open question, or explains in
    /// French why it cannot. `onPartial` receives the answer as it is written.
    /// `allowCommands`: the PC's brain may reword a free request into a command the iPhone
    /// knows; the answer then carries `action: reroute` and the command (JarvisBrainCommand).
    func answerOpenQuestion(
        _ question: String,
        context conversation: JarvisConversationContext = .shared,
        profile: JarvisUserProfile = .shared,
        memory: JarvisMemoryStore = .shared,
        pcLink: JarvisPCLink = .shared,
        now: Date = Date(),
        allowCommands: Bool = true,
        onPartial: @escaping (String) -> Void,
        completion: @escaping (JarvisResponse) -> Void
    ) {
        // Connected mode: « Qu'est-ce que l'arrêt Blanco ? » is looked up on Wikipédia; the
        // PC's brain then explains the article in its own words, or the article's first
        // sentences are said. The brains answer alone when Wikipédia has nothing.
        if JarvisInternetSettings.isEnabled, let subject = JarvisWikipediaAnswer.subject(in: question) {
            let explained = pcLink.isConfigured && pcLink.usesPCBrain
            JarvisInternetClient.shared.wikipedia(subject, sentences: explained ? 6 : 3) { [weak self] result in
                guard case .success(let article) = result else {
                    self?.answerWithBrains(question, conversation: conversation, profile: profile, memory: memory, pcLink: pcLink, now: now,
                                           allowCommands: allowCommands, onPartial: onPartial, completion: completion)
                    return
                }
                self?.answerWithBrains(question, conversation: conversation, profile: profile, memory: memory, pcLink: pcLink, now: now,
                                       article: article, allowCommands: false, onPartial: onPartial, completion: completion)
            }
            return
        }
        answerWithBrains(question, conversation: conversation, profile: profile, memory: memory, pcLink: pcLink, now: now,
                         allowCommands: allowCommands, onPartial: onPartial, completion: completion)
    }

    /// What Wikipédia says, when no brain explains it.
    static func wikipediaResponse(_ article: (title: String, extract: String)) -> JarvisResponse {
        let answer = JarvisWikipediaAnswer.summary(article.extract)
        return .ok("D'après Wikipédia : \(answer)", display: "\(article.title) — \(JarvisWikipediaAnswer.cleaned(article.extract))\nSource : Wikipédia")
    }

    /// Jarvis PC's large brain first when it is paired and answers; otherwise the
    /// iPhone's own brain (or Wikipédia's text), so a PC that is off never leaves a
    /// question unanswered.
    private func answerWithBrains(
        _ question: String,
        conversation: JarvisConversationContext,
        profile: JarvisUserProfile,
        memory: JarvisMemoryStore,
        pcLink: JarvisPCLink,
        now: Date,
        article: (title: String, extract: String)? = nil,
        allowCommands: Bool,
        onPartial: @escaping (String) -> Void,
        completion: @escaping (JarvisResponse) -> Void
    ) {
        let withoutPC = { [weak self] in
            if let article {
                // The small brain of the iPhone would embroider: Wikipédia's own words instead.
                let response = Self.wikipediaResponse(article)
                conversation.recordTurn(user: question, assistant: response.spokenResponse)
                completion(response)
            } else {
                self?.answerOnDevice(question, conversation: conversation, profile: profile, memory: memory, now: now, onPartial: onPartial, completion: completion)
            }
        }
        guard pcLink.isConfigured, pcLink.usesPCBrain else {
            withoutPC()
            return
        }
        var context = conversation.brainContextLines() + profile.brainContextLines(memory: memory)
        if let article {
            context.append("Extrait de Wikipédia sur « \(article.title) » : \(JarvisWikipediaAnswer.cleaned(article.extract))")
        }
        var heardFromPC = false
        pcLink.ask(question: question, history: conversation.recentTurns, context: context, commands: allowCommands, onPartial: { partial in
            // « COMMANDE: … » is a rewording for the iPhone, never shown or said.
            guard !JarvisBrainCommand.mayBeCommand(partial) else { return }
            heardFromPC = true
            onPartial(partial)
        }, completion: { result in
            switch result {
            case .success(let answer):
                if let command = JarvisBrainCommand.parse(answer) {
                    completion(.ok("", display: "", data: ["action": "reroute", "text": command, "question": question], shouldSpeak: false))
                    return
                }
                conversation.recordTurn(user: question, assistant: answer)
                completion(.ok(answer))
            case .failure:
                if heardFromPC {
                    let message = "La liaison avec Jarvis PC s'est coupée pendant la réponse."
                    completion(JarvisResponse(status: .unavailable, spokenResponse: message, displayResponse: message))
                } else {
                    withoutPC()
                }
            }
        })
    }

    private func answerOnDevice(
        _ question: String,
        conversation: JarvisConversationContext,
        profile: JarvisUserProfile,
        memory: JarvisMemoryStore,
        now: Date,
        onPartial: @escaping (String) -> Void,
        completion: @escaping (JarvisResponse) -> Void
    ) {
        switch availability {
        case .unsupported:
            completion(JarvisResponse(status: .unavailable, spokenResponse: JarvisBrainError.unsupportedDevice.message, displayResponse: JarvisBrainError.unsupportedDevice.message))
            return
        case .notInstalled:
            completion(.ok(JarvisBrainError.notInstalled.message, display: "J'ai compris : « \(question) ». \(JarvisBrainError.notInstalled.message)"))
            return
        case .disabled:
            completion(JarvisResponse(status: .unavailable, spokenResponse: JarvisBrainError.disabled.message, displayResponse: JarvisBrainError.disabled.message))
            return
        case .ready:
            break
        }
        // The first name and the notes the person dictated (« Souviens-toi que… ») let the
        // brain answer « Qu'est-ce que je bois le matin ? »; everything stays on the iPhone.
        let system = JarvisChatPrompt.systemPrompt(now: now, context: conversation.brainContextLines() + profile.brainContextLines(memory: memory))
        let prompt = JarvisChatPrompt.chatML(system: system, history: conversation.recentTurns, question: question)
        generate(prompt: prompt, onPartial: onPartial) { result in
            switch result {
            case .success(let answer):
                conversation.recordTurn(user: question, assistant: answer)
                completion(.ok(answer))
            case .failure(let error):
                completion(JarvisResponse(status: .unavailable, spokenResponse: error.message, displayResponse: error.message))
            }
        }
    }

    func cancel() {
        cancelLock.lock()
        cancelRequested = true
        cancelLock.unlock()
    }

    private var isCancelled: Bool {
        cancelLock.lock()
        defer { cancelLock.unlock() }
        return cancelRequested
    }

    func unloadIfIdle() {
        guard !isGenerating else { return }
        #if canImport(llama)
        queue.async { [weak self] in
            self?.engine = nil
            self?.enginePath = nil
        }
        #endif
    }

    private func generate(prompt: String, onPartial: @escaping (String) -> Void, completion: @escaping (Result<String, JarvisBrainError>) -> Void) {
        #if canImport(llama)
        guard !isGenerating else {
            completion(.failure(.generationFailed("busy")))
            return
        }
        isGenerating = true
        cancelLock.lock()
        cancelRequested = false
        cancelLock.unlock()
        let path = downloader.modelFileURL.path
        let requiredMemory = model.requiredMemoryBytes
        let maxTokens = maxAnswerTokens
        queue.async { [weak self] in
            guard let self else { return }
            var loadSeconds: Double?
            do {
                if self.enginePath != path {
                    // Another brain was chosen in Settings: free the old one first.
                    self.engine = nil
                    self.enginePath = nil
                }
                if self.engine == nil {
                    // Refuse to load rather than let iOS close the app for lack of memory.
                    let available = Int64(os_proc_available_memory())
                    if available > 0, available < requiredMemory {
                        throw JarvisBrainError.notEnoughMemory(available: available, required: requiredMemory)
                    }
                    let loadStart = Date()
                    self.engine = try JarvisLlamaEngine(modelPath: path)
                    self.enginePath = path
                    loadSeconds = Date().timeIntervalSince(loadStart)
                }
                guard let engine = self.engine else { throw JarvisBrainError.modelLoadFailed }
                let start = Date()
                var lastPublished = Date.distantPast
                let output = try engine.generate(
                    prompt: prompt,
                    maxTokens: maxTokens,
                    isCancelled: { self.isCancelled },
                    onText: { partial in
                        let now = Date()
                        guard now.timeIntervalSince(lastPublished) > 0.15 else { return }
                        lastPublished = now
                        let cleaned = JarvisAnswerCleaner.clean(partial)
                        DispatchQueue.main.async { onPartial(cleaned) }
                    }
                )
                let seconds = Date().timeIntervalSince(start)
                let cancelled = self.isCancelled
                let answer = JarvisAnswerCleaner.clean(output.text)
                DispatchQueue.main.async {
                    self.isGenerating = false
                    if let loadSeconds { self.measurement.loadSeconds = loadSeconds }
                    self.measurement.lastTokens = output.tokens
                    self.measurement.lastSeconds = seconds
                    if cancelled {
                        completion(.failure(.cancelled))
                    } else if answer.isEmpty {
                        completion(.failure(.emptyAnswer))
                    } else {
                        completion(.success(answer))
                    }
                    NotificationCenter.default.post(name: .jarvisLocalBrainStateChanged, object: nil)
                }
            } catch let error as JarvisBrainError {
                self.engine = nil
                self.enginePath = nil
                DispatchQueue.main.async {
                    self.isGenerating = false
                    completion(.failure(error))
                }
            } catch {
                self.engine = nil
                DispatchQueue.main.async {
                    self.isGenerating = false
                    completion(.failure(.generationFailed("\(error)")))
                }
            }
        }
        #else
        completion(.failure(.unsupportedDevice))
        #endif
    }
}
