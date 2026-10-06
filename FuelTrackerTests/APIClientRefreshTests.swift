import Testing
import Foundation
import Security
@testable import FuelTracker

/// Minimal scripted `URLProtocol` stub for exercising `APIClient`'s refresh-and-retry logic
/// without touching the network. Routes by request path (refresh / logout / anything else); each
/// route consumes its canned `(status, body)` pairs in order (repeating the last one once
/// exhausted), guarded by a lock since some tests issue genuinely concurrent requests, not just
/// sequential awaits.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Route: Sendable { case refresh, logout, protected }

    private static let lock = NSLock()
    private static var responses: [Route: [(Int, Data)]] = [:]
    private static var callCounts: [Route: Int] = [:]
    private static var refreshDelay: TimeInterval = 0
    private static var hook: (@Sendable (Route, Int) -> Void)?
    private static var protectedAuthHeaders: [String?] = []
    private static var revokedRefreshTokens: [String] = []

    /// `beforeResponding` runs synchronously with the route and its 0-based call index before each
    /// response is delivered, so a test can change stored tokens at an exact point in the flow.
    /// `refreshDelay` holds back each refresh response, keeping that refresh in flight.
    static func script(
        refresh: [(Int, Data)],
        protected: [(Int, Data)],
        logout: [(Int, Data)] = [(200, Data(#"{"ok":true}"#.utf8))],
        refreshDelay: TimeInterval = 0,
        beforeResponding: (@Sendable (Route, Int) -> Void)? = nil
    ) {
        lock.withLock {
            responses = [.refresh: refresh, .protected: protected, .logout: logout]
            callCounts = [:]
            self.refreshDelay = refreshDelay
            hook = beforeResponding
            protectedAuthHeaders = []
            revokedRefreshTokens = []
        }
    }

    static func counts() -> (refresh: Int, protected: Int, logout: Int) {
        lock.withLock { (callCounts[.refresh] ?? 0, callCounts[.protected] ?? 0, callCounts[.logout] ?? 0) }
    }

    /// The `Authorization` header of each non-refresh, non-logout request, in order.
    static func authHeaders() -> [String?] {
        lock.withLock { protectedAuthHeaders }
    }

    /// The `refresh_token` sent in each `POST /api/auth/logout`, in order.
    static func revokedTokens() -> [String] {
        lock.withLock { revokedRefreshTokens }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// Sentinel status meaning "simulate a transport-level failure" (offline, timeout) rather
    /// than any real HTTP response — lets tests distinguish "the server rejected this" from
    /// "the request never got an answer at all".
    static let transportFailure = -1

    override func startLoading() {
        let path = request.url?.path ?? ""
        let route: Route = path.contains("refresh") ? .refresh : path.contains("logout") ? .logout : .protected
        let body = Self.bodyData(of: request)
        let authHeader = request.value(forHTTPHeaderField: "Authorization")
        let (index, status, data, delay, hook): (Int, Int, Data, TimeInterval, (@Sendable (Route, Int) -> Void)?) = Self.lock.withLock {
            let index = Self.callCounts[route] ?? 0
            Self.callCounts[route] = index + 1
            let scripted = Self.responses[route] ?? []
            let (status, data) = scripted[min(index, scripted.count - 1)]
            switch route {
            case .protected:
                Self.protectedAuthHeaders.append(authHeader)
            case .logout:
                if let body,
                   let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                   let token = json["refresh_token"] as? String {
                    Self.revokedRefreshTokens.append(token)
                }
            case .refresh:
                break
            }
            return (index, status, data, route == .refresh ? Self.refreshDelay : 0, Self.hook)
        }
        let respond = {
            hook?(route, index)
            self.deliver(status: status, data: data)
        }
        if delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: respond)
        } else {
            respond()
        }
    }

    override func stopLoading() {}

    private func deliver(status: Int, data: Data) {
        if status == Self.transportFailure {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    /// `URLSession` hands a protocol the body as a stream rather than `httpBody`.
    private static func bodyData(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private func jsonData(_ string: String) -> Data { string.data(using: .utf8)! }

private let refreshedPair = jsonData(#"{"access_token":"new-access","refresh_token":"new-refresh","token_type":"bearer"}"#)

private func makeClient(tokenStore: TokenStore) -> APIClient {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    return APIClient(baseURL: URL(string: "https://example.test")!, tokenStore: tokenStore, session: session)
}

/// Runs `body` with the real Keychain-backed `TokenStore`, restoring whatever session was there
/// before afterwards — the simulator running these tests may have a real signed-in session in it.
private func preservingKeychain(_ body: (TokenStore) async throws -> Void) async throws {
    let store = TokenStore()
    let savedSession = store.session
    let savedEmail = store.email
    defer {
        store.clear()
        if let savedSession { try? store.setSession(savedSession) }
        store.email = savedEmail
    }
    try await body(store)
}

/// Runs `body` against a `TokenStore` seeded with a fake expired-access/valid-refresh pair.
private func withScratchTokenStore(_ body: (TokenStore) async throws -> Void) async throws {
    try await preservingKeychain { store in
        store.clear()
        try store.setSession(TokenStore.Session(accessToken: "expired-access-token", refreshToken: "valid-refresh-token"))
        store.email = "user@example.com"
        try await body(store)
    }
}

/// Polls until `condition` holds, failing the test if it doesn't within about two seconds.
private func waitUntil(_ condition: () -> Bool) async throws {
    for _ in 0..<200 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    Issue.record("Timed out waiting for condition")
}

/// Every suite that touches the real Keychain (and `StubURLProtocol`'s static script) is nested
/// here so the whole group runs one test at a time, never in parallel with each other.
@Suite(.serialized)
enum KeychainSerializedTests {}

extension KeychainSerializedTests {
    @Suite
    struct APIClientRefreshTests {
        private let protectedEndpoint = APIEndpoint(path: "api/protected", method: .get, requiresAuth: true)

        @Test func refreshesAndRetriesOnceOn401() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, refreshedPair)],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#)), (200, jsonData("{}"))]
                )
                let client = makeClient(tokenStore: tokenStore)

                try await client.requestNoContent(protectedEndpoint)

                let counts = StubURLProtocol.counts()
                #expect(counts.refresh == 1)
                #expect(counts.protected == 2)
                #expect(StubURLProtocol.authHeaders() == ["Bearer expired-access-token", "Bearer new-access"])
                #expect(tokenStore.token == "new-access")
                #expect(tokenStore.refreshToken == "new-refresh")
            }
        }

        @Test func concurrentRequests401ingAtOnceShareASingleRefresh() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, refreshedPair)],
                    // Both initial calls 401; both retries succeed — order between the two callers is
                    // irrelevant since each only ever consumes one slot per attempt.
                    protected: [(401, jsonData("{}")), (401, jsonData("{}")), (200, jsonData("{}")), (200, jsonData("{}"))]
                )
                let client = makeClient(tokenStore: tokenStore)
                let endpoint = protectedEndpoint

                async let first: Void = client.requestNoContent(endpoint)
                async let second: Void = client.requestNoContent(endpoint)
                _ = try await (first, second)

                // The whole point of RefreshCoordinator: two concurrent 401s still only cost one
                // real POST /api/auth/refresh, not two racing (and mutually-invalidating) attempts.
                #expect(StubURLProtocol.counts().refresh == 1)
            }
        }

        /// A 400 or 401 from the refresh endpoint means the refresh token itself is no good.
        @Test(arguments: [400, 401])
        func rejectedRefreshClearsTokensAndInvokesSessionExpiredCallback(status: Int) async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(status, jsonData(#"{"detail":"Invalid or expired refresh token"}"#))],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))]
                )
                let client = makeClient(tokenStore: tokenStore)
                let sessionExpired = Counter()
                client.onSessionExpired = { await sessionExpired.increment() }

                await #expect(throws: APIError.self) {
                    try await client.requestNoContent(protectedEndpoint)
                }

                #expect(await sessionExpired.value == 1)
                #expect(tokenStore.token == nil)
                #expect(tokenStore.refreshToken == nil)
            }
        }

        /// A transient failure trying to reach the refresh endpoint (offline, timeout) must NOT be
        /// treated the same as the server explicitly rejecting the refresh token.
        @Test func transientRefreshFailureLeavesTokensIntactAndDoesNotSignOut() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(StubURLProtocol.transportFailure, Data())],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))]
                )
                let client = makeClient(tokenStore: tokenStore)
                let sessionExpired = Counter()
                client.onSessionExpired = { await sessionExpired.increment() }

                await #expect(throws: (any Error).self) {
                    try await client.requestNoContent(protectedEndpoint)
                }

                #expect(await sessionExpired.value == 0)
                #expect(StubURLProtocol.counts().refresh == 2)
                #expect(tokenStore.token == "expired-access-token")
                #expect(tokenStore.refreshToken == "valid-refresh-token")
            }
        }

        /// A refresh whose response was lost in transit is retried once at once with the same
        /// token, which the server answers with a fresh pair while the token is in its grace window.
        @Test func refreshRetriesOnceAfterTransportFailure() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(StubURLProtocol.transportFailure, Data()), (200, refreshedPair)],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#)), (200, jsonData("{}"))]
                )
                let client = makeClient(tokenStore: tokenStore)

                try await client.requestNoContent(protectedEndpoint)

                #expect(StubURLProtocol.counts().refresh == 2)
                #expect(tokenStore.token == "new-access")
                #expect(tokenStore.refreshToken == "new-refresh")
            }
        }

        /// Server errors and rate limiting say nothing about the refresh token's validity, so the
        /// session is kept for a later retry.
        @Test(arguments: [429, 500, 502, 503])
        func serverErrorFromRefreshLeavesTokensIntactAndDoesNotSignOut(status: Int) async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(status, jsonData(#"{"detail":"Unavailable"}"#))],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))]
                )
                let client = makeClient(tokenStore: tokenStore)
                let sessionExpired = Counter()
                client.onSessionExpired = { await sessionExpired.increment() }

                await #expect(throws: APIError.self) {
                    try await client.requestNoContent(protectedEndpoint)
                }

                #expect(await sessionExpired.value == 0)
                #expect(tokenStore.token == "expired-access-token")
                #expect(tokenStore.refreshToken == "valid-refresh-token")
            }
        }

        /// A 2xx means the server has already rotated the refresh token, so if the new pair can't be
        /// read the stored token is spent: keeping it would get every session revoked on its next
        /// use. The session is cleared and the request isn't retried.
        @Test(arguments: [
            #"{"refresh_token":"new-refresh"}"#,
            #"{"access_token":"new-access","token_type":"bearer"}"#,
            "not json",
        ])
        func unreadableRefreshResponseSignsOutWithoutRetrying(body: String) async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, jsonData(body))],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))]
                )
                let client = makeClient(tokenStore: tokenStore)
                let sessionExpired = Counter()
                client.onSessionExpired = { await sessionExpired.increment() }

                await #expect(throws: APIError.self) {
                    try await client.requestNoContent(protectedEndpoint)
                }

                #expect(await sessionExpired.value == 1)
                #expect(StubURLProtocol.counts().refresh == 1)
                #expect(StubURLProtocol.counts().protected == 1)
                #expect(tokenStore.session == nil)
            }
        }

        /// A login that lands while a doomed refresh is in flight must survive that refresh's refusal.
        @Test func rejectedRefreshDoesNotClearALoginThatCompletedMeanwhile() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(401, jsonData(#"{"detail":"Invalid or expired refresh token"}"#))],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))],
                    beforeResponding: { route, _ in
                        guard route == .refresh else { return }
                        try? tokenStore.setSession(TokenStore.Session(accessToken: "login-access", refreshToken: "login-refresh"))
                    }
                )
                let client = makeClient(tokenStore: tokenStore)
                let sessionExpired = Counter()
                client.onSessionExpired = { await sessionExpired.increment() }

                await #expect(throws: APIError.self) {
                    try await client.requestNoContent(protectedEndpoint)
                }

                #expect(await sessionExpired.value == 0)
                #expect(tokenStore.token == "login-access")
                #expect(tokenStore.refreshToken == "login-refresh")
            }
        }

        /// A 401 for a request sent with an access token that has since been replaced retries with
        /// the stored token instead of rotating the refresh token again.
        @Test func late401AfterTokenChangedRetriesWithoutRefreshing() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, refreshedPair)],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#)), (200, jsonData("{}"))],
                    beforeResponding: { route, index in
                        guard route == .protected, index == 0 else { return }
                        try? tokenStore.setSession(TokenStore.Session(accessToken: "fresh-access", refreshToken: "fresh-refresh"))
                    }
                )
                let client = makeClient(tokenStore: tokenStore)

                try await client.requestNoContent(protectedEndpoint)

                let counts = StubURLProtocol.counts()
                #expect(counts.refresh == 0)
                #expect(counts.protected == 2)
                #expect(StubURLProtocol.authHeaders() == ["Bearer expired-access-token", "Bearer fresh-access"])
                #expect(tokenStore.refreshToken == "fresh-refresh")
            }
        }

        @Test func signOutClearsTokensAndRevokesRefreshToken() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(refresh: [(200, refreshedPair)], protected: [(200, jsonData("{}"))])
                let client = makeClient(tokenStore: tokenStore)

                await client.signOut()

                #expect(tokenStore.session == nil)
                #expect(tokenStore.email == nil)
                #expect(StubURLProtocol.revokedTokens() == ["valid-refresh-token"])
            }
        }

        @Test func signOutStillClearsLocallyWhenRevokeCannotBeSent() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, refreshedPair)],
                    protected: [(200, jsonData("{}"))],
                    logout: [(StubURLProtocol.transportFailure, Data())]
                )
                let client = makeClient(tokenStore: tokenStore)

                await client.signOut()

                #expect(tokenStore.session == nil)
                #expect(StubURLProtocol.counts().logout == 1)
            }
        }

        /// Sign-out waits for the in-flight refresh, then revokes the token that refresh produced, and
        /// nothing is written back afterwards.
        @Test func signOutDuringInFlightRefreshRevokesNewestTokenAndStaysSignedOut() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, refreshedPair)],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#)), (200, jsonData("{}"))],
                    refreshDelay: 0.5
                )
                let client = makeClient(tokenStore: tokenStore)
                let endpoint = protectedEndpoint

                async let request: Void = client.requestNoContent(endpoint)
                try await waitUntil { StubURLProtocol.counts().refresh == 1 }
                await client.signOut()
                try? await request

                #expect(StubURLProtocol.counts().refresh == 1)
                #expect(StubURLProtocol.revokedTokens() == ["new-refresh"])
                #expect(tokenStore.session == nil)
            }
        }

        /// A user who signs in again while sign-out is still waiting on a refresh keeps that new
        /// session; only the old one is revoked.
        @Test func loginWhileSignOutWaitsOnRefreshSurvives() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, refreshedPair)],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#)), (200, jsonData("{}"))],
                    refreshDelay: 0.5
                )
                let client = makeClient(tokenStore: tokenStore)
                let endpoint = protectedEndpoint

                async let request: Void = client.requestNoContent(endpoint)
                try await waitUntil { StubURLProtocol.counts().refresh == 1 }
                async let signOut: Void = client.signOut()
                // Lets sign-out capture the old session and start waiting before the new login lands.
                try await Task.sleep(nanoseconds: 100_000_000)
                try tokenStore.setSession(TokenStore.Session(accessToken: "login-access", refreshToken: "login-refresh"))
                await signOut
                try? await request

                #expect(tokenStore.refreshToken == "login-refresh")
                #expect(StubURLProtocol.revokedTokens().contains("valid-refresh-token"))
                #expect(!StubURLProtocol.revokedTokens().contains("login-refresh"))
            }
        }

        /// A refresh whose answer arrives after the session was cleared doesn't store the rotated
        /// pair, and revokes the rotated refresh token it would otherwise orphan.
        @Test func refreshFinishingAfterSessionClearedDoesNotWriteTokensBack() async throws {
            try await withScratchTokenStore { tokenStore in
                StubURLProtocol.script(
                    refresh: [(200, refreshedPair)],
                    protected: [(401, jsonData(#"{"detail":"Invalid token"}"#))],
                    beforeResponding: { route, _ in
                        if route == .refresh { tokenStore.clear() }
                    }
                )
                let client = makeClient(tokenStore: tokenStore)

                try? await client.requestNoContent(protectedEndpoint)

                #expect(tokenStore.session == nil)
                #expect(StubURLProtocol.revokedTokens() == ["new-refresh"])
            }
        }
    }

    @Suite
    struct TokenStoreTests {
        private let service = "uk.co.fuelprices.auth"

        /// Writes an item the way the older two-item layout did, with the default accessibility.
        private func addLegacyItem(account: String, value: String) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            SecItemDelete(query as CFDictionary)
            var attributes = query
            attributes[kSecValueData as String] = Data(value.utf8)
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            #expect(SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess)
        }

        private func attributes(account: String) -> [String: Any]? {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? [String: Any]
        }

        @Test func migratesLegacyTwoItemLayoutIntoOneSessionItem() async throws {
            try await preservingKeychain { store in
                store.clear()
                addLegacyItem(account: "jwt_token", value: "legacy-access")
                addLegacyItem(account: "refresh_token", value: "legacy-refresh")
                addLegacyItem(account: "user_email", value: "legacy@example.com")

                let migrated = try TokenStore().loadSession()

                #expect(migrated == TokenStore.Session(accessToken: "legacy-access", refreshToken: "legacy-refresh"))
                #expect(attributes(account: "jwt_token") == nil)
                #expect(attributes(account: "refresh_token") == nil)
                let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
                #expect(attributes(account: "auth_session")?[kSecAttrAccessible as String] as? String == accessible)
                #expect(attributes(account: "user_email")?[kSecAttrAccessible as String] as? String == accessible)
                #expect(store.email == "legacy@example.com")
                #expect(store.isSignedIn)
            }
        }

        @Test func migratesLegacyAccessTokenWithoutRefreshToken() async throws {
            try await preservingKeychain { store in
                store.clear()
                addLegacyItem(account: "jwt_token", value: "legacy-access")

                #expect(try store.loadSession() == TokenStore.Session(accessToken: "legacy-access", refreshToken: nil))
                #expect(attributes(account: "jwt_token") == nil)
            }
        }

        /// Refreshes don't start a new generation, so a clear for the original sign-in still applies
        /// after several rotations and reports the newest refresh token.
        @Test func clearIfGenerationSurvivesRotationsButNotANewSignIn() async throws {
            try await preservingKeychain { store in
                try store.setSession(TokenStore.Session(accessToken: "a", refreshToken: "A"))
                let signedIn = store.snapshot.generation
                #expect(try store.replaceSession(ifGeneration: signedIn, refreshToken: "A", with: TokenStore.Session(accessToken: "b", refreshToken: "B")))
                #expect(try store.replaceSession(ifGeneration: signedIn, refreshToken: "B", with: TokenStore.Session(accessToken: "c", refreshToken: "C")))

                let cleared = store.clear(ifGeneration: signedIn)
                #expect(cleared?.refreshToken == "C")
                #expect(store.session == nil)

                let stale = store.snapshot.generation
                try store.setSession(TokenStore.Session(accessToken: "d", refreshToken: "D"))
                #expect(store.clear(ifGeneration: stale) == nil)
                #expect(store.refreshToken == "D")
                #expect(try store.replaceSession(ifGeneration: stale, refreshToken: "D", with: TokenStore.Session(accessToken: "e", refreshToken: "E")) == false)
                #expect(store.refreshToken == "D")
            }
        }
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
