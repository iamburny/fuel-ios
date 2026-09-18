import Testing
import Foundation
@testable import FuelTracker

/// Captures the single request it receives (method/path/headers/body) rather than just counting
/// calls — `HTTPMethod.patch` and `FuelPricesAPIClient.updateFavourite` are both new as of this
/// change, so the thing actually worth verifying is that a PATCH genuinely goes out with the
/// right method, auth header, and JSON body, not just that *some* 200 came back.
private final class CapturingURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var captured: URLRequest?
    private static var responseData = Data("{}".utf8)

    static func reset(respondingWith data: Data) {
        lock.withLock {
            captured = nil
            responseData = data
        }
    }

    static func lastRequest() -> URLRequest? {
        lock.withLock { captured }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession commonly hands a small request body to a custom URLProtocol as
        // `httpBodyStream` rather than `httpBody`, even though the caller (APIClient) set it via
        // `request.httpBody = jsonBody` — so `request.httpBody` alone is unreliable here.
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let stream = capturedRequest.httpBodyStream {
            capturedRequest.httpBody = Self.readAll(stream)
        }
        let data = Self.lock.withLock {
            Self.captured = capturedRequest
            return Self.responseData
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAll(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
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

struct FavouritesAPIPatchTests {
    @Test func updateFavouriteIssuesPatchWithBodyAndAuthHeader() async throws {
        let tokenStore = TokenStore()
        let savedToken = tokenStore.token
        defer { tokenStore.token = savedToken }
        tokenStore.token = "test-access-token"

        CapturingURLProtocol.reset(respondingWith: Data(
            #"{"id":5,"station_id":501,"fuel_type":"E10","notify_on_drop":false,"price_threshold_pence":null}"#.utf8
        ))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        let apiClient = APIClient(baseURL: URL(string: "https://example.test")!, tokenStore: tokenStore, session: session)
        let api = FuelPricesAPIClient(client: apiClient)

        let updated = try await api.updateFavourite(id: 5, FavouriteUpdateRequest(notifyOnDrop: false))

        let request = CapturingURLProtocol.lastRequest()
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.url?.path == "/api/favourites/5")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        let sentBody = try request?.httpBody.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(sentBody??["notify_on_drop"] as? Bool == false)

        #expect(updated.id == 5)
        #expect(updated.notifyOnDrop == false)
    }

    @Test func updateFavouriteFuelTypeIssuesPatchWithBodyAndAuthHeader() async throws {
        let tokenStore = TokenStore()
        let savedToken = tokenStore.token
        defer { tokenStore.token = savedToken }
        tokenStore.token = "test-access-token"

        CapturingURLProtocol.reset(respondingWith: Data(
            #"{"id":5,"station_id":501,"fuel_type":"HVO","notify_on_drop":true,"price_threshold_pence":null}"#.utf8
        ))

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let session = URLSession(configuration: config)
        let apiClient = APIClient(baseURL: URL(string: "https://example.test")!, tokenStore: tokenStore, session: session)
        let api = FuelPricesAPIClient(client: apiClient)

        let updated = try await api.updateFavourite(id: 5, FavouriteFuelTypeUpdateRequest(fuelType: "HVO"))

        let request = CapturingURLProtocol.lastRequest()
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.url?.path == "/api/favourites/5")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        let sentBody = try request?.httpBody.map { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        #expect(sentBody??["fuel_type"] as? String == "HVO")

        #expect(updated.id == 5)
        #expect(updated.fuelType == "HVO")
    }
}
