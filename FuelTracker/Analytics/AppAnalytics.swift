import Foundation

/// Thin analytics abstraction — mirrors fuel-android's `AppAnalytics.kt` (a Firebase Analytics
/// wrapper whose event/param names deliberately match fuel-web's GA4 events). No-op for now;
/// Phase 8 (Extras) swaps in a real Firebase-Analytics-backed implementation. Kept as a protocol
/// so call sites in Nearby/Detail/etc. are wired with the exact final event names now, rather than
/// bolted on later.
protocol AppAnalytics: Sendable {
    func trackEvent(_ name: String, params: [String: Any])
}

struct NoOpAppAnalytics: AppAnalytics {
    func trackEvent(_ name: String, params: [String: Any]) {}
}
