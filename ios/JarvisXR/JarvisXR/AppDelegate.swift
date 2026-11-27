import UIKit
import UserNotifications

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UIDevice.current.isBatteryMonitoringEnabled = true
        // Timers that end while JARVIS is open are shown and spoken.
        UNUserNotificationCenter.current().delegate = JarvisTimerCenter.shared
        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return JarvisDeepLinkRouter.handle(url)
    }
}
