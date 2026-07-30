import Foundation
import Observation
import UserNotifications
import UIKit
import FirebaseCore
import FirebaseMessaging

/// Ports fuel-android's `FcmService.kt`. A singleton (not part of `AppContainer`'s DI graph)
/// because `Messaging.messaging().delegate`/`UNUserNotificationCenter.current().delegate` must be
/// set from `AppDelegate.didFinishLaunchingWithOptions` — before `AppContainer` (constructed as a
/// SwiftUI `@State` on the `App` struct) is guaranteed to exist. Everything here is a no-op when
/// `GoogleService-Info.plist` hasn't been supplied (`FirebaseApp.app() == nil`), same graceful-
/// degradation pattern as the Google Maps/Sign-In keys.
///
/// Also conforms to `PushTokenProvider` — `AuthViewModel`'s existing post-login hook (from Phase 1,
/// previously wired to `NoOpPushTokenProvider`) now drives the whole permission-request ->
/// APNs-registration -> FCM-token flow at the moment a natural prompt is expected (right after
/// sign-in), matching Android's runtime `POST_NOTIFICATIONS` request timing intent.
@Observable
@MainActor
final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    /// Read by `RootView` via `.onChange` to register with the backend — kept as a plain
    /// `@Observable` property (not routed through `FuelRepository` directly) so this class stays
    /// decoupled from `AppContainer`'s construction order.
    private(set) var latestToken: String?
    /// Set when a notification is tapped with a `station_id` payload; `RootView` observes this to
    /// present Detail, then clears it back to `nil`.
    var pendingDeepLinkStationId: Int?

    private override init() {
        super.init()
    }

    func configure() {
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorizationIfNeeded() async {
        guard FirebaseApp.app() != nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        UIApplication.shared.registerForRemoteNotifications()
    }
}

extension PushNotificationManager: PushTokenProvider {
    func currentToken() async -> String? {
        guard FirebaseApp.app() != nil else { return nil }
        await requestAuthorizationIfNeeded()
        let token = try? await Messaging.messaging().token()
        if let token { latestToken = token }
        return token
    }
}

extension PushNotificationManager: MessagingDelegate {
    // Fires on initial token issuance AND rotation — mirrors Android's `onNewToken`, which
    // registers unconditionally (no login check; the backend endpoint is JWT-authenticated, so an
    // unauthenticated attempt just 401s and is swallowed as best-effort, same as here).
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in self.latestToken = fcmToken }
    }
}

extension PushNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    // Price-drop payloads are expected as a snake_case data map (station_id, fuel_type,
    // price_pence, station_name) per fuel-api's fcm.ts comment (matches what FcmService expects) —
    // extract station_id the same way, tolerant of it arriving as either a string or a number.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let data = response.notification.request.content.userInfo
        let stationId: Int?
        if let raw = data["station_id"] as? String {
            stationId = Int(raw)
        } else if let raw = data["station_id"] as? Int {
            stationId = raw
        } else {
            stationId = nil
        }
        guard let stationId else { return }
        await MainActor.run { self.pendingDeepLinkStationId = stationId }
    }
}
