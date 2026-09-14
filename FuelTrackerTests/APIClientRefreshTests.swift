import Testing
import Foundation
@testable import FuelTracker

/// Minimal scripted `URLProtocol` stub for exercising `APIClient`'s refresh-and-retry logic
/// without touching the network. Routes by whether the request path contains "refresh"; each
/// route consumes its canned `(status, body)` pairs in order (repeating the last one once
/// exhausted), guarded by a lock since the single-flight test issues genuinely concurrent
/// requests, not just sequential awaits.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var refreshResponses: [(Int, Data)] = []
    private static var protectedResponses: [(Int, Data)] = []
    private static var refreshCallCount = 0
    private static var protectedCallCount = 0

    static func script(refresh: [(Int, Data)], protected: [(Int, Data)]) {
        lock.withLock {
            refreshResponses = refresh
            protectedResponses = protected
            refreshCallCount = 0
            protectedCallCount = 0
        }
    }

    static func counts() -> (refresh: Int, protected: Int) {
        lock.withLock { (refreshCallCount, protectedCallCount) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Sentinel status meaning "simulate a transport-level failure" (offline, timeout) rather
    /// than any real HTTP response — lets tests distinguish "the server rejected this" from
    /// "the request never got an answer at all".
    static let transportFailure = -1

    override func startLoading() {
        let isRefresh = request.url?.path.contains("refresh") ?? false
        let (status, data): (Int, Data) = Self.lock.withLock {
            if isRefresh {
                let index = min(Self.refreshCallCount, Self.refreshResponses.count - 1)
                Self.refreshCallCount += 1
                return Self.refreshResponses[index]
            } else {
                let index = min(Self.protectedCallCount, Self.protectedResponses.count - 1)
                Self.protectedCallCount += 1
                return Self.protectedResponses[index]
            }
        }
        if status == Self.transportFailure {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private func jsonData(_ string: String) -> Data { string.data(using: .utf8)! }

private func makeClient(tokenStore: TokenStore) -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    return APIClient(baseURL: URL(string: "https://example.test")!, tokenStore: tokenStore, session: session)
}

/// Runs `body` against a `TokenStore` seeded with a fake expired-access/valid-refresh pair, then
/// restores whatever was there before — this is the real Keychain-backed `TokenStore`, and the
/// simulator running these tests may have a real signed-in session in it.
private func withScratchTokenStore(_ body: (TokenStore) async throws -> Void) async throws {
    let store = TokenStore()
    let savedToken = store.token
    let savedRefresh = store.refreshToken
    let savedEmail = store.email
    defer {
        store.token = savedToken
        store.refreshToken = savedRefresh
        store.email = savedEmail
    }
    store.token = "expired-access-token"
    store.refreshToken = "valid-refresh-token"
    store.email = "user@example.com"
    try await body(store)
}

struct APIClientRefreshTests {
    @Test func refreshesAndRetriesOnceOn401() async throws {
        try await withScratchTokenStore { tokenStore in
            StubURLProtocol.script(
                refresh: [(200, jsonData(#"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"bearer"}"#))],
                protected: [(401, jsonData(#"{"detail":"Invalid token"}"#)), (200, jsonData("{}"))]
            )
            let client = makeClient(tokenStore: tokenStore)
            let endpoint = APIEndpoint(path: "api/protected", method: .get, requiresAuth: true)

            try await client.requestNoContent(endpoint)

            let counts = StubURLProtocol.counts()
            #expect(counts.refresh == 1)
            #expect(counts.protected == 2)
            #expect(tokenStore.token == "new-access")
            #expect(tokenStore.refreshToken == "new-refresh")
        }
    }

    @Test func concurrentRequests401ingAtOnceShareASingleRefresh() async throws {
        try await withScratchTokenStore { tokenStore in
            StubURLProtocol.script(
                refresh: [(200, jsonData(#"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"bearer"}"#))],
                // Both initial calls 401; both retries succeed — order between the two callers is
                // irrelevant since each only ever consumes one slot per attempt.
                protected: [(401, jsonData("{}")), (401, jsonData("{}")), (200, jsonData("{}")), (200, jsonData("{}"))]
            )
            let client = makeClient(tokenStore: tokenStore)
            let endpoint = APIEndpoint(path: "api/protected", method: .get, requiresAuth: true)

            async let first: Void = client.requestNoContent(endpoint)
            async let second: Void = client.requestNoContent(endpoint)
            _ = try await (first, second)

            // The whole point of RefreshCoordinator: two concurrent 401s still only cost one
            // real POST /api/auth/refresh, not two racing (and mutually-invalidating) attempts.
            #expect(StubURLProtocol.counts().refresh == 1)
        }
    }

    @Test func failedRefreshClearsTokensAndInvokesSessionExpiredCallback() async throws {
        try await withScratchTokenStore { tokenStore in
            StubURLProtocol.script(
                refresh: [(401, jsonData(#"{"detail":"Invalid or expired refresh token"}"#))],
                protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))]
            )
            let client = makeClient(tokenStore: tokenStore)
            let sessionExpired = Counter()
            client.onSessionExpired = { await sessionExpired.increment() }
            let endpoint = APIEndpoint(path: "api/protected", method: .get, requiresAuth: true)

            await #expect(throws: APIError.self) {
                try await client.requestNoContent(endpoint)
            }

            #expect(await sessionExpired.value == 1)
            #expect(tokenStore.token == nil)
            #expect(tokenStore.refreshToken == nil)
        }
    }

    /// A transient failure trying to reach the refresh endpoint (offline, timeout) must NOT be
    /// treated the same as the server explicitly rejecting the refresh token — regression test
    /// for exactly that conflation, which force-signed-out users on a mere network blip.
    @Test func transientRefreshFailureLeavesTokensIntactAndDoesNotSignOut() async throws {
        try await withScratchTokenStore { tokenStore in
            StubURLProtocol.script(
                refresh: [(StubURLProtocol.transportFailure, Data())],
                protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))]
            )
            let client = makeClient(tokenStore: tokenStore)
            let sessionExpired = Counter()
            client.onSessionExpired = { await sessionExpired.increment() }
            let endpoint = APIEndpoint(path: "api/protected", method: .get, requiresAuth: true)

            await #expect(throws: (any Error).self) {
                try await client.requestNoContent(endpoint)
            }

            #expect(await sessionExpired.value == 0)
            #expect(tokenStore.token == "expired-access-token")
            #expect(tokenStore.refreshToken == "valid-refresh-token")
        }
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
