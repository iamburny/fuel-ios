import Foundation
import Observation

private struct UnleashPayload: Decodable {
    let type: String
    let value: String
}

private struct UnleashVariant: Decodable {
    let name: String
    let enabled: Bool
    let payload: UnleashPayload?
}

private struct UnleashToggle: Decodable {
    let name: String
    let enabled: Bool
    let variant: UnleashVariant?
}

private struct UnleashResponse: Decodable {
    let toggles: [UnleashToggle]
}

/// Ports fuel-android's `FeatureFlags.kt` — a thin wrapper around a self-hosted Unleash instance
/// (shared across all fuel-tracker apps). Android uses the official Unleash Android SDK against
/// Unleash's lightweight "Frontend API"; there's no equivalent official Swift SDK, so this talks
/// to the same Frontend API directly via `URLSession` (`GET {url}/api/frontend`,
/// `Authorization: <clientKey>` header — the same protocol, just hand-rolled).
///
/// Gracefully degrades when `UNLEASH_CLIENT_KEY` is empty (no polling at all) — `isEnabled` then
/// always returns its caller-supplied default, matching Android's exact fallback behaviour, so
/// every flag-gated feature in this app keeps working (using its default state) with zero Unleash
/// configuration.
@Observable
@MainActor
final class FeatureFlags {
    /// Bumped on every successful poll — call sites that need to react to a flag changing (rather
    /// than just reading it once) can observe this, mirroring Android's `version: StateFlow<Int>`.
    private(set) var version = 0

    private var toggles: [String: UnleashToggle] = [:]
    private let baseURL: URL?
    private let clientKey: String?
    private var pollTask: Task<Void, Never>?

    init(url: String?, clientKey: String?) {
        if let url, !url.isEmpty, let base = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)) {
            baseURL = base.appendingPathComponent("api/frontend")
        } else {
            baseURL = nil
        }
        self.clientKey = (clientKey?.isEmpty ?? true) ? nil : clientKey
        startPolling()
    }

    func isEnabled(_ name: String, default defaultValue: Bool = false) -> Bool {
        toggles[name]?.enabled ?? defaultValue
    }

    /// The active variant's text payload for a flag, or `nil` when inactive/no payload.
    func variantText(_ name: String) -> String? {
        guard let variant = toggles[name]?.variant, variant.enabled else { return nil }
        return variant.payload?.value
    }

    private func startPolling() {
        guard let baseURL, let clientKey else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(baseURL: baseURL, clientKey: clientKey)
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func refresh(baseURL: URL, clientKey: String) async {
        var request = URLRequest(url: baseURL)
        request.setValue(clientKey, forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(UnleashResponse.self, from: data) else {
            return
        }
        // uniquingKeysWith rather than uniqueKeysWithValues: a server-side duplicate toggle name
        // should never crash the app on every poll — keep whichever entry sorts last.
        toggles = Dictionary(decoded.toggles.map { ($0.name, $0) }, uniquingKeysWith: { _, latest in latest })
        version += 1
    }
}
