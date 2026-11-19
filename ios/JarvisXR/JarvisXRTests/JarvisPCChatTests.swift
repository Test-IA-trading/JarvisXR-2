import XCTest
@testable import JarvisXR

final class JarvisPCChatTests: XCTestCase {
    func testAcceptsTheCompanionsHomeNetworkAddress() {
        for input in ["192.168.1.12", " HTTP://192.168.1.12:8765/ ", "192.168.1.12:8765"] {
            XCTAssertEqual(JarvisPCChatAddress(input)?.url.absoluteString, "http://192.168.1.12:8765/")
        }
        for input in ["10.0.0.3", "172.16.1.2", "172.31.255.1"] {
            XCTAssertNotNil(JarvisPCChatAddress(input))
        }
    }

    func testRejectsPublicAddressesCredentialsAndOtherRoutes() {
        for input in ["", "127.0.0.1", "192.168.1", "192.168.1.256", "172.32.1.2", "1.1.1.1",
                      "192.168.1.2:11434", "https://192.168.1.2", "evil.example", "10.1.2.3/api/chat",
                      "user@10.0.0.1", "10.0.0.1#key", "192.168.1.01", "10.0.0.1?next=x"] {
            XCTAssertNil(JarvisPCChatAddress(input), input)
        }
    }

    func testVoiceChatRequestUsesOnlyThePairedEndpoint() throws {
        let address = try XCTUnwrap(JarvisPCChatAddress("192.168.1.12"))
        let transport = JarvisPCChatTransport(address: address, code: "pairing-code")
        let messages = [["role": "user", "content": "Bonjour Jarvis"]]
        let request = try transport.makeRequest(messages)
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.12:8765/api/chat")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Jarvis-Code"), "pairing-code")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let data = try XCTUnwrap(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: data) as? [String: [[String: String]]]
        XCTAssertEqual(payload, ["messages": messages])
    }

    func testChatDeclinesHTTPRedirects() throws {
        let endpoint = try XCTUnwrap(URL(string: "http://192.168.1.12:8765/api/chat"))
        let other = try XCTUnwrap(URL(string: "https://example.invalid/redirect"))
        let response = try XCTUnwrap(HTTPURLResponse(url: endpoint, statusCode: 307,
            httpVersion: "HTTP/1.1", headerFields: ["Location": other.absoluteString]))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        var called = false
        JarvisPCChatRedirectPolicy().urlSession(session, task: session.dataTask(with: endpoint),
            willPerformHTTPRedirection: response, newRequest: URLRequest(url: other)) { proposed in
            XCTAssertNil(proposed)
            called = true
        }
        XCTAssertTrue(called)
    }
}
