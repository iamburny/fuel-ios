import UIKit
import FirebaseCore
import FirebaseMessaging

/// The one piece of push-notification setup that must live in a `UIApplicationDelegate` rather
/// than SwiftUI's `App`/`Scene` lifecycle: `didRegisterForRemoteNotificationsWithDeviceToken` is a
/// UIKit-only callback with no SwiftUI equivalent. `FirebaseApp.configure()` is gated on
/// `GoogleService-Info.plist` actually being present so a fresh checkout without one still builds
/// and runs — push notifications just stay inert (same pattern as the Maps/Sign-In keys).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }
        PushNotificationManager.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}
