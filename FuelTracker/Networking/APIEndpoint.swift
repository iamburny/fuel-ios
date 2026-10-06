import Foundation
import os

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Describes one REST call. `requiresAuth` is table-driven per endpoint so call sites in
/// `FuelPricesAPIClient` don't need to think about attaching the Bearer token themselves.
struct APIEndpoint {
    var path: String
    var method: HTTPMethod
    var queryItems: [URLQueryItem] = []
    var jsonBody: Data? = nil
    var formBody: [String: String]? = nil
    var requiresAuth: Bool = false
}

enum APIError: Error, LocalizedError, Sendable {
    case http(status: Int, message: String?)
    /// A non-2xx answer whose body also carries a machine-readable `reason` code (the ratings
    /// endpoints' 403 blocker and 409 cooldown/edit-window answers). `body` is the raw response so
    /// a caller can decode the extra fields that come with it, such as the stored rating a 409
    /// cooldown returns. Never used for a 401, which always stays `.http` so the refresh-and-retry
    /// path below sees it.
    case rejected(status: Int, message: String?, reason: String, body: Data)
    case decoding(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .http(let status, let message): message ?? "Request failed (HTTP \(status))"
        case .rejected(let status, let message, _, _): message ?? "Request failed (HTTP \(status))"
        case .decoding(let detail): "Couldn't read the server's response (\(detail))"
        case .invalidURL: "Invalid request URL"
        }
    }

    /// The HTTP status for either HTTP-failure case, `nil` for decoding/URL failures.
    var statusCode: Int? {
        switch self {
        case .http(let status, _), .rejected(let status, _, _, _): status
        case .decoding, .invalidURL: nil
        }
    }
}

/// Mirrors the backend's uniform `{"detail": "..."}` error body, plus the optional `reason` code
/// some endpoints add.
private struct ErrorDetail: Decodable {
    let detail: String?
    let reason: String?
}

/// Single-flight coordinator for the token refresh call: when several requests 401 around the
/// same time, only the first triggers a real `POST /api/auth/refresh`; the rest await that same
/// in-flight attempt instead of each independently racing to rotate the refresh token (rotation
/// invalidates it on first use, so a second independent attempt with the same stale token would
/// itself fail).
private actor RefreshCoordinator {
    private var inFlight: Task<Void, Error>?

    func refreshOnce(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        if let inFlight {
            try await inFlight.value
            return
        }
        let task = Task { try await operation() }
        inFlight = task
        defer {
            if inFlight == task { inFlight = nil }
        }
        try await task.value
    }

    /// Runs `body` once no refresh is in flight. `body` is synchronous, so no refresh can start
    /// between the wait ending and `body` finishing.
    func afterInFlightRefresh<T: Sendable>(_ body: @Sendable () -> T) async -> T {
        while let task = inFlight {
            _ = try? await task.value
            if inFlight == task { inFlight = nil }
        }
        return body()
    }
}

/// URLSession-based API client. Auth is handled inline (reads `TokenStore`, attaches
/// `Authorization: Bearer` when `endpoint.requiresAuth`) rather than via a `URLProtocol`
/// subclass — simpler, and matches the fact that only some endpoints need it.
final class APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    private let refreshCoordinator = RefreshCoordinator()

    /// Invoked when a 401 on an authenticated call can't be recovered from — the refresh token
    /// itself is missing or was refused — after the stored tokens have been cleared. Set by
    /// `AppContainer` once `FuelRepository` exists, to flip `isLoggedIn`/`currentEmail` back to
    /// signed-out. Awaited (not fire-and-forget) so that state update happens before the
    /// triggering error reaches any caller's `catch`.
    var onSessionExpired: (@Sendable () async -> Void)? {
        get { sessionExpiredHandler.withLock { $0 } }
        set { sessionExpiredHandler.withLock { $0 = newValue } }
    }
    private let sessionExpiredHandler = OSAllocatedUnfairLock<(@Sendable () async -> Void)?>(initialState: nil)

    /// The most recent refresh-token rotation this client stored, so `signOut()` can tell the
    /// session it was asked to end apart from a new login stored while it waited.
    private struct Rotation: Sendable {
        let from: String
        let to: String
    }
    private let lastRotation = OSAllocatedUnfairLock<Rotation?>(initialState: nil)

    init(
        baseURL: URL,
        tokenStore: TokenStore,
        session: URLSession = URLSession(configuration: {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 15
            config.timeoutIntervalForResource = 30
            return config
        }())
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        self.session = session
    }

    /// Decodes a JSON response body of type `T`.
    func request<T: Decodable>(_ endpoint: APIEndpoint) async throws -> T {
        let data = try await rawRequest(endpoint)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }
    }

    /// For calls whose response body is empty/irrelevant (e.g. `DELETE`, `fcm-token`).
    func requestNoContent(_ endpoint: APIEndpoint) async throws {
        _ = try await rawRequest(endpoint)
    }

    /// Thrown by `performRefresh()` when there's no refresh token to even attempt with — distinct
    /// from a transport-level failure (offline, timeout) so `rawRequest` can tell "nothing to
    /// recover with, genuinely signed out" apart from "couldn't reach the server this time".
    private struct NoRefreshTokenStored: Error, Sendable {}

    /// Thrown by `performRefresh()` when the refresh endpoint answers 400/401: `refreshToken` is
    /// invalid, expired or revoked. Every other failure (offline, timeout, 5xx, 429, an
    /// unreadable body, a failed Keychain read or write) is transient and keeps the stored tokens.
    private struct RefreshRejected: Error, Sendable {
        let refreshToken: String
    }

    /// Exchanges the stored refresh token for a new access token (+ rotated refresh token) via
    /// `POST /api/auth/refresh`. Goes straight through `performOnce`, never `rawRequest` — this
    /// call must never itself trigger the retry-on-401 logic below.
    private func performRefresh() async throws {
        guard let refreshToken = try tokenStore.loadSession()?.refreshToken else {
            throw NoRefreshTokenStored()
        }
        let body = try RefreshRequest(refreshToken: refreshToken).asJSONData()
        let endpoint = APIEndpoint(path: "api/auth/refresh", method: .post, jsonBody: body)
        let data: Data
        do {
            data = try await performOnce(endpoint, accessToken: nil)
        } catch let error as APIError where error.statusCode == 400 || error.statusCode == 401 {
            throw RefreshRejected(refreshToken: refreshToken)
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let newRefreshToken = decoded.refreshToken ?? refreshToken
        let session = TokenStore.Session(accessToken: decoded.accessToken, refreshToken: newRefreshToken)
        let stored = try tokenStore.replaceSession(ifRefreshTokenIs: refreshToken, with: session)
        if stored {
            lastRotation.withLock { $0 = Rotation(from: refreshToken, to: newRefreshToken) }
        } else if newRefreshToken != refreshToken {
            // Signed out or signed in afresh while this was in flight; the rotated token is unused.
            await revoke(refreshToken: newRefreshToken)
        }
    }

    /// Wraps `performOnce` with a one-shot refresh-and-retry on a 401 from an authenticated call.
    /// `endpoint.requiresAuth` naturally excludes the refresh call itself (built without it) and
    /// unauthenticated calls like `/login`, where a wrong-password 401 is passed straight through.
    private func rawRequest(_ endpoint: APIEndpoint) async throws -> Data {
        let sentToken = endpoint.requiresAuth ? tokenStore.token : nil
        do {
            return try await performOnce(endpoint, accessToken: sentToken)
        } catch APIError.http(status: 401, message: let message) where endpoint.requiresAuth {
            // Another request already refreshed (or the user signed in again) after this one was
            // sent, so retry with the newer token rather than spending another rotation.
            if let currentToken = tokenStore.token, currentToken != sentToken {
                return try await performOnce(endpoint, accessToken: currentToken)
            }
            do {
                try await refreshCoordinator.refreshOnce { try await self.performRefresh() }
            } catch is NoRefreshTokenStored {
                // Nothing to recover with — genuinely signed out.
                await expireSession(ifRefreshTokenIs: nil)
                throw APIError.http(status: 401, message: message)
            } catch let rejected as RefreshRejected {
                await expireSession(ifRefreshTokenIs: rejected.refreshToken)
                throw APIError.http(status: 401, message: message)
            } catch {
                // Transient: leave the tokens intact so a later request can still recover the
                // session, instead of force-signing-out on a network blip or server hiccup.
                throw APIError.http(status: 401, message: message)
            }
            // Retry exactly once with the freshly-refreshed token. Deliberately not wrapped in
            // this same catch again — a 401 here is a genuine anomaly and should propagate
            // normally rather than loop.
            return try await performOnce(endpoint, accessToken: tokenStore.token)
        }
    }

    /// Signs out after a refused refresh, unless a newer session has been stored since (a login
    /// that completed while the refresh was in flight), which is left alone.
    private func expireSession(ifRefreshTokenIs refreshToken: String?) async {
        guard tokenStore.clear(ifRefreshTokenIs: refreshToken) else { return }
        await onSessionExpired?()
    }

    /// Clears the stored session and revokes its refresh token server-side. Waits for any
    /// in-flight refresh first, so the token revoked is the newest one (including one that refresh
    /// rotated to) and nothing is written back afterwards. A different session stored while
    /// waiting — the user signing in again — is left alone. The revoke is best-effort and never
    /// throws.
    func signOut() async {
        let tokenStore = tokenStore
        let lastRotation = lastRotation
        let signedOutToken = tokenStore.refreshToken
        let refreshToken = await refreshCoordinator.afterInFlightRefresh { () -> String? in
            var refreshToken = signedOutToken
            if let rotation = lastRotation.withLock({ $0 }), rotation.from == refreshToken {
                refreshToken = rotation.to
            }
            _ = tokenStore.clear(ifRefreshTokenIs: refreshToken)
            return refreshToken
        }
        if let refreshToken {
            await revoke(refreshToken: refreshToken)
        }
    }

    /// `POST /api/auth/logout` — unauthenticated and always 200 for any token, so the only
    /// possible failures are transport errors, which are ignored.
    private func revoke(refreshToken: String) async {
        guard let body = try? LogoutRequest(refreshToken: refreshToken).asJSONData() else { return }
        let endpoint = APIEndpoint(path: "api/auth/logout", method: .post, jsonBody: body)
        _ = try? await performOnce(endpoint, accessToken: nil)
    }

    /// Attaches `accessToken` as the Bearer token when `endpoint.requiresAuth`.
    private func performOnce(_ endpoint: APIEndpoint, accessToken: String?) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(endpoint.path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue

        if let formBody = endpoint.formBody {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            var formComponents = URLComponents()
            formComponents.queryItems = formBody.map { URLQueryItem(name: $0.key, value: $0.value) }
            request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
        } else if let jsonBody = endpoint.jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonBody
        }

        if endpoint.requiresAuth, let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, message: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let errorBody = try? JSONDecoder().decode(ErrorDetail.self, from: data)
            if http.statusCode != 401, let reason = errorBody?.reason, !reason.isEmpty {
                throw APIError.rejected(status: http.statusCode, message: errorBody?.detail, reason: reason, body: data)
            }
            throw APIError.http(status: http.statusCode, message: errorBody?.detail)
        }
        return data
    }
}

extension Encodable {
    func asJSONData(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }
}
