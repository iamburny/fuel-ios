import Foundation
import Observation

/// Direct port of fuel-android's `FavouritesViewModel.kt`.
@Observable
@MainActor
final class FavouritesViewModel {
    var isLoading = true
    var favourites: [FavouriteDTO] = []
    var alerts: [AlertSubscriptionDTO] = []
    var isLoggedIn = true
    var creatingAlert = false
    var error: String?
    var message: String?

    private let repository: FuelRepository
    private let locationManager: LocationManager
    private let analytics: AppAnalytics

    init(repository: FuelRepository, locationManager: LocationManager, analytics: AppAnalytics) {
        self.repository = repository
        self.locationManager = locationManager
        self.analytics = analytics
    }

    /// Reloads whenever the screen is (re)entered — e.g. returning after signing in from
    /// elsewhere — matching Android's `LaunchedEffect(Unit) { viewModel.load() }` re-triggering on
    /// every navigation into this screen (called from `FavouritesView.onAppear`, unconditionally,
    /// not gated on first-construction).
    func load() async {
        isLoading = true
        error = nil
        guard repository.isLoggedIn else {
            isLoading = false
            isLoggedIn = false
            favourites = []
            alerts = []
            return
        }
        do {
            let favs = try await repository.getFavourites()
            let alertList = try await repository.getAlerts()
            isLoading = false
            isLoggedIn = true
            favourites = favs
            alerts = alertList
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    /// Create a "drops near me" subscription anchored at the device's current location.
    func createAlertNearMe(radiusMiles: Double, fuelType: String) async {
        creatingAlert = true
        error = nil
        message = nil
        guard let location = await locationManager.getCurrentLocation() else {
            creatingAlert = false
            error = "Couldn't get your location. Enable location and try again."
            return
        }
        do {
            let subscription = try await repository.addAlert(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                radiusMiles: radiusMiles, fuelType: fuelType
            )
            analytics.trackEvent("create_alert", params: ["fuel_type": fuelType, "radius_miles": radiusMiles])
            creatingAlert = false
            alerts = [subscription] + alerts
            message = "Alert created — we'll notify you of nearby drops."
        } catch {
            creatingAlert = false
            self.error = error.localizedDescription
        }
    }

    func removeAlert(id: Int) async {
        do {
            try await repository.removeAlert(id: id)
            alerts.removeAll { $0.id == id }
        } catch {
            // Best-effort, matches Android's empty catch block.
        }
    }

    func removeFavourite(id: Int, stationId: Int) async {
        do {
            try await repository.removeFavourite(id: id)
            analytics.trackEvent("remove_from_favourites", params: ["station_id": stationId])
            favourites.removeAll { $0.id == id }
        } catch {
            // Best-effort, matches Android's empty catch block.
        }
    }

    func trackStationClick(_ stationId: Int) {
        analytics.trackEvent("select_station", params: ["station_id": stationId, "source": "favourites"])
    }

    func clearMessage() {
        message = nil
    }
}
