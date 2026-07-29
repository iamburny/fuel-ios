import Foundation
import SwiftData
import Observation

private let cacheTTLSeconds: TimeInterval = 24 * 60 * 60
private let milesPerDegreeLat = 69.0

/// Single source of truth for all backend data — direct port of fuel-android's
/// `FuelRepository.kt`. The caching rules below are asymmetric per endpoint; see the class doc
/// comments on each method before changing behaviour, the asymmetry is deliberate (confirmed
/// against the Android source, not a simplification opportunity).
///
/// SwiftData's `ModelContext` isn't `Sendable`, so this stays `@MainActor`-isolated; network calls
/// are still concurrent under the hood via `URLSession`, they just get awaited from the main
/// actor. Fine at this app's cache scale — revisit with a `ModelActor` if station volume grows.
@Observable
@MainActor
final class FuelRepository {
    private let api: FuelPricesAPI
    private let modelContext: ModelContext
    private let tokenStore: TokenStore

    /// Consecutive network failures on the station data path — bumped when a fetch falls back to
    /// cache because the network was unreachable, reset to 0 on any successful call. The UI
    /// watches this to surface a graceful "can't reach the server" banner once it crosses a
    /// threshold, rather than silently showing an empty/stale list.
    private(set) var apiFailureCount = 0

    init(api: FuelPricesAPI, modelContext: ModelContext, tokenStore: TokenStore) {
        self.api = api
        self.modelContext = modelContext
        self.tokenStore = tokenStore
    }

    private func recordSuccess() { apiFailureCount = 0 }
    private func recordFailure() { apiFailureCount += 1 }

    // MARK: - Stations

    /// Prices don't change often, so this checks the local cache before hitting the network: a
    /// cache hit (fresh — within 24h — and covering this area) is returned directly, no network
    /// call. Falls through to the network if the cache has nothing fresh for this area, and falls
    /// back to (possibly stale) cache if the network call itself fails.
    func getNearbyStations(lat: Double, lng: Double, radiusMiles: Double = 10.0, forceRefresh: Bool = false) async throws -> StationListResponse {
        // forceRefresh (the manual pull-to-refresh) skips the cache entirely and goes straight to
        // the network, so the user always gets live prices on demand — automatic loads stay
        // cache-first below.
        if !forceRefresh {
            let cached = freshCachedStationsNear(lat: lat, lng: lng, radiusMiles: radiusMiles)
            if !cached.isEmpty {
                return StationListResponse(count: cached.count, stations: cached)
            }
        }

        do {
            // No fuel_type filter — the backend restricts the prices array to just that fuel type
            // when one's given, which would make the cache incomplete for every other fuel type
            // filter. Fetching everything once lets the cache serve all of them.
            let response = try await api.getNearbyStations(lat: lat, lng: lng, radiusMiles: radiusMiles)
            recordSuccess()
            cacheStations(response.stations)
            return response
        } catch {
            recordFailure()
            // Network failed and the cache had nothing fresh for this area — fall back to
            // whatever's cached regardless of age, better than nothing. Distance is still relative
            // to the original query point.
            let stale = allCachedStations().map { $0.toDTO(originLat: lat, originLng: lng) }
            return StationListResponse(count: stale.count, stations: stale)
        }
    }

    /// Stations within an exact lat/lng box (a map viewport) — cache-first via the same bounding-
    /// box query `getNearbyStations` uses internally, network fallback via the bounds endpoint.
    /// Unlike `getNearbyStations`, a stale-cache fallback here stays scoped to the box (ignoring
    /// freshness) rather than falling back to every cached station — an unrelated station from
    /// elsewhere in the country has no business appearing on a dragged viewport.
    func getStationsInBounds(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double, forceRefresh: Bool = false) async throws -> StationListResponse {
        let freshAfter = Date().addingTimeInterval(-cacheTTLSeconds)
        if !forceRefresh {
            let cached = fetchCachedStations(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, freshAfter: freshAfter)
                .map { $0.toDTO(originLat: nil, originLng: nil) }
            if !cached.isEmpty {
                return StationListResponse(count: cached.count, stations: cached)
            }
        }

        do {
            let response = try await api.getStationsInBounds(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng)
            recordSuccess()
            cacheStations(response.stations)
            return response
        } catch {
            recordFailure()
            let stale = fetchCachedStations(minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, freshAfter: .distantPast)
                .map { $0.toDTO(originLat: nil, originLng: nil) }
            return StationListResponse(count: stale.count, stations: stale)
        }
    }

    /// Network-first, cache-fallback only on failure — the inverse of the two methods above.
    /// `GET /api/stations/{id}` never returns `distance_miles`; distance is computed client-side
    /// elsewhere against the current location, never here.
    func getStation(id: Int) async throws -> StationDTO {
        do {
            let station = try await api.getStation(id: id)
            cacheStations([station])
            return station
        } catch {
            if let cached = fetchCachedStation(id: id) {
                return cached.toDTO(originLat: nil, originLng: nil)
            }
            throw error
        }
    }

    /// Network-first, cache fallback (name/brand/postcode substring match) on failure.
    func searchStations(query: String) async throws -> StationListResponse {
        do {
            return try await api.searchStations(query: query)
        } catch {
            let cached = searchCachedStations(query: query).map { $0.toDTO(originLat: nil, originLng: nil) }
            return StationListResponse(count: cached.count, stations: cached)
        }
    }

    // MARK: - Prices — never cached, no fallback. Errors must reach the UI, not be papered over
    // with stale numbers — a Fair Use Policy compliance concern, not just a UX one.

    func getCheapest(fuelType: String = FuelType.default.rawValue, lat: Double? = nil, lng: Double? = nil, radiusMiles: Double = 10.0) async throws -> CheapestResponse {
        try await api.getCheapest(fuelType: fuelType, lat: lat, lng: lng, radiusMiles: radiusMiles)
    }

    func getNationalAverages() async throws -> AveragesResponse {
        try await api.getNationalAverages()
    }

    func getHeatmap(fuelType: String = FuelType.default.rawValue) async throws -> HeatmapResponse {
        try await api.getHeatmap(fuelType: fuelType)
    }

    func getPriceHistory(stationId: Int, fuelType: String = FuelType.default.rawValue, days: Int = 30) async throws -> PriceHistoryResponse {
        try await api.getPriceHistory(stationId: stationId, fuelType: fuelType, days: days)
    }

    func getNationalTrends(fuelType: String = FuelType.default.rawValue, days: Int = 30) async throws -> TrendsResponse {
        try await api.getNationalTrends(fuelType: fuelType, days: days)
    }

    // MARK: - Auth

    func login(email: String, password: String) async throws -> TokenResponse {
        let response = try await api.login(email: email, password: password)
        tokenStore.token = response.accessToken
        tokenStore.email = email
        return response
    }

    func register(email: String, password: String) async throws -> UserResponse {
        try await api.register(RegisterRequest(email: email, password: password))
    }

    /// Exchange a Google ID token for the app JWT; `email` is stored for display (the backend
    /// response carries only the token).
    func loginWithGoogle(idToken: String, email: String) async throws -> TokenResponse {
        let response = try await api.googleLogin(GoogleLoginRequest(idToken: idToken))
        tokenStore.token = response.accessToken
        tokenStore.email = email
        return response
    }

    /// Exchange an Apple identity token for the app JWT. Apple only sends `email`/`name` on the
    /// user's very first authorization — pass them through then, `nil` on subsequent sign-ins.
    func loginWithApple(idToken: String, email: String?, name: String?) async throws -> TokenResponse {
        let response = try await api.appleLogin(AppleLoginRequest(idToken: idToken, email: email, name: name))
        tokenStore.token = response.accessToken
        if let email { tokenStore.email = email }
        return response
    }

    /// Ask the backend to email a password-reset link. The endpoint always succeeds (it never
    /// reveals whether the address is registered); the actual reset happens on the web page the
    /// email links to — there is deliberately no in-app "enter new password" screen.
    func forgotPassword(email: String) async throws {
        try await api.forgotPassword(ForgotPasswordRequest(email: email))
    }

    /// Register this device's FCM token against the logged-in user (call after login).
    func registerFcmToken(_ token: String) async throws {
        try await api.updateFcmToken(token)
    }

    func logout() { tokenStore.clear() }
    var isLoggedIn: Bool { tokenStore.isSignedIn }
    var currentEmail: String? { tokenStore.email }

    // MARK: - Favourites

    func getFavourites() async throws -> [FavouriteDTO] { try await api.getFavourites() }

    func addFavourite(stationId: Int, fuelType: String = FuelType.default.rawValue) async throws -> FavouriteDTO {
        try await api.addFavourite(FavouriteCreateRequest(stationId: stationId, fuelType: fuelType))
    }

    func removeFavourite(id: Int) async throws { try await api.removeFavourite(id: id) }

    // MARK: - Area alerts

    func getAlerts() async throws -> [AlertSubscriptionDTO] { try await api.getAlerts() }

    func addAlert(latitude: Double, longitude: Double, radiusMiles: Double = 10.0, fuelType: String = FuelType.default.rawValue, label: String? = nil) async throws -> AlertSubscriptionDTO {
        try await api.addAlert(AlertCreateRequest(latitude: latitude, longitude: longitude, radiusMiles: radiusMiles, fuelType: fuelType, label: label))
    }

    func removeAlert(id: Int) async throws { try await api.removeAlert(id: id) }

    // MARK: - Discrepancy

    func reportDiscrepancy(_ request: DiscrepancyReportRequest) async throws {
        try await api.reportDiscrepancy(request)
    }

    // MARK: - Cache helpers

    private func freshCachedStationsNear(lat: Double, lng: Double, radiusMiles: Double) -> [StationDTO] {
        let latDelta = radiusMiles / milesPerDegreeLat
        let lngDelta = radiusMiles / (milesPerDegreeLat * max(cos(lat * .pi / 180), 0.01))
        let freshAfter = Date().addingTimeInterval(-cacheTTLSeconds)
        return fetchCachedStations(minLat: lat - latDelta, maxLat: lat + latDelta, minLng: lng - lngDelta, maxLng: lng + lngDelta, freshAfter: freshAfter)
            .map { $0.toDTO(originLat: lat, originLng: lng) }
    }

    private func fetchCachedStations(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double, freshAfter: Date) -> [CachedStation] {
        let descriptor = FetchDescriptor<CachedStation>(predicate: #Predicate { station in
            station.lastFetchedAt >= freshAfter &&
            station.latitude >= minLat && station.latitude <= maxLat &&
            station.longitude >= minLng && station.longitude <= maxLng
        })
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchCachedStation(id: Int) -> CachedStation? {
        let descriptor = FetchDescriptor<CachedStation>(predicate: #Predicate { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
    }

    private func allCachedStations() -> [CachedStation] {
        (try? modelContext.fetch(FetchDescriptor<CachedStation>())) ?? []
    }

    private func searchCachedStations(query: String) -> [CachedStation] {
        allCachedStations().filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            ($0.brand?.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.postcode?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func cacheStations(_ stations: [StationDTO]) {
        let now = Date()
        let encoder = JSONEncoder()
        for dto in stations {
            let entity = fetchCachedStation(id: dto.id) ?? {
                let new = CachedStation(
                    id: dto.id, govId: dto.govId, name: dto.name, brand: dto.brand, operatorName: dto.operatorName,
                    phone: dto.phone, addressLine1: dto.addressLine1, addressLine2: dto.addressLine2, town: dto.town,
                    county: dto.county, postcode: dto.postcode, latitude: dto.latitude, longitude: dto.longitude,
                    temporaryClosure: dto.temporaryClosure, isMotorway: dto.isMotorway, isSupermarket: dto.isSupermarket,
                    amenitiesJSON: nil, openingHoursJSON: nil, lastFetchedAt: now
                )
                modelContext.insert(new)
                return new
            }()

            entity.govId = dto.govId
            entity.name = dto.name
            entity.brand = dto.brand
            entity.operatorName = dto.operatorName
            entity.phone = dto.phone
            entity.addressLine1 = dto.addressLine1
            entity.addressLine2 = dto.addressLine2
            entity.town = dto.town
            entity.county = dto.county
            entity.postcode = dto.postcode
            entity.latitude = dto.latitude
            entity.longitude = dto.longitude
            entity.temporaryClosure = dto.temporaryClosure
            entity.isMotorway = dto.isMotorway
            entity.isSupermarket = dto.isSupermarket
            entity.amenitiesJSON = dto.amenities.flatMap { try? encoder.encode($0) }
            entity.openingHoursJSON = dto.openingHours.flatMap { try? encoder.encode($0) }
            entity.lastFetchedAt = now

            // Replace-with-latest-snapshot, mirroring Room's upsert-prices behaviour.
            for old in entity.prices { modelContext.delete(old) }
            entity.prices = dto.prices.map { CachedFuelPrice(fuelType: $0.fuelType, pricePence: $0.pricePence, reportedAt: $0.reportedAt, station: entity) }
        }
        try? modelContext.save()
    }
}
