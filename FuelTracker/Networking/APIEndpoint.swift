import Foundation

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
    case decoding(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .http(let status, let message): message ?? "Request failed (HTTP \(status))"
        case .decoding(let detail): "Couldn't read the server's response (\(detail))"
        case .invalidURL: "Invalid request URL"
        }
    }
}

/// Mirrors the backend's uniform `{"detail": "..."}` error body.
private struct ErrorDetail: Decodable {
    let detail: String?
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
        do {
            try await task.value
            inFlight = nil
        } catch {
            inFlight = nil
            throw error
        }
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
    /// itself is missing/invalid/expired. Set by `AppContainer` once `FuelRepository` exists, to
    /// flip `isLoggedIn`/`currentEmail` back to signed-out. Awaited (not fire-and-forget) so that
    /// state update happens before the triggering error reaches any caller's `catch`.
    var onSessionExpired: (@Sendable () async -> Void)?

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

    /// Exchanges the stored refresh token for a new access token (+ rotated refresh token) via
    /// `POST /api/auth/refresh`. Goes straight through `performOnce`, never `rawRequest` — this
    /// call must never itself trigger the retry-on-401 logic below.
    private func performRefresh() async throws {
        guard let refreshToken = tokenStore.refreshToken else {
            throw NoRefreshTokenStored()
        }
        let body = try RefreshRequest(refreshToken: refreshToken).asJSONData()
        let endpoint = APIEndpoint(path: "api/auth/refresh", method: .post, jsonBody: body)
        let data = try await performOnce(endpoint)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        tokenStore.token = decoded.accessToken
        if let newRefreshToken = decoded.refreshToken {
            tokenStore.refreshToken = newRefreshToken
        }
    }

    /// Wraps `performOnce` with a one-shot refresh-and-retry on a 401 from an authenticated call.
    /// `endpoint.requiresAuth` naturally excludes the refresh call itself (built without it) and
    /// unauthenticated calls like `/login` (a wrong-password 401 there is untouched, same as
    /// before this existed).
    private func rawRequest(_ endpoint: APIEndpoint) async throws -> Data {
        do {
            return try await performOnce(endpoint)
        } catch APIError.http(status: 401, message: let message) where endpoint.requiresAuth {
            do {
                try await refreshCoordinator.refreshOnce { try await self.performRefresh() }
            } catch is NoRefreshTokenStored {
                // Nothing to recover with — genuinely signed out.
                await onSessionExpired?()
                tokenStore.clear()
                throw APIError.http(status: 401, message: message)
            } catch APIError.http {
                // The refresh endpoint itself gave a definitive HTTP rejection — the refresh
                // token is invalid/expired/revoked. Genuinely signed out.
                await onSessionExpired?()
                tokenStore.clear()
                throw APIError.http(status: 401, message: message)
            } catch {
                // A transient failure while trying to refresh — offline, timeout, or a decoding
                // hiccup on the refresh response — not a rejection of the refresh token itself.
                // Leave the tokens intact so a later retry (once connectivity returns) can still
                // recover the session, instead of force-signing-out on a network blip.
                throw APIError.http(status: 401, message: message)
            }
            // Retry exactly once with the freshly-refreshed token. Deliberately not wrapped in
            // this same catch again — a 401 here is a genuine anomaly and should propagate
            // normally rather than loop.
            return try await performOnce(endpoint)
        }
    }

    private func performOnce(_ endpoint: APIEndpoint) async throws -> Data {
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

        if endpoint.requiresAuth, let token = tokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(status: -1, message: nil)
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorDetail.self, from: data))?.detail
            throw APIError.http(status: http.statusCode, message: message)
        }
        return data
    }
}

extension Encodable {
    func asJSONData(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }
}
