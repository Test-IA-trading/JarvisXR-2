import Contacts
import CoreMotion
import MessageUI
import Photos
import UIKit

// The iPhone's own data, read on the iPhone only and only when asked: contacts (to call
// or write to someone), steps (the motion coprocessor), photos. iOS asks the user once for
// each; nothing is stored by Jarvis or sent anywhere. Calls and messages always end in
// iOS's own confirmation: the call prompt, or the message window where the user taps Send.

enum JarvisDeviceFailure: Error, Equatable {
    case refused(String)
    case unavailable(String)
    case notFound(String)

    var message: String {
        switch self {
        case .refused(let text), .unavailable(let text), .notFound(let text):
            return text
        }
    }
}

// MARK: - Contacts

final class JarvisContactsService {
    static let shared = JarvisContactsService()
    static let refusedMessage = "Je n'ai pas accès à vos contacts : autorisez-les pour JARVIS dans Réglages iOS › Applications › JARVIS › Contacts."

    private let store = CNContactStore()
    private let queue = DispatchQueue(label: "JarvisXR.contacts", qos: .userInitiated)

    /// The contacts that have a phone number, read away from the main thread.
    func candidates(completion: @escaping (Result<[JarvisContactCandidate], JarvisDeviceFailure>) -> Void) {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            load(completion)
        case .notDetermined:
            store.requestAccess(for: .contacts) { [weak self] granted, _ in
                DispatchQueue.main.async {
                    guard granted, let self else {
                        completion(.failure(.refused(Self.refusedMessage)))
                        return
                    }
                    self.load(completion)
                }
            }
        case .denied, .restricted:
            completion(.failure(.refused(Self.refusedMessage)))
        @unknown default:
            completion(.failure(.refused(Self.refusedMessage)))
        }
    }

    private func load(_ completion: @escaping (Result<[JarvisContactCandidate], JarvisDeviceFailure>) -> Void) {
        let store = self.store
        queue.async {
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactNicknameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            ]
            var found: [JarvisContactCandidate] = []
            var failed = false
            do {
                try store.enumerateContacts(with: CNContactFetchRequest(keysToFetch: keys)) { contact, _ in
                    guard !contact.phoneNumbers.isEmpty else { return }
                    let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                    let name = formatted.isEmpty ? (contact.nickname.isEmpty ? contact.organizationName : contact.nickname) : formatted
                    let phones = contact.phoneNumbers.map { JarvisPhone(label: $0.label, number: $0.value.stringValue) }
                    found.append(JarvisContactCandidate(
                        identifier: contact.identifier,
                        displayName: name,
                        givenName: contact.givenName,
                        familyName: contact.familyName,
                        nickname: contact.nickname,
                        organization: contact.organizationName,
                        phones: phones
                    ))
                }
            } catch {
                failed = true
            }
            let result: Result<[JarvisContactCandidate], JarvisDeviceFailure> = failed
                ? .failure(.unavailable("Je n'arrive pas à lire vos contacts pour le moment."))
                : .success(found)
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// MARK: - Calls and messages

enum JarvisTopScreen {
    /// The screen on top, to show iOS's message window or the photos over it.
    static func controller() -> UIViewController? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

enum JarvisPhoneActions {
    /// iOS asks « Appeler … ? » before anything is dialled.
    static func call(_ number: String, completion: @escaping (Bool) -> Void) {
        let digits = JarvisContactMatcher.dialable(number)
        guard digits.count >= 3, let url = URL(string: "tel:\(digits)") else {
            completion(false)
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            completion(opened)
        }
    }
}

/// iOS's message window, filled with the recipient and the words: the user sends it.
final class JarvisQuickMessage: NSObject, MFMessageComposeViewControllerDelegate {
    static let shared = JarvisQuickMessage()

    func compose(to number: String, body: String?) -> Bool {
        guard MFMessageComposeViewController.canSendText(), let presenter = JarvisTopScreen.controller() else { return false }
        let composer = MFMessageComposeViewController()
        composer.messageComposeDelegate = self
        composer.recipients = [number]
        composer.body = body
        presenter.present(composer, animated: !UIAccessibility.isReduceMotionEnabled)
        return true
    }

    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        controller.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
    }
}

// MARK: - Steps

final class JarvisStepCounter {
    static let shared = JarvisStepCounter()
    static let refusedMessage = "Je n'ai pas accès à vos mouvements : autorisez « Mouvements et forme » pour JARVIS dans Réglages iOS › Applications › JARVIS."

    private let pedometer = CMPedometer()

    /// Steps, distance and floors from the iPhone's motion coprocessor (the last 7 days).
    func steps(during period: JarvisDevicePeriod, now: Date = Date(), completion: @escaping (Result<String, JarvisDeviceFailure>) -> Void) {
        guard CMPedometer.isStepCountingAvailable() else {
            completion(.failure(.unavailable("Cet iPhone ne compte pas les pas.")))
            return
        }
        let status = CMPedometer.authorizationStatus()
        guard status != .denied, status != .restricted else {
            completion(.failure(.refused(Self.refusedMessage)))
            return
        }
        let interval = period.interval(now: now)
        pedometer.queryPedometerData(from: interval.start, to: interval.end) { data, error in
            let result: Result<String, JarvisDeviceFailure>
            if let data, error == nil {
                result = .success(JarvisDeviceSentences.steps(
                    data.numberOfSteps.intValue,
                    meters: data.distance?.doubleValue,
                    floors: data.floorsAscended?.intValue,
                    period: period
                ))
            } else if CMPedometer.authorizationStatus() == .denied {
                result = .failure(.refused(Self.refusedMessage))
            } else {
                result = .failure(.unavailable("Je n'arrive pas à lire vos pas pour le moment."))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

// MARK: - Photos

final class JarvisPhotoLibrary {
    static let shared = JarvisPhotoLibrary()
    static let refusedMessage = "Je n'ai pas accès à vos photos : autorisez-les pour JARVIS dans Réglages iOS › Applications › JARVIS › Photos."

    private func authorize(_ completion: @escaping (Bool) -> Void) {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized, .limited:
            completion(true)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async { completion(status == .authorized || status == .limited) }
            }
        default:
            completion(false)
        }
    }

    private static func options(_ interval: DateInterval?, limit: Int = 0) -> PHFetchOptions {
        let options = PHFetchOptions()
        if let interval {
            options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", interval.start as NSDate, interval.end as NSDate)
        }
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if limit > 0 { options.fetchLimit = limit }
        return options
    }

    /// « Hier, vous avez pris 12 photos et 2 vidéos. »
    func count(during period: JarvisDevicePeriod, now: Date = Date(), completion: @escaping (Result<String, JarvisDeviceFailure>) -> Void) {
        authorize { allowed in
            guard allowed else {
                completion(.failure(.refused(Self.refusedMessage)))
                return
            }
            let interval = period.interval(now: now)
            let photos = PHAsset.fetchAssets(with: .image, options: Self.options(interval)).count
            let videos = PHAsset.fetchAssets(with: .video, options: Self.options(interval)).count
            completion(.success(JarvisDeviceSentences.photoCount(photos: photos, videos: videos, period: period)))
        }
    }

    /// Shows the latest photo, or those of the period (the 12 most recent).
    func show(during period: JarvisDevicePeriod, latestOnly: Bool, now: Date = Date(), completion: @escaping (Result<String, JarvisDeviceFailure>) -> Void) {
        authorize { allowed in
            guard allowed else {
                completion(.failure(.refused(Self.refusedMessage)))
                return
            }
            let interval = latestOnly ? nil : period.interval(now: now)
            var assets: [PHAsset] = []
            PHAsset.fetchAssets(with: .image, options: Self.options(interval, limit: latestOnly ? 1 : 12)).enumerateObjects { asset, _, _ in
                assets.append(asset)
            }
            guard let first = assets.first else {
                completion(.failure(.notFound(latestOnly ? "Je ne trouve aucune photo sur cet iPhone." : "\(period.opening), vous n'avez pris aucune photo.")))
                return
            }
            let total = latestOnly ? 1 : PHAsset.fetchAssets(with: .image, options: Self.options(interval)).count
            let title = latestOnly ? "Dernière photo" : "\(period.opening) : \(total) \(total == 1 ? "photo" : "photos")"
            guard JarvisPhotoViewer.present(assets, title: title) else {
                completion(.failure(.unavailable("Fermez l'écran en cours, puis redemandez vos photos.")))
                return
            }
            if latestOnly {
                completion(.success(JarvisDeviceSentences.latestPhoto(taken: first.creationDate ?? now, now: now)))
            } else {
                let shown = total > assets.count ? " Voici les \(assets.count) plus récentes." : ""
                completion(.success(JarvisDeviceSentences.photoCount(photos: total, videos: 0, period: period) + shown))
            }
        }
    }
}

/// The photos asked for, one under the other, with their date for VoiceOver.
final class JarvisPhotoViewer: UIViewController {
    private let assets: [PHAsset]
    private let heading: String
    private let stack = UIStackView()
    private let manager = PHCachingImageManager()

    init(assets: [PHAsset], title: String) {
        self.assets = assets
        self.heading = title
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    static func present(_ assets: [PHAsset], title: String) -> Bool {
        guard let presenter = JarvisTopScreen.controller() else { return false }
        let navigation = UINavigationController(rootViewController: JarvisPhotoViewer(assets: assets, title: title))
        presenter.present(navigation, animated: !UIAccessibility.isReduceMotionEnabled)
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        title = heading
        navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
        })

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -12),
        ])

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.dateFormat = "EEEE d MMMM yyyy 'à' H 'h' mm"
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        for asset in assets {
            let imageView = UIImageView()
            imageView.contentMode = .scaleAspectFit
            imageView.clipsToBounds = true
            imageView.backgroundColor = UIColor(white: 0.12, alpha: 1)
            imageView.isAccessibilityElement = true
            imageView.accessibilityLabel = asset.creationDate.map { "Photo du \(formatter.string(from: $0))" } ?? "Photo"
            let ratio = asset.pixelWidth > 0 ? CGFloat(asset.pixelHeight) / CGFloat(asset.pixelWidth) : 1
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: min(max(ratio, 0.3), 2.5)).isActive = true
            stack.addArrangedSubview(imageView)
            manager.requestImage(for: asset, targetSize: CGSize(width: 1200, height: 1200), contentMode: .aspectFit, options: options) { [weak imageView] image, _ in
                DispatchQueue.main.async { imageView?.image = image }
            }
        }
    }
}

// MARK: - The actions the French router asks for

enum JarvisDeviceActions {
    static let actions: Set<String> = ["phone_call", "phone_message", "phone_number", "steps", "photos_count", "photos_show"]

    static func perform(_ data: [String: String], now: Date, completion: @escaping (JarvisResponse) -> Void) {
        let fail: (JarvisDeviceFailure) -> Void = { failure in
            completion(JarvisResponse(status: .unavailable, spokenResponse: failure.message, displayResponse: failure.message))
        }
        let period = JarvisDevicePeriod(rawValue: data["period"] ?? "") ?? .today
        switch data["action"] {
        case "steps":
            JarvisStepCounter.shared.steps(during: period, now: now) { result in
                switch result {
                case .success(let text): completion(.ok(text))
                case .failure(let failure): fail(failure)
                }
            }
        case "photos_count":
            JarvisPhotoLibrary.shared.count(during: period, now: now) { result in
                switch result {
                case .success(let text): completion(.ok(text))
                case .failure(let failure): fail(failure)
                }
            }
        case "photos_show":
            JarvisPhotoLibrary.shared.show(during: period, latestOnly: data["latest"] == "1", now: now) { result in
                switch result {
                case .success(let text): completion(.ok(text))
                case .failure(let failure): fail(failure)
                }
            }
        default:
            contactAction(data, completion: completion, fail: fail)
        }
    }

    private static func contactAction(_ data: [String: String], completion: @escaping (JarvisResponse) -> Void, fail: @escaping (JarvisDeviceFailure) -> Void) {
        let spoken = data["name"] ?? ""
        let action = data["action"] ?? ""
        // « Appelle le 06 12 34 56 78 »: a number, no contact needed.
        if action == "phone_call", spoken.filter(\.isNumber).count >= 6 {
            JarvisPhoneActions.call(spoken) { opened in
                if opened {
                    completion(.ok("J'appelle ce numéro.", display: "Appel : \(spoken)"))
                } else {
                    fail(.unavailable("Cet iPhone ne peut pas passer cet appel."))
                }
            }
            return
        }
        JarvisContactsService.shared.candidates { result in
            switch result {
            case .failure(let failure):
                fail(failure)
            case .success(let candidates):
                var match = JarvisContactMatcher.match(spoken, in: candidates)
                var body = data["body"]
                // « Écris à Paul j'arrive »: the longest start of the words that is a contact.
                if case .nobody = match, action == "phone_message", body == nil {
                    let words = spoken.split(separator: " ").map(String.init)
                    for count in stride(from: words.count - 1, to: 0, by: -1) {
                        let shorter = JarvisContactMatcher.match(words.prefix(count).joined(separator: " "), in: candidates)
                        if case .nobody = shorter { continue }
                        match = shorter
                        body = words.dropFirst(count).joined(separator: " ")
                        break
                    }
                }
                switch match {
                case .nobody:
                    fail(.notFound("Je ne trouve pas « \(spoken) » dans vos contacts."))
                case .several(let list):
                    let question = "J'ai plusieurs contacts pour « \(spoken) » : \(JarvisContactMatcher.choices(list)). Lequel ?"
                    completion(JarvisResponse(status: .confirmationRequired, spokenResponse: question, displayResponse: question))
                case .one(let contact):
                    guard let phone = JarvisContactMatcher.preferredPhone(contact.phones) else {
                        fail(.notFound("\(contact.displayName) n'a pas de numéro de téléphone."))
                        return
                    }
                    run(action, for: contact, phone: phone, body: body, completion: completion, fail: fail)
                }
            }
        }
    }

    private static func run(_ action: String, for contact: JarvisContactCandidate, phone: JarvisPhone, body: String?, completion: @escaping (JarvisResponse) -> Void, fail: @escaping (JarvisDeviceFailure) -> Void) {
        switch action {
        case "phone_number":
            completion(.ok("Le numéro de \(contact.displayName) est le \(phone.number).", display: "\(contact.displayName) : \(phone.number)"))
        case "phone_call":
            JarvisPhoneActions.call(phone.number) { opened in
                if opened {
                    completion(.ok("J'appelle \(contact.displayName).", display: "Appel de \(contact.displayName) : confirmez dans la fenêtre d'iOS."))
                } else {
                    fail(.unavailable("Cet iPhone ne peut pas appeler \(contact.displayName)."))
                }
            }
        default:
            guard JarvisQuickMessage.shared.compose(to: phone.number, body: body) else {
                fail(.unavailable("Les messages ne sont pas disponibles sur cet iPhone."))
                return
            }
            let said = body.map { "Message pour \(contact.displayName) : « \($0) ». Touchez Envoyer pour l'envoyer." }
                ?? "J'ouvre un message pour \(contact.displayName) : écrivez-le, puis touchez Envoyer."
            completion(.ok(said))
        }
    }
}
