import Foundation
import CoreLocation
import GoogleMaps
import Observation

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
    var searchQuery = ""
    var userLat: Double?
    var userLng: Double?
    var error: String?
    /// Stations for whatever map area the user last dragged to — nil until the first drag, at
    /// which point map pins switch to this instead of the GPS-anchored `stations`. The bottom
    /// list panel's default (non-search) list also tracks this via `nearbyStationsSortedByPrice`,
    /// so it stays in sync with whatever's currently pinned on the map, including after a drag.
    var viewportStations: [StationDTO]?
    /// Bumped only when the map should jump to userLat/userLng — never on every reload, so
    /// changing the radius/fuel filter/mode doesn't fight a drag by snapping the camera back.
    var cameraRecenterToken = 0
    /// True once the user has dragged the map away from GPS-center — shows a recenter button.
    var isOffGpsCenter = false
    /// True while a drag-triggered viewport fetch is in flight. Drives a thin top-of-map progress
    /// bar — the old pins stay on screen throughout (viewportStations is only replaced once the
    /// new response lands), so this is purely a "something's happening" signal, not a data swap.
    var isLoadingViewport = false

    private let repository: FuelRepository
    private let locationManager: LocationManager
    private let preferencesStore: UserPreferencesStore
    private let analytics: AppAnalytics

    private var searchTask: Task<Void, Never>?
    private var boundsTask: Task<Void, Never>?
    private var locationUpdatesTask: Task<Void, Never>?
    private var bootstrapTask: Task<Void, Never>?
    private var permissionListenerTask: Task<Void, Never>?

    init(repository: FuelRepository, locationManager: LocationManager, preferencesStore: UserPreferencesStore, analytics: AppAnalytics) {
        self.repository = repository
        self.locationManager = locationManager
        self.preferencesStore = preferencesStore
        self.analytics = analytics
        bootstrapTask = Task { [weak self] in await self?.bootstrap() }
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
        // took longer than 3s to answer, or it's granted later via Settings). Split into its own
        // task (rather than continuing this same async function) so `[weak self]` can be
        // re-checked on EVERY iteration of this effectively-infinite loop — a single `guard let
        // self` at the top of one long-lived function would re-capture `self` strongly for the
        // rest of its execution, silently defeating the weak capture and leaking this view model
        // for the app's lifetime.
        permissionListenerTask = Task { [weak self] in
            guard let stream = self?.locationManager.permissionGranted else { return }
            for await _ in stream {
                guard let self else { return }
                await self.loadNearby()
                self.startLocationUpdates()
            }
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
            self.isLoadingViewport = true
            defer { self.isLoadingViewport = false }
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
        isLoadingViewport = false
        cameraRecenterToken += 1
    }

    func setFuelType(_ type: String) {
        analytics.trackEvent("select_fuel_type", params: ["fuel_type": type])
        selectedFuelType = type
    }

    func setRadius(_ miles: Double) {
        radiusMiles = miles
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

    /// Client-side derived view of whatever's currently pinned on the map (viewportStations after a
    /// drag, else the GPS-anchored `stations`), sorted ascending by price for `selectedFuelType` and
    /// filtered to stations that have one. No network call — recomputed automatically by `@Observable`
    /// whenever `stations`/`viewportStations`/`selectedFuelType` change. Backs the bottom list
    /// panel's only default (non-search) list.
    var nearbyStationsSortedByPrice: [StationDTO] {
        (viewportStations ?? stations)
            .compactMap { station in
                station.cheapestPrice(for: selectedFuelType).map { (station, $0.pricePence) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    private func reload(forceRefresh: Bool = false) async {
        if searchQuery.count >= 2 {
            // Search hits no local cache, so forceRefresh is a no-op for it.
            setSearchQuery(searchQuery)
        } else {
            await loadNearby(forceRefresh: forceRefresh)
        }
    }
}
