import Foundation

struct DiscrepancyReportUrlResponse: Decodable, Sendable {
    let url: String
    let message: String
}

/// One function per backend endpoint — direct port of fuel-android's `FuelPricesApi.kt` Retrofit
/// interface. Trailing slashes on favourites/alerts/discrepancy paths are intentional, matching
/// the Android client exactly (the backend's Express routes are mounted with them).
protocol FuelPricesAPI: Sendable {
    func getNearbyStations(lat: Double, lng: Double, radiusMiles: Double) async throws -> StationListResponse
    func getStationsInBounds(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) async throws -> StationListResponse
    func getStation(id: Int) async throws -> StationDTO
    func searchStations(query: String) async throws -> StationListResponse

    func getCheapest(fuelType: String, lat: Double?, lng: Double?, radiusMiles: Double) async throws -> CheapestResponse
    func getNationalAverages() async throws -> AveragesResponse
    func getHeatmap(fuelType: String) async throws -> HeatmapResponse
    func getPriceHistory(stationId: Int, fuelType: String, days: Int) async throws -> PriceHistoryResponse
    func getNationalTrends(fuelType: String, days: Int) async throws -> TrendsResponse

    func login(email: String, password: String) async throws -> TokenResponse
    func register(_ body: RegisterRequest) async throws -> UserResponse
    func googleLogin(_ body: GoogleLoginRequest) async throws -> TokenResponse
    func appleLogin(_ body: AppleLoginRequest) async throws -> TokenResponse
    func forgotPassword(_ body: ForgotPasswordRequest) async throws
    func updateFcmToken(_ token: String) async throws

    func getFavourites() async throws -> [FavouriteDTO]
    func addFavourite(_ body: FavouriteCreateRequest) async throws -> FavouriteDTO
    func removeFavourite(id: Int) async throws

    func getAlerts() async throws -> [AlertSubscriptionDTO]
    func addAlert(_ body: AlertCreateRequest) async throws -> AlertSubscriptionDTO
    func removeAlert(id: Int) async throws

    func reportDiscrepancy(_ body: DiscrepancyReportRequest) async throws
    func getDiscrepancyReportUrl() async throws -> DiscrepancyReportUrlResponse
}

final class FuelPricesAPIClient: FuelPricesAPI {
    private let client: APIClient
    private let encoder = JSONEncoder()

    init(client: APIClient) {
        self.client = client
    }

    // MARK: - Stations

    func getNearbyStations(lat: Double, lng: Double, radiusMiles: Double) async throws -> StationListResponse {
        try await client.request(APIEndpoint(
            path: "api/stations/nearby", method: .get,
            queryItems: [
                .init(name: "lat", value: "\(lat)"),
                .init(name: "lng", value: "\(lng)"),
                .init(name: "radius_miles", value: "\(radiusMiles)"),
            ]
        ))
    }

    func getStationsInBounds(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) async throws -> StationListResponse {
        try await client.request(APIEndpoint(
            path: "api/stations/bounds", method: .get,
            queryItems: [
                .init(name: "min_lat", value: "\(minLat)"),
                .init(name: "max_lat", value: "\(maxLat)"),
                .init(name: "min_lng", value: "\(minLng)"),
                .init(name: "max_lng", value: "\(maxLng)"),
            ]
        ))
    }

    func getStation(id: Int) async throws -> StationDTO {
        try await client.request(APIEndpoint(path: "api/stations/\(id)", method: .get))
    }

    func searchStations(query: String) async throws -> StationListResponse {
        try await client.request(APIEndpoint(
            path: "api/stations/search/", method: .get,
            queryItems: [.init(name: "q", value: query)]
        ))
    }

    // MARK: - Prices

    func getCheapest(fuelType: String, lat: Double?, lng: Double?, radiusMiles: Double) async throws -> CheapestResponse {
        var items = [URLQueryItem(name: "fuel_type", value: fuelType), .init(name: "radius_miles", value: "\(radiusMiles)")]
        if let lat { items.append(.init(name: "lat", value: "\(lat)")) }
        if let lng { items.append(.init(name: "lng", value: "\(lng)")) }
        return try await client.request(APIEndpoint(path: "api/prices/cheapest", method: .get, queryItems: items))
    }

    func getNationalAverages() async throws -> AveragesResponse {
        try await client.request(APIEndpoint(path: "api/prices/averages", method: .get))
    }

    func getHeatmap(fuelType: String) async throws -> HeatmapResponse {
        try await client.request(APIEndpoint(
            path: "api/prices/heatmap", method: .get,
            queryItems: [.init(name: "fuel_type", value: fuelType)]
        ))
    }

    func getPriceHistory(stationId: Int, fuelType: String, days: Int) async throws -> PriceHistoryResponse {
        try await client.request(APIEndpoint(
            path: "api/prices/history/\(stationId)", method: .get,
            queryItems: [.init(name: "fuel_type", value: fuelType), .init(name: "days", value: "\(days)")]
        ))
    }

    func getNationalTrends(fuelType: String, days: Int) async throws -> TrendsResponse {
        try await client.request(APIEndpoint(
            path: "api/prices/trends", method: .get,
            queryItems: [.init(name: "fuel_type", value: fuelType), .init(name: "days", value: "\(days)")]
        ))
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> TokenResponse {
        try await client.request(APIEndpoint(
            path: "api/auth/login", method: .post,
            formBody: ["username": email, "password": password]
        ))
    }

    func register(_ body: RegisterRequest) async throws -> UserResponse {
        try await client.request(APIEndpoint(path: "api/auth/register", method: .post, jsonBody: try body.asJSONData(encoder: encoder)))
    }

    func googleLogin(_ body: GoogleLoginRequest) async throws -> TokenResponse {
        try await client.request(APIEndpoint(path: "api/auth/google", method: .post, jsonBody: try body.asJSONData(encoder: encoder)))
    }

    func appleLogin(_ body: AppleLoginRequest) async throws -> TokenResponse {
        try await client.request(APIEndpoint(path: "api/auth/apple", method: .post, jsonBody: try body.asJSONData(encoder: encoder)))
    }

    func forgotPassword(_ body: ForgotPasswordRequest) async throws {
        try await client.requestNoContent(APIEndpoint(path: "api/auth/forgot-password", method: .post, jsonBody: try body.asJSONData(encoder: encoder)))
    }

    func updateFcmToken(_ token: String) async throws {
        try await client.requestNoContent(APIEndpoint(
            path: "api/auth/fcm-token", method: .post,
            queryItems: [.init(name: "fcm_token", value: token)],
            requiresAuth: true
        ))
    }

    // MARK: - Favourites

    func getFavourites() async throws -> [FavouriteDTO] {
        try await client.request(APIEndpoint(path: "api/favourites/", method: .get, requiresAuth: true))
    }

    func addFavourite(_ body: FavouriteCreateRequest) async throws -> FavouriteDTO {
        try await client.request(APIEndpoint(path: "api/favourites/", method: .post, jsonBody: try body.asJSONData(encoder: encoder), requiresAuth: true))
    }

    func removeFavourite(id: Int) async throws {
        try await client.requestNoContent(APIEndpoint(path: "api/favourites/\(id)", method: .delete, requiresAuth: true))
    }

    // MARK: - Area alerts

    func getAlerts() async throws -> [AlertSubscriptionDTO] {
        try await client.request(APIEndpoint(path: "api/alerts/", method: .get, requiresAuth: true))
    }

    func addAlert(_ body: AlertCreateRequest) async throws -> AlertSubscriptionDTO {
        try await client.request(APIEndpoint(path: "api/alerts/", method: .post, jsonBody: try body.asJSONData(encoder: encoder), requiresAuth: true))
    }

    func removeAlert(id: Int) async throws {
        try await client.requestNoContent(APIEndpoint(path: "api/alerts/\(id)", method: .delete, requiresAuth: true))
    }

    // MARK: - Discrepancy

    func reportDiscrepancy(_ body: DiscrepancyReportRequest) async throws {
        try await client.requestNoContent(APIEndpoint(path: "api/discrepancy/", method: .post, jsonBody: try body.asJSONData(encoder: encoder)))
    }

    func getDiscrepancyReportUrl() async throws -> DiscrepancyReportUrlResponse {
        try await client.request(APIEndpoint(path: "api/discrepancy/report-url", method: .get))
    }
}
