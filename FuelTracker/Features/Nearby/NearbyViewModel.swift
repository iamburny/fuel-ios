import Foundation
import CoreLocation
import GoogleMaps
import Observation

enum ListMode {
    case nearby
    case cheapest
}

/// Direct port of fuel-android's `NearbyViewModel.kt`. See its doc comments for the reasoning
/// behind each piece of state — reproduced inline below rather than re-explained.
///
/// Not ported: `apiUnreachable` — `NearbyView` reads `repository.apiFailureCount` directly instead
/// (both are `@Observable` and reach the view via `@Environment`, so there's no need to re-mirror
/// the repository's state into this view model the way Android's StateFlow architecture requires).
@Observable
@MainActor
final class NearbyViewModel {
    var isLoading = true
    var stations: [StationDTO] = []
    var selectedFuelType = FuelType.default.rawValue
    var radiusMiles = 10.0
    var mode: ListMode = .nearby
    var searchQuery = ""
    var userLat: Double?
    var userLng: Double?
    var discrepancyReportUrl = ""
    var error: String?
    /// Stations for whatever map area the user last dragged to — nil until the first drag, at
    /// which point map pins switch to this instead of the GPS-anchored `stations`. The bottom
    /// list panel always keeps using `stations`, unaffected by dragging.
    var viewportStations: [StationDTO]?
    /// Bumped only when the map should jump to userLat/userLng — never on every reload, so
    /// changing the radius/fuel filter/mode doesn't fight a drag by snapping the camera back.
    var cameraRecenterToken = 0
    /// True once the user has dragged the map away from GPS-center — shows a recenter button.
    var isOffGpsCenter = false

    private let repository: FuelRepository
    private let locationManager: LocationManager
    private let preferencesStore: UserPreferencesStore
    private let analytics: AppAnalytics

    private var searchTask: Task<Void, Never>?
    private var boundsTask: Task<Void, Never>?
    private var locationUpdatesTask: Task<Void, Never>?

    init(repository: FuelRepository, locationManager: LocationManager, preferencesStore: UserPreferencesStore, analytics: AppAnalytics) {
        self.repository = repository
        self.locationManager = locationManager
        self.preferencesStore = preferencesStore
        self.analytics = analytics
        Task { await bootstrap() }
    }

    private func bootstrap() async {
        // Start from the user's saved "usual fuel" preference rather than always defaulting to E10.
        selectedFuelType = preferencesStore.preferences.fuelType

        locationManager.requestPermissionIfNeeded()
        // Give the permission dialog a brief window to be answered before firing the first
        // request — otherwise we load London (the fallback), render it, then immediately correct
        // to the real location once permission lands, which reads as a jarring flash. If
        // permission's already granted (the common case for returning users) this returns
        // instantly. Capped at 3s so a slow response doesn't stall the screen.
        if !locationManager.hasPermission {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await _ in self.locationManager.permissionGranted { break }
                }
                group.addTask { try? await Task.sleep(for: .seconds(3)) }
                await group.next()
                group.cancelAll()
            }
        }
        await loadNearby()
        startLocationUpdates()

        // Keep listening in case permission lands after our short wait above (e.g. the dialog
        // took longer than 3s to answer, or it's granted later via Settings).
        for await _ in locationManager.permissionGranted {
            await loadNearby()
            startLocationUpdates()
        }
    }

    /// Subscribes to continuous GPS fixes so the map tracks the user in real time. While the user
    /// hasn't dragged away from GPS-center (`isOffGpsCenter` is false), each new fix re-centers
    /// the camera by bumping `cameraRecenterToken`; once they've dragged, we still update the
    /// stored location (for the "my location" dot and distances) but leave the camera where they
    /// put it.
    private func startLocationUpdates() {
        locationUpdatesTask?.cancel()
        locationUpdatesTask = Task { [weak self] in
            guard let self else { return }
            for await location in self.locationManager.locationUpdates() {
                if Task.isCancelled { break }
                let lat = location.coordinate.latitude
                let lng = location.coordinate.longitude
                // Ignore sub-30m jitter so the camera doesn't twitch while standing still.
                let moved: Bool
                if let prevLat = self.userLat, let prevLng = self.userLng {
                    moved = FuelCostCalculator.haversineMiles(lat1: prevLat, lng1: prevLng, lat2: lat, lng2: lng) > 0.02
                } else {
                    moved = true
                }
                guard moved else { continue }
                self.userLat = lat
                self.userLng = lng
                if !self.isOffGpsCenter {
                    self.cameraRecenterToken += 1
                }
            }
        }
    }

    /// Manual refresh — re-acquires GPS and forces a live network reload, bypassing the cache.
    func refresh() {
        Task { await reload(forceRefresh: true) }
    }

    func loadNearby(forceRefresh: Bool = false) async {
        isLoading = true
        error = nil
        do {
            let location = await locationManager.getCurrentLocation()
            let lat = location?.coordinate.latitude ?? 51.5074 // default: London
            let lng = location?.coordinate.longitude ?? -0.1278

            // No fuelType here — the repository always caches full price data per station now,
            // so switching the fuel filter chip doesn't need a new fetch, just a client-side
            // re-filter for display.
            let response = try await repository.getNearbyStations(lat: lat, lng: lng, radiusMiles: radiusMiles, forceRefresh: forceRefresh)

            // Only jump the camera to GPS the first time we get a real fix — subsequent reloads
            // (radius/fuel/mode changes) shouldn't yank the map back if the user has since
            // dragged it elsewhere.
            let isFirstFix = userLat == nil
            isLoading = false
            stations = response.stations
            userLat = lat
            userLng = lng
            if isFirstFix { cameraRecenterToken += 1 }
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    /// Called when the map's drag gesture ends, with the newly visible viewport.
    func loadStationsInBounds(_ bounds: GMSCoordinateBounds) {
        boundsTask?.cancel()
        boundsTask = Task { [weak self] in
            guard let self else { return }
            self.isOffGpsCenter = true
            do {
                let response = try await self.repository.getStationsInBounds(
                    minLat: bounds.southWest.latitude, maxLat: bounds.northEast.latitude,
                    minLng: bounds.southWest.longitude, maxLng: bounds.northEast.longitude
                )
                if Task.isCancelled { return }
                self.viewportStations = response.stations
            } catch {
                // Keep showing whatever was already on the map rather than clearing pins on a
                // transient network failure mid-drag.
            }
        }
    }

    /// Jumps the map back to the user's GPS location and reverts pins to the GPS-anchored set.
    func recenterOnGps() {
        boundsTask?.cancel()
        viewportStations = nil
        isOffGpsCenter = false
        cameraRecenterToken += 1
    }

    func setFuelType(_ type: String) {
        analytics.trackEvent("select_fuel_type", params: ["fuel_type": type])
        selectedFuelType = type
        // Nearby mode already has every fuel type's prices cached/loaded — just re-filter for
        // display. Cheapest mode ranks server-side per fuel type, so that genuinely needs a fresh
        // request.
        if mode == .cheapest {
            Task { await reload() }
        }
    }

    func setRadius(_ miles: Double) {
        radiusMiles = miles
        Task { await reload() }
    }

    func setMode(_ newMode: ListMode) {
        analytics.trackEvent("select_mode", params: ["mode": newMode == .nearby ? "nearby" : "cheapest"])
        mode = newMode
        searchQuery = ""
        searchTask?.cancel()
        Task { await reload() }
    }

    func setSearchQuery(_ query: String) {
        searchQuery = query
        searchTask?.cancel()
        if query.count < 2 {
            // Revert to normal mode results.
            Task { await reload() }
            return
        }
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(400))
            // Only reached once the query has settled (a newer keystroke cancels this task before
            // getting here), so this fires once per search rather than once per character typed.
            if Task.isCancelled { return }
            self.analytics.trackEvent("search", params: ["search_term": query])
            self.isLoading = true
            self.error = nil
            do {
                let response = try await self.repository.searchStations(query: query)
                if Task.isCancelled { return }
                self.isLoading = false
                self.stations = response.stations
            } catch {
                if Task.isCancelled { return }
                self.isLoading = false
                self.error = error.localizedDescription
            }
        }
    }

    /// Kept in the view model (rather than firing analytics straight from the View) so it stays
    /// testable and consistent with how every other tracked interaction here goes through
    /// analytics.
    func trackStationClick(_ stationId: Int, source: String) {
        analytics.trackEvent("select_station", params: ["station_id": stationId, "fuel_type": selectedFuelType, "source": source])
    }

    func loadCheapest() async {
        isLoading = true
        error = nil
        do {
            let response = try await repository.getCheapest(fuelType: selectedFuelType, lat: userLat, lng: userLng, radiusMiles: radiusMiles)
            // /api/prices/cheapest's station objects carry no `prices` array — only a top-level
            // price for the one matched fuel type — so StationListRow/the map markers'
            // `station.prices` lookups would find nothing and render no price at all. Synthesize
            // the single-entry list they expect. Also sorted client-side by price ascending — not
            // just relying on the backend's order — so "Cheapest" always reads cheapest-first.
            let fuelType = selectedFuelType
            let sorted = response.results.sorted { $0.pricePence < $1.pricePence }
            isLoading = false
            stations = sorted.map { entry in
                let s = entry.station
                return StationDTO(
                    id: s.id, govId: s.govId, name: s.name, brand: s.brand, operatorName: s.operatorName,
                    phone: s.phone, addressLine1: s.addressLine1, addressLine2: s.addressLine2,
                    town: s.town, county: s.county, postcode: s.postcode,
                    latitude: s.latitude, longitude: s.longitude,
                    temporaryClosure: s.temporaryClosure, isMotorway: s.isMotorway, isSupermarket: s.isSupermarket,
                    amenities: s.amenities, openingHours: s.openingHours,
                    distanceMiles: entry.distanceMiles,
                    prices: [PriceDTO(fuelType: fuelType, pricePence: entry.pricePence, reportedAt: "")]
                )
            }
            discrepancyReportUrl = response.discrepancyReportUrl
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    private func reload(forceRefresh: Bool = false) async {
        if searchQuery.count >= 2 {
            // Search and cheapest hit no local cache, so forceRefresh is a no-op for them.
            setSearchQuery(searchQuery)
        } else {
            switch mode {
            case .nearby: await loadNearby(forceRefresh: forceRefresh)
            case .cheapest: await loadCheapest()
            }
        }
    }
}
