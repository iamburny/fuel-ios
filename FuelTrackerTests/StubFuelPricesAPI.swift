import Foundation
@testable import FuelTracker

enum StubError: Error { case offline, unimplemented }

/// Minimal `FuelPricesAPI` double — only `searchStations` and `getNearbyStations` are wired up;
/// everything else throws, since no test touches it.
final class StubFuelPricesAPI: FuelPricesAPI, @unchecked Sendable {
    struct RecordedSearch {
        let query: String
        let limit: Int
        let lat: Double?
        let lng: Double?
    }

    var searchShouldThrow = false
    var searchResult = StationListResponse(count: 0, stations: [])
    private(set) var recordedSearch: RecordedSearch?

    func searchStations(query: String, limit: Int, lat: Double?, lng: Double?) async throws -> StationListResponse {
        recordedSearch = RecordedSearch(query: query, limit: limit, lat: lat, lng: lng)
        if searchShouldThrow { throw StubError.offline }
        return searchResult
    }

    private(set) var nearbyRequests: [(lat: Double, lng: Double)] = []

    func getNearbyStations(lat: Double, lng: Double, radiusMiles: Double, limit: Int) async throws -> StationListResponse {
        nearbyRequests.append((lat, lng))
        return StationListResponse(count: 0, stations: [])
    }
    func getStationsInBounds(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double, limit: Int) async throws -> StationListResponse { throw StubError.unimplemented }
    func getStation(id: Int) async throws -> StationDTO { throw StubError.unimplemented }
    func getNationalAverages() async throws -> AveragesResponse { throw StubError.unimplemented }
    func getHeatmap(fuelType: String) async throws -> HeatmapResponse { throw StubError.unimplemented }
    func getPriceHistory(stationId: Int, fuelType: String, days: Int) async throws -> PriceHistoryResponse { throw StubError.unimplemented }
    func getNationalTrends(fuelType: String, days: Int) async throws -> TrendsResponse { throw StubError.unimplemented }
    func login(email: String, password: String) async throws -> TokenResponse { throw StubError.unimplemented }
    func register(_ body: RegisterRequest) async throws -> UserResponse { throw StubError.unimplemented }
    func googleLogin(_ body: GoogleLoginRequest) async throws -> TokenResponse { throw StubError.unimplemented }
    func appleLogin(_ body: AppleLoginRequest) async throws -> TokenResponse { throw StubError.unimplemented }
    func forgotPassword(_ body: ForgotPasswordRequest) async throws { throw StubError.unimplemented }
    func updateFcmToken(_ token: String) async throws { throw StubError.unimplemented }
    func deleteAccount() async throws { throw StubError.unimplemented }
    func signOut() async {}
    func getPreferences() async throws -> PreferencesDTO { throw StubError.unimplemented }
    func updatePreferences(_ body: PreferencesDTO) async throws -> PreferencesDTO { throw StubError.unimplemented }
    func getFavourites() async throws -> [FavouriteDTO] { throw StubError.unimplemented }
    func addFavourite(_ body: FavouriteCreateRequest) async throws -> FavouriteDTO { throw StubError.unimplemented }
    func updateFavourite(id: Int, _ body: FavouriteUpdateRequest) async throws -> FavouriteDTO { throw StubError.unimplemented }
    func updateFavourite(id: Int, _ body: FavouriteFuelTypeUpdateRequest) async throws -> FavouriteDTO { throw StubError.unimplemented }
    func removeFavourite(id: Int) async throws { throw StubError.unimplemented }
    func getAlerts() async throws -> [AlertSubscriptionDTO] { throw StubError.unimplemented }
    func addAlert(_ body: AlertCreateRequest) async throws -> AlertSubscriptionDTO { throw StubError.unimplemented }
    func removeAlert(id: Int) async throws { throw StubError.unimplemented }
    func reportDiscrepancy(_ body: DiscrepancyReportRequest) async throws { throw StubError.unimplemented }
    func getDiscrepancyReportUrl() async throws -> DiscrepancyReportUrlResponse { throw StubError.unimplemented }
    func getStationRatings(stationId: Int, page: Int) async throws -> PublicRatingsResponse { throw StubError.unimplemented }
    func getMyRating(stationId: Int) async throws -> MyRatingStateDTO { throw StubError.unimplemented }
    func createRating(stationId: Int, _ body: RatingInput) async throws -> RatingSaveResponse { throw StubError.unimplemented }
    func updateRating(id: Int, _ body: RatingInput) async throws -> RatingSaveResponse { throw StubError.unimplemented }
    func reportRating(id: Int, _ body: ReportRatingRequest) async throws { throw StubError.unimplemented }
    func blockRatingAuthor(ratingId: Int) async throws -> BlockAuthorResponse { throw StubError.unimplemented }
    func getBlockedReviewers() async throws -> BlockedReviewersResponse { throw StubError.unimplemented }
    func unblockReviewer(authorRef: String) async throws { throw StubError.unimplemented }
    func requestEmailVerification() async throws -> VerifyEmailResponse { throw StubError.unimplemented }
    func acceptTerms(_ body: AcceptTermsRequest) async throws { throw StubError.unimplemented }
}
