import Foundation
import FirebaseAnalytics
import FirebaseCore

/// Thin analytics abstraction — mirrors fuel-android's `AppAnalytics.kt` (a Firebase Analytics
/// wrapper whose event/param names deliberately match fuel-web's GA4 events, so the same
/// interaction reads as one event across platforms in GA4 rather than differently-named ones).
/// Kept as a protocol so call sites in Nearby/Detail/etc. were wired with the exact final event
/// names from the start, rather than bolted on later.
protocol AppAnalytics: Sendable {
    func trackEvent(_ name: String, params: [String: Any])
}

struct NoOpAppAnalytics: AppAnalytics {
    func trackEvent(_ name: String, params: [String: Any]) {}
}

/// Gated on `FirebaseApp.app() != nil` (i.e. whether `GoogleService-Info.plist` was supplied) —
/// same graceful-no-op pattern as `PushNotificationManager`. `Analytics.logEvent` itself is safe
/// to call before configuration (it silently no-ops per Firebase's own docs), but the guard keeps
/// this consistent with the rest of the app's Firebase-touching code and makes the dependency
/// explicit rather than relying on that undocumented-feeling leniency.
struct FirebaseAppAnalytics: AppAnalytics {
    func trackEvent(_ name: String, params: [String: Any]) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: params)
    }
}
