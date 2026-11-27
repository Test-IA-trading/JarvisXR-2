import CoreLocation
import Foundation

/// The iPhone's position, only in connected mode (Réglages › Internet): for the weather of
/// where the user is and « Où suis-je ? ». iOS asks the user once; the position is
/// requested to about a kilometre, used for that answer and never stored.
final class JarvisLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = JarvisLocationService()

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var waiting: [(CLLocation?) -> Void] = []
    private var timeout: DispatchWorkItem?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Refused in the iOS Settings (or by a restriction).
    var isRefused: Bool {
        let status = manager.authorizationStatus
        return status == .denied || status == .restricted
    }

    /// The current position, or nil when refused, unknown or not found within 10 s.
    func currentLocation(completion: @escaping (CLLocation?) -> Void) {
        guard !isRefused else {
            completion(nil)
            return
        }
        waiting.append(completion)
        guard waiting.count == 1 else { return }
        let work = DispatchWorkItem { [weak self] in self?.finish(nil) }
        timeout = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
        if manager.authorizationStatus == .notDetermined {
            // The position is requested once the user has answered iOS.
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    /// The address iOS gives for `location` (Apple's geocoder), or nil.
    func address(of location: CLLocation, completion: @escaping (CLPlacemark?) -> Void) {
        geocoder.reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "fr_FR")) { placemarks, _ in
            completion(placemarks?.first)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard !waiting.isEmpty else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .denied, .restricted:
            finish(nil)
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(locations.last)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(nil)
    }

    private func finish(_ location: CLLocation?) {
        timeout?.cancel()
        timeout = nil
        let callbacks = waiting
        waiting = []
        callbacks.forEach { $0(location) }
    }
}
