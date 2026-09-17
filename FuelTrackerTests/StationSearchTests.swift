import Testing
import Foundation
import SwiftData
@testable import FuelTracker

// MARK: - Query building

/// `/api/stations/search` takes `lat`/`lng` as *optional* params: supplied, they become the
/// within-relevance-tier distance tie-break and the response gains `distance_miles`; omitted, the
/// ordering is relevance-only and `distance_miles` is absent from the response entirely. The one
/// thing that must never happen is sending them as `0` when we don't have a fix — that's a real
/// coordinate off West Africa, and it would silently reorder every result. Same contract on
/// fuel-web and fuel-android.
struct SearchQueryItemTests {
    private func items(lat: Double?, lng: Double?) -> [URLQueryItem] {
        FuelPricesAPIClient.searchQueryItems(query: "tesco", limit: 20, lat: lat, lng: lng)
    }

    @Test func alwaysSendsQueryAndLimit() {
        let names = items(lat: nil, lng: nil).map(\.name)
        #expect(names.contains("q"))
        #expect(names.contains("limit"))
        #expect(items(lat: nil, lng: nil).first { $0.name == "q" }?.value == "tesco")
        #expect(items(lat: nil, lng: nil).first { $0.name == "limit" }?.value == "20")
    }

    @Test func includesCoordinatesWhenSupplied() {
        let result = items(lat: 51.5074, lng: -0.1278)
        #expect(result.first { $0.name == "lat" }?.value == "51.5074")
        #expect(result.first { $0.name == "lng" }?.value == "-0.1278")
    }

    @Test func omitsCoordinatesEntirelyWhenNil() {
        let names = items(lat: nil, lng: nil).map(\.name)
        #expect(!names.contains("lat"))
        #expect(!names.contains("lng"))
    }

    /// A half-set location is no location — one coordinate on its own can't produce a distance,
    /// and `lat=0` would be a lie. Both or neither.
    @Test func omitsCoordinatesWhenOnlyOneIsPresent() {
        #expect(!items(lat: 51.5, lng: nil).map(\.name).contains("lat"))
        #expect(!items(lat: nil, lng: -0.12).map(\.name).contains("lng"))
    }

    /// Guards against a regression where a nil coordinate gets defaulted to 0 somewhere upstream.
    @Test func nilCoordinatesNeverAppearAsZero() {
        let values = items(lat: nil, lng: nil).map { $0.value ?? "" }
        #expect(!values.contains("0.0"))
        #expect(!values.contains("0"))
    }
}

// MARK: - Repository fallback

private enum StubError: Error { case offline, unimplemented }

/// Minimal `FuelPricesAPI` double — only `searchStations` is wired up; everything else throws,
/// since nothing in these tests touches it.
private final class StubFuelPricesAPI: FuelPricesAPI, @unchecked Sendable {
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

    func getNearbyStations(lat: Double, lng: Double, radiusMiles: Double, limit: Int) async throws -> StationListResponse { throw StubError.unimplemented }
    func getStationsInBounds(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double, limit: Int) async throws -> StationListResponse { throw StubError.unimplemented }
    func getStation(id: Int) async throws -> StationDTO { throw StubError.unimplemented }
    func getCheapest(fuelType: String, lat: Double?, lng: Double?, radiusMiles: Double, limit: Int) async throws -> CheapestResponse { throw StubError.unimplemented }
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
    func getPreferences() async throws -> PreferencesDTO { throw StubError.unimplemented }
    func updatePreferences(_ body: PreferencesDTO) async throws -> PreferencesDTO { throw StubError.unimplemented }
    func getFavourites() async throws -> [FavouriteDTO] { throw StubError.unimplemented }
    func addFavourite(_ body: FavouriteCreateRequest) async throws -> FavouriteDTO { throw StubError.unimplemented }
    func removeFavourite(id: Int) async throws { throw StubError.unimplemented }
    func getAlerts() async throws -> [AlertSubscriptionDTO] { throw StubError.unimplemented }
    func addAlert(_ body: AlertCreateRequest) async throws -> AlertSubscriptionDTO { throw StubError.unimplemented }
    func removeAlert(id: Int) async throws { throw StubError.unimplemented }
    func reportDiscrepancy(_ body: DiscrepancyReportRequest) async throws { throw StubError.unimplemented }
    func getDiscrepancyReportUrl() async throws -> DiscrepancyReportUrlResponse { throw StubError.unimplemented }
}

@MainActor
struct CachedStationSearchTests {
    // London, roughly Charing Cross — the "user is here" origin for the ordering tests.
    private static let originLat = 51.5074
    private static let originLng = -0.1278

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: CachedStation.self, CachedFuelPrice.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        // A manually-constructed ModelContext doesn't autosave, so `insert` below saves explicitly
        // — the repository's fetches must see the rows, not leave them pending.
        return ModelContext(container)
    }

    private func insert(
        into context: ModelContext,
        id: Int, name: String, brand: String? = nil, town: String? = nil, postcode: String? = nil,
        latitude: Double, longitude: Double
    ) throws {
        let station = CachedStation(
            id: id, govId: "gov-\(id)", name: name, brand: brand, operatorName: nil, phone: nil,
            addressLine1: nil, addressLine2: nil, town: town, county: nil, postcode: postcode,
            latitude: latitude, longitude: longitude,
            temporaryClosure: false, isMotorway: false, isSupermarket: false,
            amenitiesJSON: nil, openingHoursJSON: nil, lastFetchedAt: Date()
        )
        context.insert(station)
        try context.save()
    }

    private func makeRepository(api: StubFuelPricesAPI, context: ModelContext) -> FuelRepository {
        FuelRepository(api: api, modelContext: context, tokenStore: TokenStore())
    }

    @Test func passesCoordinatesThroughToTheApi() async throws {
        let api = StubFuelPricesAPI()
        let repository = makeRepository(api: api, context: try makeContext())

        _ = try await repository.searchStations(query: "shell", lat: Self.originLat, lng: Self.originLng)

        let recorded = try #require(api.recordedSearch)
        #expect(recorded.lat == Self.originLat)
        #expect(recorded.lng == Self.originLng)
        #expect(recorded.limit == 20)
    }

    @Test func passesNilCoordinatesThroughUndefaulted() async throws {
        let api = StubFuelPricesAPI()
        let repository = makeRepository(api: api, context: try makeContext())

        _ = try await repository.searchStations(query: "shell")

        // #require first: a nil `recordedSearch` would make both checks below pass vacuously.
        let recorded = try #require(api.recordedSearch)
        #expect(recorded.lat == nil)
        #expect(recorded.lng == nil)
    }

    /// The server searches name/postcode/brand/**town**; the offline cache used to check only the
    /// first three, so a town query that worked online came back empty offline.
    @Test func offlineFallbackMatchesOnTown() async throws {
        let context = try makeContext()
        try insert(into: context, id: 1, name: "Aurora Filling", town: "Loughborough", latitude: 52.77, longitude: -1.21)
        try insert(into: context, id: 2, name: "Northgate Services", town: "Derby", latitude: 52.92, longitude: -1.47)

        let api = StubFuelPricesAPI()
        api.searchShouldThrow = true
        let repository = makeRepository(api: api, context: context)

        let response = try await repository.searchStations(query: "loughborough")
        #expect(response.stations.map(\.id) == [1])
    }

    @Test func offlineFallbackStillMatchesNameBrandAndPostcode() async throws {
        let context = try makeContext()
        try insert(into: context, id: 1, name: "Shell Croydon", latitude: 51.37, longitude: -0.10)
        try insert(into: context, id: 2, name: "Aurora Filling", brand: "Shell", latitude: 51.40, longitude: -0.12)
        try insert(into: context, id: 3, name: "Northgate", postcode: "SE1 7PB", latitude: 51.50, longitude: -0.11)

        let api = StubFuelPricesAPI()
        api.searchShouldThrow = true
        let repository = makeRepository(api: api, context: context)

        let byNameOrBrand = try await repository.searchStations(query: "shell").stations.map(\.id)
        #expect(Set(byNameOrBrand) == Set([1, 2]))

        let byPostcode = try await repository.searchStations(query: "se1 7pb").stations.map(\.id)
        #expect(byPostcode == [3])
    }

    /// Matching is case-insensitive on every field — the server's rewrite fixed a real
    /// case-sensitivity bug, and the offline path must not reintroduce it.
    @Test func offlineFallbackIsCaseInsensitive() async throws {
        let context = try makeContext()
        try insert(into: context, id: 1, name: "Shell Croydon", town: "Croydon", latitude: 51.37, longitude: -0.10)

        let api = StubFuelPricesAPI()
        api.searchShouldThrow = true
        let repository = makeRepository(api: api, context: context)

        let upperCaseName = try await repository.searchStations(query: "SHELL").stations.map(\.id)
        #expect(upperCaseName == [1])

        let mixedCaseTown = try await repository.searchStations(query: "cRoYdOn").stations.map(\.id)
        #expect(mixedCaseTown == [1])
    }

    @Test func offlineFallbackSortsNearestFirstWhenLocationIsKnown() async throws {
        let context = try makeContext()
        // Deliberately inserted farthest-first so a passing test can't just be insertion order.
        try insert(into: context, id: 1, name: "Shell Manchester", latitude: 53.4808, longitude: -2.2426)
        try insert(into: context, id: 2, name: "Shell Birmingham", latitude: 52.4862, longitude: -1.8904)
        try insert(into: context, id: 3, name: "Shell Croydon", latitude: 51.3762, longitude: -0.0982)

        let api = StubFuelPricesAPI()
        api.searchShouldThrow = true
        let repository = makeRepository(api: api, context: context)

        let response = try await repository.searchStations(query: "shell", lat: Self.originLat, lng: Self.originLng)
        #expect(response.stations.map(\.id) == [3, 2, 1])
    }

    /// With a location the fallback also fills in `distanceMiles`, mirroring the server returning
    /// `distance_miles` only when `lat`/`lng` were supplied.
    @Test func offlineFallbackPopulatesDistanceOnlyWhenLocationIsKnown() async throws {
        let context = try makeContext()
        try insert(into: context, id: 1, name: "Shell Croydon", latitude: 51.3762, longitude: -0.0982)

        let api = StubFuelPricesAPI()
        api.searchShouldThrow = true
        let repository = makeRepository(api: api, context: context)

        let located = try await repository.searchStations(query: "shell", lat: Self.originLat, lng: Self.originLng)
        let distance = try #require(located.stations.first?.distanceMiles)
        // Charing Cross → Croydon is ~9 miles as the crow flies.
        #expect(distance > 8 && distance < 10)

        // #require the row first — `stations.first?.distanceMiles == nil` would also hold if the
        // fallback returned nothing at all.
        let unlocated = try await repository.searchStations(query: "shell")
        let unlocatedStation = try #require(unlocated.stations.first)
        #expect(unlocatedStation.distanceMiles == nil)
    }

    /// The 20-row cap has to be applied *after* sorting — truncating first would pick an
    /// arbitrary 20 of the 30 matches and only then order those, so the genuinely nearest station
    /// could be dropped before it was ever compared.
    @Test func offlineFallbackSortsBeforeTruncatingToTwenty() async throws {
        let context = try makeContext()
        // 30 matches, laid out so the nearest one is inserted last and would fall outside an
        // unsorted first-20 window.
        for index in 0..<30 {
            try insert(
                into: context, id: index + 1, name: "Shell \(index)",
                latitude: Self.originLat + Double(30 - index) * 0.05, longitude: Self.originLng
            )
        }

        let api = StubFuelPricesAPI()
        api.searchShouldThrow = true
        let repository = makeRepository(api: api, context: context)

        let response = try await repository.searchStations(query: "shell", lat: Self.originLat, lng: Self.originLng)
        #expect(response.stations.count == 20)
        #expect(response.stations.first?.id == 30)
        #expect(response.count == 20)
    }
}
