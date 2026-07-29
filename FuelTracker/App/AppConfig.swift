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
}
