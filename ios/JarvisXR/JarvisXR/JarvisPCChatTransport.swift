import Foundation

final class JarvisPCChatRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

final class JarvisPCChatTransport {
    enum Response {
        case reply(String)
        case failure(String)
    }

    private let endpoint: URL
    private let code: String
    private let session: URLSession

    init(address: JarvisPCChatAddress, code: String) {
        endpoint = address.url.appendingPathComponent("api/chat")
        self.code = code
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 185
        config.timeoutIntervalForResource = 190
        config.allowsCellularAccess = false
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.urlCredentialStorage = nil
        session = URLSession(configuration: config, delegate: JarvisPCChatRedirectPolicy(), delegateQueue: .main)
    }

    deinit { session.invalidateAndCancel() }

    func makeRequest(_ messages: [[String: String]]) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(code, forHTTPHeaderField: "X-Jarvis-Code")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["messages": messages])
        return request
    }

    func send(_ messages: [[String: String]], completion: @escaping (Response) -> Void) throws -> () -> Void {
        let request = try makeRequest(messages)
        let task = session.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse, let data else {
                completion(.failure("PC inaccessible. Vérifie le Wi-Fi, l’adresse et le compagnon Windows."))
                return
            }
            let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            guard http.statusCode == 200, let reply = body?["reply"] as? String,
                  !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                completion(.failure((body?["error"] as? String) ?? "Le PC a interrompu la demande."))
                return
            }
            completion(.reply(reply))
        }
        task.resume()
        return { task.cancel() }
    }
}
