import XCTest
@testable import JarvisXR

final class JarvisPCChatTests: XCTestCase {
    func testAcceptsTheCompanionsHomeNetworkAddress() {
        for input in ["192.168.1.12", " HTTP://192.168.1.12:8765/ ", "192.168.1.12:8765"] {
            XCTAssertEqual(JarvisPCChatAddress.url(for: input)?.absoluteString, "http://192.168.1.12:8765/")
        }
        for input in ["10.0.0.3", "172.16.1.2", "172.31.255.1"] {
            XCTAssertNotNil(JarvisPCChatAddress.url(for: input))
        }
    }

    func testRejectsPublicAddressesCredentialsAndOtherRoutes() {
        for input in ["", "127.0.0.1", "192.168.1", "192.168.1.256", "172.32.1.2", "1.1.1.1",
                      "192.168.1.2:11434", "https://192.168.1.2", "evil.example", "10.1.2.3/api/chat",
                      "user@10.0.0.1", "10.0.0.1#key", "192.168.1.01", "10.0.0.1?next=x"] {
            XCTAssertNil(JarvisPCChatAddress.url(for: input), input)
        }
    }
}
