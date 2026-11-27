import ActivityKit
import Foundation

extension JarvisWakeWordSettings {
    static let backgroundKey = "JarvisXR.wakeInBackground"

    /// Jarvis keeps listening for two claps when the user leaves the app (not once it is
    /// closed from the app switcher). Off by default: the microphone then stays on.
    static var worksInBackground: Bool {
        get { UserDefaults.standard.bool(forKey: backgroundKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundKey) }
    }

    /// Everything the background watch needs is on.
    static var watchesInBackground: Bool { isEnabled && clapsEnabled && worksInBackground }
}

/// What Jarvis can do from the background, and what needs the screen first: iOS shows a
/// call's confirmation, the message window or the photos only to an app on screen.
enum JarvisBackgroundPolicy {
    static let screenActions: Set<String> = [
        "phone_call", "phone_message", "photos_show", "open_camera", "inspect", "ar_cube", "ar_summary",
        "diagnostics", "settings", "control_mesh",
    ]

    static func needsScreen(_ response: JarvisResponse, opensVision: Bool = false, opensMessage: Bool = false) -> Bool {
        if opensVision || opensMessage || response.data["url_scheme"] != nil { return true }
        guard let action = response.data["action"] else { return false }
        return screenActions.contains(action)
    }

    /// Said when the request waits for the screen.
    static let waitingForScreen = "Pour cela, il me faut l'écran : touchez la Dynamic Island, et je m'en occupe."

    /// A request kept for the screen is run when Jarvis opens within this delay.
    static let pendingLifetime: TimeInterval = 180
}

/// The Dynamic Island and the lock screen of the background watch (JarvisXRWidgets).
/// iOS lets an app start a Live Activity only while it is on screen; it is then updated
/// from the background as Jarvis listens and answers. It lasts at most 8 hours, and is
/// started again each time Jarvis comes back on screen.
final class JarvisLiveActivity {
    static let shared = JarvisLiveActivity()

    private var activity: Activity<JarvisActivityAttributes>?
    private var current = JarvisActivityAttributes.ContentState.watching
    private var restoreWork: DispatchWorkItem?
    /// Why it could not start (Diagnostics).
    private(set) var lastFailure: String?

    var isRunning: Bool { activity != nil }

    /// Starts the activity, on screen only, and ends any left by an earlier launch.
    func start() {
        for stale in Activity<JarvisActivityAttributes>.activities where stale.id != activity?.id {
            Task { await stale.end(nil, dismissalPolicy: .immediate) }
        }
        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastFailure = "Activités en direct désactivées pour JARVIS dans les Réglages d'iOS."
            return
        }
        current = .watching
        do {
            activity = try Activity<JarvisActivityAttributes>.request(attributes: JarvisActivityAttributes(), content: content(for: current), pushType: nil)
            lastFailure = nil
        } catch {
            lastFailure = (error as NSError).localizedDescription
        }
    }

    func stop() {
        restoreWork?.cancel()
        restoreWork = nil
        guard let activity else { return }
        self.activity = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Shows what Jarvis is doing. With `backToWatch`, « En veille » comes back after that delay.
    func show(_ phase: JarvisActivityAttributes.ContentState.Phase, title: String, detail: String, backToWatch: TimeInterval? = nil) {
        guard let activity else { return }
        restoreWork?.cancel()
        restoreWork = nil
        let state = JarvisActivityAttributes.ContentState(phase: phase, title: String(title.prefix(60)), detail: String(detail.prefix(180)))
        if state != current {
            current = state
            let content = content(for: state)
            Task { await activity.update(content) }
        }
        guard let backToWatch else { return }
        let work = DispatchWorkItem { [weak self] in
            let watching = JarvisActivityAttributes.ContentState.watching
            self?.show(watching.phase, title: watching.title, detail: watching.detail)
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + backToWatch, execute: work)
    }

    private func content(for state: JarvisActivityAttributes.ContentState) -> ActivityContent<JarvisActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(8 * 3600))
    }
}
