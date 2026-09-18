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
    /// Favourite ids with a `toggleNotify`/`updateFuelType` PATCH currently in flight — guards
    /// against a rapid double-tap (or overlapping notify+fuel-type edits on the same row) firing
    /// two overlapping requests, matching `NearbyViewModel.pendingFavouriteToggles`'s pattern.
    var pendingUpdateIds: Set<Int> = []

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
        // Android rebuilds the whole state object here, which implicitly resets creatingAlert/
        // message to their defaults on every reload — do the same explicitly, since this method
        // (unlike every other screen's load) is called unconditionally on every re-entry, so stale
        // values could otherwise survive across a reload in a way Android's fresh-struct semantics
        // never allow.
        creatingAlert = false
        message = nil
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
            // A 401 mid-call means APIClient already tried a silent refresh and it failed (the
            // refresh token is itself invalid/expired/revoked), which flips repository.isLoggedIn
            // to false — treat that as the normal signed-out state rather than showing the raw
            // error, matching Android's FavouritesViewModel.
            if !repository.isLoggedIn {
                isLoggedIn = false
                favourites = []
                alerts = []
            } else {
                self.error = error.localizedDescription
            }
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

    func toggleNotify(_ favourite: FavouriteDTO) async {
        guard !pendingUpdateIds.contains(favourite.id) else { return }
        pendingUpdateIds.insert(favourite.id)
        defer { pendingUpdateIds.remove(favourite.id) }

        let newValue = !favourite.notifyOnDrop
        do {
            let updated = try await repository.updateFavourite(id: favourite.id, notifyOnDrop: newValue)
            replaceFavourite(favourite, with: updated)
            analytics.trackEvent(newValue ? "favourite_notify_enabled" : "favourite_notify_disabled", params: ["station_id": favourite.stationId])
        } catch {
            // Best-effort, matches removeFavourite's empty catch block.
        }
    }

    func updateFuelType(_ favourite: FavouriteDTO, to newFuelType: String) async {
        guard !pendingUpdateIds.contains(favourite.id), newFuelType != favourite.fuelType else { return }
        pendingUpdateIds.insert(favourite.id)
        defer { pendingUpdateIds.remove(favourite.id) }

        do {
            let updated = try await repository.updateFavouriteFuelType(id: favourite.id, fuelType: newFuelType)
            replaceFavourite(favourite, with: updated)
            analytics.trackEvent("favourite_fuel_type_changed", params: ["station_id": favourite.stationId, "fuel_type": newFuelType])
        } catch {
            // Best-effort, matches removeFavourite's empty catch block.
        }
    }

    /// Both PATCH responses omit `station` (see `FavouriteDTO`'s own doc comment on why POST's
    /// response also omits it) — keep the one already loaded from GET.
    private func replaceFavourite(_ original: FavouriteDTO, with updated: FavouriteDTO) {
        guard let idx = favourites.firstIndex(where: { $0.id == original.id }) else { return }
        favourites[idx] = FavouriteDTO(
            id: updated.id, stationId: updated.stationId, fuelType: updated.fuelType,
            notifyOnDrop: updated.notifyOnDrop, priceThresholdPence: updated.priceThresholdPence,
            station: original.station
        )
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
