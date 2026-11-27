import CryptoKit
import Foundation

extension Notification.Name {
    /// Posted on the main thread when the local brain's download or readiness changes.
    static let jarvisLocalBrainStateChanged = Notification.Name("JarvisLocalBrainStateChanged")
}

/// One-time, user-approved download of the local brain's model file from Hugging Face.
///
/// This is the only network path in the app (allowed explicitly by
/// tools/audit_vision_privacy.py): it fetches the pinned model file and sends no user
/// data. The file is verified by size and SHA-256, kept in Application Support and
/// excluded from iCloud backups. Everything after the download runs offline.
final class JarvisModelDownloader: NSObject, URLSessionDownloadDelegate {
    static let shared = JarvisModelDownloader(model: .qwen25Instruct1_5B)

    enum State: Equatable {
        case idle
        case downloading(received: Int64, expected: Int64)
        case verifying
        case failed(String)
    }

    let model: JarvisLocalModel
    let modelsDirectory: URL
    private(set) var state: State = .idle {
        didSet { NotificationCenter.default.post(name: .jarvisLocalBrainStateChanged, object: nil) }
    }
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var lastPublishedPercent = -1
    private let verificationQueue = DispatchQueue(label: "jarvis.model-verification", qos: .utility)

    init(model: JarvisLocalModel, directory: URL? = nil) {
        self.model = model
        if let directory {
            modelsDirectory = directory
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            modelsDirectory = support.appendingPathComponent("JarvisModels", isDirectory: true)
        }
        super.init()
    }

    var modelFileURL: URL { modelsDirectory.appendingPathComponent(model.fileName) }
    private var stagingURL: URL { modelsDirectory.appendingPathComponent(model.fileName + ".partial") }

    var isInstalled: Bool {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: modelFileURL.path))?[.size] as? NSNumber else {
            return false
        }
        return size.int64Value == model.sizeBytes
    }

    var isDownloading: Bool {
        switch state {
        case .downloading, .verifying: return true
        default: return false
        }
    }

    /// Free space on the volume, in bytes, or nil when unknown.
    var availableCapacity: Int64? {
        try? FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let values = try? modelsDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    /// French text describing the current state, for Settings.
    var stateDescription: String? {
        switch state {
        case .idle: return nil
        case .downloading(let received, let expected):
            let total = expected > 0 ? expected : model.sizeBytes
            let percent = total > 0 ? Int(Double(received) / Double(total) * 100) : 0
            return "Téléchargement : \(percent) % (\(received / 1_000_000) Mo sur \(total / 1_000_000) Mo). Gardez JARVIS ouvert."
        case .verifying: return "Vérification de l'empreinte du fichier…"
        case .failed(let message): return message
        }
    }

    /// Starts the download. Returns a French reason when it cannot start.
    @discardableResult
    func startDownload() -> String? {
        guard !isInstalled else { return nil }
        guard !isDownloading else { return nil }
        if let capacity = availableCapacity, capacity < model.sizeBytes + 300_000_000 {
            let message = "Espace insuffisant : libérez au moins \(model.sizeDescription) sur l'iPhone, puis réessayez."
            state = .failed(message)
            return message
        }
        do {
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        } catch {
            let message = "Impossible de préparer le dossier du modèle."
            state = .failed(message)
            return message
        }
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForResource = 60 * 60
        let newSession = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = newSession
        lastPublishedPercent = -1
        state = .downloading(received: 0, expected: model.sizeBytes)
        let newTask = newSession.downloadTask(with: model.downloadURL)
        task = newTask
        newTask.resume()
        return nil
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        session?.invalidateAndCancel()
        session = nil
        try? FileManager.default.removeItem(at: stagingURL)
        state = .idle
    }

    func deleteModel() {
        cancelDownload()
        try? FileManager.default.removeItem(at: modelFileURL)
        state = .idle
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 4 * 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: URLSessionDownloadDelegate (called on the session's background queue)

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : model.sizeBytes
        let percent = Int(Double(totalBytesWritten) / Double(max(expected, 1)) * 100)
        guard percent != lastPublishedPercent else { return }
        lastPublishedPercent = percent
        DispatchQueue.main.async { [weak self] in
            guard let self, case .downloading = self.state else { return }
            self.state = .downloading(received: totalBytesWritten, expected: expected)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            DispatchQueue.main.async { [weak self] in
                self?.state = .failed("Le serveur du modèle a répondu \(http.statusCode). Réessayez plus tard.")
            }
            return
        }
        // The temporary file disappears when this method returns: move it now.
        try? FileManager.default.removeItem(at: stagingURL)
        do {
            try FileManager.default.moveItem(at: location, to: stagingURL)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.state = .failed("Le fichier téléchargé n'a pas pu être enregistré.")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in self?.state = .verifying }
        verificationQueue.async { [weak self] in
            self?.verifyStagedFile()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        DispatchQueue.main.async { [weak self] in
            self?.state = .failed("Téléchargement interrompu (\(nsError.code)). Vérifiez la connexion puis réessayez.")
        }
    }

    private func verifyStagedFile() {
        let staged = stagingURL
        let size = ((try? FileManager.default.attributesOfItem(atPath: staged.path))?[.size] as? NSNumber)?.int64Value ?? -1
        let digest = (try? Self.sha256(of: staged)) ?? ""
        guard size == model.sizeBytes, digest == model.sha256 else {
            try? FileManager.default.removeItem(at: staged)
            DispatchQueue.main.async { [weak self] in
                self?.state = .failed("Le fichier téléchargé est incomplet ou différent du modèle attendu. Réessayez.")
            }
            return
        }
        do {
            try? FileManager.default.removeItem(at: modelFileURL)
            try FileManager.default.moveItem(at: staged, to: modelFileURL)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var installed = modelFileURL
            try? installed.setResourceValues(values)
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.state = .failed("Le modèle n'a pas pu être installé.")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.task = nil
            self?.session?.finishTasksAndInvalidate()
            self?.session = nil
            self?.state = .idle
        }
    }
}
