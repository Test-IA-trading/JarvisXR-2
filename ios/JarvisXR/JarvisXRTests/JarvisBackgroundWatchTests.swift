import XCTest
@testable import JarvisXR

/// The background watch: what waits for the screen, and what the Dynamic Island shows.
final class JarvisBackgroundWatchTests: XCTestCase {
    func testCallsMessagesAndPhotosWaitForTheScreen() {
        for action in ["phone_call", "phone_message", "photos_show", "open_camera"] {
            XCTAssertTrue(JarvisBackgroundPolicy.needsScreen(.ok("…", data: ["action": action])), action)
        }
        XCTAssertTrue(JarvisBackgroundPolicy.needsScreen(.ok("…", data: ["url_scheme": "spotify:"])))
        XCTAssertTrue(JarvisBackgroundPolicy.needsScreen(.ok("…"), opensMessage: true))
        // What is said or done without the screen goes on in the background.
        for action in ["web_weather", "pc_command", "timer_start", "steps", "where_am_i"] {
            XCTAssertFalse(JarvisBackgroundPolicy.needsScreen(.ok("…", data: ["action": action])), action)
        }
        XCTAssertFalse(JarvisBackgroundPolicy.needsScreen(.ok("Il est 15 h 40.")))
    }

    func testTheIslandStatesAreShortAndEncodable() throws {
        let watching = JarvisActivityAttributes.ContentState.watching
        XCTAssertEqual(watching.phase, .watching)
        XCTAssertEqual(watching.short, "Veille")
        let data = try JSONEncoder().encode(JarvisActivityAttributes.ContentState(phase: .needsScreen, title: "Appelle Paul", detail: "Touchez ici"))
        let decoded = try JSONDecoder().decode(JarvisActivityAttributes.ContentState.self, from: data)
        XCTAssertEqual(decoded.phase, .needsScreen)
        XCTAssertEqual(decoded.symbol, "hand.tap")
    }

    func testTheWatchNeedsTheWakeWordAndTheClaps() {
        let defaults = UserDefaults.standard
        let keys = [JarvisWakeWordSettings.enabledKey, JarvisWakeWordSettings.clapsKey, JarvisWakeWordSettings.backgroundKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        JarvisWakeWordSettings.isEnabled = true
        JarvisWakeWordSettings.clapsEnabled = true
        JarvisWakeWordSettings.worksInBackground = false
        XCTAssertFalse(JarvisWakeWordSettings.watchesInBackground, "off by default")
        JarvisWakeWordSettings.worksInBackground = true
        XCTAssertTrue(JarvisWakeWordSettings.watchesInBackground)
        JarvisWakeWordSettings.clapsEnabled = false
        XCTAssertFalse(JarvisWakeWordSettings.watchesInBackground)
    }
}
