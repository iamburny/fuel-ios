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
    /// Whether the first fetch is configured to ever happen at all — `false` when unconfigured
    /// (no `baseURL`/`clientKey`), so `waitForInitialLoad` knows there's nothing to wait for.
    private var isPolling = false
    /// Set once the first fetch (success or failure) completes. Plain flag rather than awaiting
    /// the fetch `Task`'s `.value` directly: `withTaskGroup`/cancellation can't actually bound an
    /// await on a `Task.value` (cancelling it doesn't unblock it, it just marks it cancelled while
    /// the underlying await keeps running) — `waitForInitialLoad`'s polling loop below only ever
    /// reads this flag, so it's genuinely decoupled from how long the network call takes.
    private var hasCompletedInitialLoad = false

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

    /// Waits (up to `timeout`) for the first poll to land, so a one-shot flag check (e.g. deciding
    /// whether to show a prompt once at cold launch) sees the real server value rather than racing
    /// it and silently falling back to `isEnabled`'s default. Returns immediately if unconfigured
    /// (nothing will ever arrive) or once the first poll has already completed. A polling loop
    /// against a wall-clock deadline, not a `Task`-cancellation race — the latter can't actually
    /// bound how long this waits, since cancelling a task awaiting another task's `.value` doesn't
    /// unblock it; the underlying network call keeps running regardless (see `hasCompletedInitialLoad`).
    func waitForInitialLoad(timeout: Duration = .seconds(2)) async {
        guard isPolling else { return }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while !hasCompletedInitialLoad && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private func startPolling() {
        guard let baseURL, let clientKey else { return }
        isPolling = true
        pollTask = Task { [weak self] in
            await self?.refresh(baseURL: baseURL, clientKey: clientKey)
            self?.hasCompletedInitialLoad = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.refresh(baseURL: baseURL, clientKey: clientKey)
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
