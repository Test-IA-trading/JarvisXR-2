import CoreLocation
import Foundation

/// The connected mode's only network path (Réglages › Internet, off by default):
/// Open-Meteo for the weather, Wikipédia for « Qui est… ? » and franceinfo for the news,
/// free and without account. Each is sent only what it needs: a city or a position
/// rounded to about a kilometre, the subject searched, or nothing for the news. Never a
/// recording, a frame, a note or the conversation.
final class JarvisInternetClient {
    static let shared = JarvisInternetClient()

    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            // No cache and no cookies; a generic name instead of the device's.
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 15
            configuration.httpAdditionalHeaders = ["User-Agent": "JarvisXR/2.0 (assistant personnel)"]
            self.session = URLSession(configuration: configuration)
        }
    }

    static func url(host: String, path: String, query: [(String, String)] = []) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        }
        return components.url
    }

    // MARK: Requests

    private func fetch(_ url: URL?, completion: @escaping (Result<Data, JarvisInternetFailure>) -> Void) {
        guard JarvisInternetSettings.isEnabled else {
            completion(.failure(.disabled))
            return
        }
        guard !JarvisEmergencyStop.shared.isEngaged else {
            completion(.failure(.stopped))
            return
        }
        guard let url else {
            completion(.failure(.unreadable))
            return
        }
        // The financial guard (JarvisCostGuard): only services free for Jarvis are called.
        guard JarvisCostGuard.permits(url) else {
            JarvisCostGuard.noteRefusal(url)
            completion(.failure(.notFree(url.host ?? "")))
            return
        }
        session.dataTask(with: url) { data, response, error in
            let result: Result<Data, JarvisInternetFailure>
            if error != nil {
                result = .failure(.unreachable)
            } else if let data, (response as? HTTPURLResponse)?.statusCode == 200 {
                result = .success(data)
            } else {
                result = .failure(.unreadable)
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    private func fetchJSON(_ url: URL?, completion: @escaping (Result<[String: Any], JarvisInternetFailure>) -> Void) {
        fetch(url) { result in
            completion(result.flatMap { (data: Data) -> Result<[String: Any], JarvisInternetFailure> in
                guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return .failure(.unreadable) }
                return .success(object)
            })
        }
    }

    // MARK: Weather (Open-Meteo)

    func geocode(_ city: String, completion: @escaping (Result<JarvisPlace, JarvisInternetFailure>) -> Void) {
        let url = Self.url(host: "geocoding-api.open-meteo.com", path: "/v1/search", query: [
            ("name", city), ("count", "1"), ("language", "fr"), ("format", "json"),
        ])
        fetchJSON(url) { result in
            completion(result.flatMap { (object: [String: Any]) -> Result<JarvisPlace, JarvisInternetFailure> in
                guard let place = JarvisWeatherReport.place(fromGeocoding: object) else { return .failure(.unknownCity(city)) }
                return .success(place)
            })
        }
    }

    func forecast(latitude: Double, longitude: Double, completion: @escaping (Result<[String: Any], JarvisInternetFailure>) -> Void) {
        let url = Self.url(host: "api.open-meteo.com", path: "/v1/forecast", query: [
            ("latitude", JarvisWeatherReport.rounded(latitude)),
            ("longitude", JarvisWeatherReport.rounded(longitude)),
            ("current", "temperature_2m,apparent_temperature,weather_code,wind_speed_10m"),
            ("daily", "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            ("timezone", "auto"),
            ("forecast_days", "3"),
        ])
        fetchJSON(url, completion: completion)
    }

    /// The weather sentence for `city`; without one, for where the iPhone is (when the
    /// position is used and allowed), else for the saved city.
    func weather(city: String?, dayOffset: Int, completion: @escaping (Result<String, JarvisInternetFailure>) -> Void) {
        guard JarvisInternetSettings.isEnabled else {
            completion(.failure(.disabled))
            return
        }
        if let city {
            weather(ofCity: city, dayOffset: dayOffset, completion: completion)
            return
        }
        let savedCity = JarvisInternetSettings.city
        guard JarvisInternetSettings.usesLocation else {
            if let savedCity {
                weather(ofCity: savedCity, dayOffset: dayOffset, completion: completion)
            } else {
                completion(.failure(.noPlace))
            }
            return
        }
        JarvisLocationService.shared.currentLocation { [weak self] location in
            guard let self else { return }
            guard let location else {
                if let savedCity {
                    self.weather(ofCity: savedCity, dayOffset: dayOffset, completion: completion)
                } else {
                    completion(.failure(.noPlace))
                }
                return
            }
            self.weather(at: location, dayOffset: dayOffset, completion: completion)
        }
    }

    private func weather(ofCity city: String, dayOffset: Int, completion: @escaping (Result<String, JarvisInternetFailure>) -> Void) {
        geocode(city) { [weak self] result in
            switch result {
            case .failure(let failure):
                completion(.failure(failure))
            case .success(let place):
                self?.forecast(latitude: place.latitude, longitude: place.longitude) { forecast in
                    completion(forecast.flatMap { (object: [String: Any]) -> Result<String, JarvisInternetFailure> in
                        guard let text = JarvisWeatherReport.sentence(place: place.name, forecast: object, dayOffset: dayOffset) else { return .failure(.unreadable) }
                        return .success(text)
                    })
                }
            }
        }
    }

    /// The forecast and the town's name, asked at the same time.
    private func weather(at location: CLLocation, dayOffset: Int, completion: @escaping (Result<String, JarvisInternetFailure>) -> Void) {
        let found = WeatherParts()
        let group = DispatchGroup()
        group.enter()
        JarvisLocationService.shared.address(of: location) { placemark in
            found.town = placemark?.locality
            group.leave()
        }
        group.enter()
        forecast(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude) { result in
            found.forecast = result
            group.leave()
        }
        group.notify(queue: .main) {
            switch found.forecast {
            case .success(let object)?:
                if let text = JarvisWeatherReport.sentence(place: found.town, forecast: object, dayOffset: dayOffset) {
                    completion(.success(text))
                } else {
                    completion(.failure(.unreadable))
                }
            case .failure(let failure)?:
                completion(.failure(failure))
            case nil:
                completion(.failure(.unreadable))
            }
        }
    }

    private final class WeatherParts {
        var town: String?
        var forecast: Result<[String: Any], JarvisInternetFailure>?
    }

    // MARK: « Où suis-je ? »

    func whereAmI(completion: @escaping (Result<(spoken: String, display: String), JarvisInternetFailure>) -> Void) {
        guard JarvisInternetSettings.isEnabled else {
            completion(.failure(.disabled))
            return
        }
        JarvisLocationService.shared.currentLocation { location in
            guard let location else {
                completion(.failure(.noPosition))
                return
            }
            JarvisLocationService.shared.address(of: location) { placemark in
                guard let placemark,
                      let answer = JarvisWhereAmI.answer(number: placemark.subThoroughfare, street: placemark.thoroughfare, postalCode: placemark.postalCode, town: placemark.locality, country: placemark.country) else {
                    completion(.failure(.unreachable))
                    return
                }
                completion(.success(answer))
            }
        }
    }

    // MARK: Wikipédia

    /// The best article for `subject`: its title and its first two sentences.
    /// The best article for `subject`: its title and the first `sentences` of its introduction.
    func wikipedia(_ subject: String, sentences: Int = 2, completion: @escaping (Result<(title: String, extract: String), JarvisInternetFailure>) -> Void) {
        let url = Self.url(host: "fr.wikipedia.org", path: "/w/api.php", query: [
            ("action", "query"), ("format", "json"), ("formatversion", "2"),
            ("generator", "search"), ("gsrsearch", subject), ("gsrlimit", "1"),
            ("prop", "extracts|pageprops"), ("ppprop", "disambiguation"),
            ("exintro", "1"), ("explaintext", "1"), ("exsentences", String(max(1, min(sentences, 10)))), ("redirects", "1"),
        ])
        fetchJSON(url) { result in
            completion(result.flatMap { (object: [String: Any]) -> Result<(title: String, extract: String), JarvisInternetFailure> in
                guard let article = JarvisWikipediaAnswer.article(from: object) else { return .failure(.notFound) }
                return .success(article)
            })
        }
    }

    // MARK: News (franceinfo)

    func news(limit: Int = 5, completion: @escaping (Result<[String], JarvisInternetFailure>) -> Void) {
        fetch(Self.url(host: "www.francetvinfo.fr", path: "/titres.rss")) { result in
            completion(result.flatMap { (data: Data) -> Result<[String], JarvisInternetFailure> in
                let titles = JarvisNewsFeedParser.titles(from: data, limit: limit)
                return titles.isEmpty ? .failure(.unreadable) : .success(titles)
            })
        }
    }
}
