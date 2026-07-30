import Foundation

/// Reads the per-build-configuration `API_BASE_URL` baked into Info.plist via the active
/// xcconfig (`Config/Debug.xcconfig` / `Config/Release.xcconfig`) — the iOS equivalent of
/// Android's `BuildConfig.API_BASE_URL`.
enum AppConfig {
    static var apiBaseURL: URL {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
              !raw.isEmpty, let url = URL(string: raw) else {
            fatalError("APIBaseURL missing/invalid in Info.plist — check Config/*.xcconfig")
        }
        return url
    }

    /// Google Sign-In web/server client ID. Unlike `apiBaseURL`, absence here isn't fatal — it
    /// mirrors Android's `BuildConfig.GOOGLE_WEB_CLIENT_ID.isBlank()` guard: the "Continue with
    /// Google" button degrades to a friendly "not configured yet" message instead of crashing
    /// when no real OAuth client ID has been supplied via `Config/Secrets.xcconfig`.
    static var googleClientID: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GoogleClientID") as? String, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    /// Google Maps iOS SDK key. Also non-fatal when absent — `FuelMapView` shows a "Maps not
    /// configured" placeholder rather than crashing the whole app (map screens are important but
    /// shouldn't take down Prices/Favourites/Settings if a fresh checkout has no Secrets.xcconfig).
    static var googleMapsAPIKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsAPIKey") as? String, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    /// Self-hosted Unleash Frontend API base URL. Non-secret — hardcoded to match Android's
    /// `fuel-android/core/build.gradle.kts` value directly in the xcconfigs rather than routed
    /// through `Secrets.xcconfig`.
    static var unleashURL: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "UnleashURL") as? String, !raw.isEmpty else {
            return nil
        }
        return raw
    }

    /// Unleash Frontend API client key. Secret — absence means `FeatureFlags` simply never polls
    /// and every flag falls back to its call-site default, the same graceful-degradation pattern
    /// as the other credentials above.
    static var unleashClientKey: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "UnleashClientKey") as? String, !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
