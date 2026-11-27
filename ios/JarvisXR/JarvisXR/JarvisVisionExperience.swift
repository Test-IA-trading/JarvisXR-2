import Foundation

enum JarvisVisionCommand: String, Codable, Equatable, Sendable {
    case run
    case stop
    case pause
    case resume
    case repeatLast
    case moreDetail
    case lessDetail
    case whatChanged
    case nextReadingLine
    case previousReadingLine
    case flashlightOn
    case flashlightOff
    case flashlightStatus
    case checkQuality
}

/// Typed launch information shared by commands, deep links, App Intents, and the
/// native Vision screen. OCR and barcode result payloads never belong here.
struct JarvisVisionLaunchRequest: Codable, Equatable, Sendable {
    var mode: VisionMode
    var command: JarvisVisionCommand
    var target: String?
    var region: SpatialRegion?
    var source: String
    var startsImmediately: Bool

    init(
        mode: VisionMode = .describe,
        command: JarvisVisionCommand = .run,
        target: String? = nil,
        region: SpatialRegion? = nil,
        source: String = "in_app",
        startsImmediately: Bool = false
    ) {
        self.mode = mode
        self.command = command
        self.target = target?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.region = region
        self.source = source
        self.startsImmediately = startsImmediately
    }

    var excludesResultFromGeneralHistory: Bool {
        mode == .readText || mode == .scanBarcode || command == .repeatLast
    }
}

extension VisionMode {
    var visionDisplayName: String {
        switch self {
        case .inactive: return "Vision"
        case .describe: return "Décrire"
        case .liveGuide: return "Guide en direct"
        case .find: return "Trouver"
        case .readText: return "Lire"
        case .scanBarcode: return "Code-barres"
        case .identifyColor: return "Couleur"
        }
    }

    var visionPrimaryActionTitle: String {
        switch self {
        case .inactive, .describe: return "Décrire ce qui est là"
        case .liveGuide: return "Lancer le guide en direct"
        case .find: return "Choisir un objet à trouver"
        case .readText: return "Capturer et lire"
        case .scanBarcode: return "Lancer le scan de code-barres"
        case .identifyColor: return "Identifier la couleur"
        }
    }

    var visionReadyGuidance: String {
        switch self {
        case .inactive, .describe:
            return "Orientez la caméra arrière vers ce que vous voulez décrire."
        case .liveGuide:
            return "Le guide en direct annonce une fois chaque objet qui apparaît, bouge ou disparaît, tant que Jarvis reste ouvert."
        case .find:
            return "Nommez un objet reconnu, puis balayez lentement avec le téléphone."
        case .readText:
            return "Tenez le texte imprimé immobile et cadrez-le en entier."
        case .scanBarcode:
            return "Passez lentement la caméra sur l'emballage ou le code."
        case .identifyColor:
            return "Placez la surface à identifier au centre de l'image."
        }
    }
}

extension Notification.Name {
    static let jarvisVisionPreferencesDidChange = Notification.Name("JarvisVisionPreferencesDidChange")
}

final class VisionPreferencesStore {
    static let shared = VisionPreferencesStore()

    private let key = "JarvisXR.vision.preferences.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var storedValue: VisionPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key),
           let decoded = try? decoder.decode(VisionPreferences.self, from: data) {
            storedValue = decoded
        } else {
            storedValue = .default
        }
    }

    var value: VisionPreferences {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func update(_ mutation: (inout VisionPreferences) -> Void) {
        lock.lock()
        mutation(&storedValue)
        let value = storedValue
        let data = try? encoder.encode(value)
        lock.unlock()
        if let data {
            defaults.set(data, forKey: key)
        }
        NotificationCenter.default.post(name: .jarvisVisionPreferencesDidChange, object: value)
    }

    func reset() {
        lock.lock()
        storedValue = .default
        lock.unlock()
        defaults.removeObject(forKey: key)
        NotificationCenter.default.post(name: .jarvisVisionPreferencesDidChange, object: VisionPreferences.default)
    }
}

final class JarvisVisionFirstRunStore {
    static let shared = JarvisVisionFirstRunStore()

    private let defaults: UserDefaults
    private let completedKey = "JarvisXR.vision.firstRun.completed.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var shouldPresent: Bool {
        !defaults.bool(forKey: completedKey)
    }

    func markCompleted() {
        defaults.set(true, forKey: completedKey)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
