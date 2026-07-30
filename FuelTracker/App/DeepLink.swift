import Foundation

/// Ports fuel-android's `DeepLinkTarget` (`Navigation.kt`). Resolved from a Universal Link
/// (`https://fueltracker.uk/...`) via `RootView`'s `.onOpenURL` — notification taps use their own
/// simpler `PushNotificationManager.pendingDeepLinkStationId` path (station-only, per the backend's
/// FCM payload design) rather than going through this enum, matching Android's `DeepLinkTarget`
/// being shared by both sources at the *dispatch* site, not necessarily the same Swift type.
enum DeepLink: Equatable {
    case station(Int)
    case prices
    case settings
    case home

    /// Maps a Universal Link URL to a destination. Paths mirror the fuel-web routes:
    /// `/stations/{id}` -> Detail, `/prices` -> Prices, `/settings` -> Preferences, `/` -> Nearby.
    /// Returns `nil` for any unrecognised host/path (or a non-numeric station id) so the caller can
    /// fall back to just opening the app on its default screen.
    static func from(url: URL) -> DeepLink? {
        guard let host = url.host, host.caseInsensitiveCompare("fueltracker.uk") == .orderedSame else {
            return nil
        }
        let segments = url.pathComponents.filter { $0 != "/" }
        if segments.isEmpty { return .home }
        if segments[0] == "stations", segments.count >= 2, let id = Int(segments[1]) {
            return .station(id)
        }
        if segments[0] == "prices" { return .prices }
        if segments[0] == "settings" { return .settings }
        return nil
    }
}
