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
}
