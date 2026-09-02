import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
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

/// URLSession-based API client. Auth is handled inline (reads `TokenStore`, attaches
/// `Authorization: Bearer` when `endpoint.requiresAuth`) rather than via a `URLProtocol`
/// subclass — simpler, and matches the fact that only some endpoints need it.
final class APIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore

    init(baseURL: URL, tokenStore: TokenStore) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
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

    private func rawRequest(_ endpoint: APIEndpoint) async throws -> Data {
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
