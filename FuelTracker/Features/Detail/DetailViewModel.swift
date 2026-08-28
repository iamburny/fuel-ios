import Foundation
import Observation

/// Direct port of fuel-android's `DetailViewModel.kt`. `station`-fetch failure is the only thing
/// that blocks the whole screen (`error` set, whole `load()` throws); history/favourite-status/
/// national-averages/drive-cost are each best-effort and fail silently and independently — do NOT
/// collapse them into one enclosing `do/catch`, that would regress "one flaky sub-fetch blanks the
/// whole screen" (see fuel-android's inline comment on the equivalent Kotlin `try`s).
@Observable
@MainActor
final class DetailViewModel {
    let stationId: Int

    var isLoading = true
    var station: StationDTO?
    var priceHistory: [PriceHistoryPoint] = []
    var selectedFuelType: String = FuelType.default.rawValue
    var isFavourite = false
    var favouriteId: Int?
    var nationalAverages: [NationalAverageDTO] = []
    var distanceMiles: Double?
    var driveCostPounds: Double?
    var error: String?

    private let repository: FuelRepository
    private let locationManager: LocationManager
    private let preferencesStore: UserPreferencesStore
    private let analytics: AppAnalytics

    init(stationId: Int, repository: FuelRepository, locationManager: LocationManager, preferencesStore: UserPreferencesStore, analytics: AppAnalytics) {
        self.stationId = stationId
        self.repository = repository
        self.locationManager = locationManager
        self.preferencesStore = preferencesStore
        self.analytics = analytics
        Task { await load() }
    }

    func load() async {
        isLoading = true
        do {
            let station = try await repository.getStation(id: stationId)
            let preferences = preferencesStore.preferences
            let fuelType = station.prices.contains { $0.fuelType == preferences.fuelType }
                ? preferences.fuelType
                : (station.prices.first?.fuelType ?? preferences.fuelType)

            let history: [PriceHistoryPoint]
            do {
                history = try await repository.getPriceHistory(stationId: stationId, fuelType: fuelType).history
            } catch {
                history = []
            }

            var existingFavourite: FavouriteDTO?
            do {
                existingFavourite = try await repository.getFavourites().first { $0.stationId == stationId }
            } catch {
                existingFavourite = nil
            }

            // Unconditional — needed for the vs-national-average price delta regardless of
            // whether MPG/tank capacity are set (unlike the car app's conditional fetch, which is
            // only used there for savings-based sorting).
            var averages: [NationalAverageDTO] = []
            do {
                averages = try await repository.getNationalAverages().averages
            } catch {
                averages = []
            }

            var distance: Double?
            var driveCost: Double?
            if preferences.canEstimateDriveCost {
                let location = await locationManager.getCurrentLocation()
                let price = station.prices.first { $0.fuelType == preferences.fuelType }?.pricePence
                if let location, let price, let mpg = preferences.mpg {
                    let d = FuelCostCalculator.haversineMiles(
                        lat1: location.coordinate.latitude, lng1: location.coordinate.longitude,
                        lat2: station.latitude, lng2: station.longitude
                    )
                    distance = d
                    driveCost = FuelCostCalculator.estimateDriveCostPounds(distanceMiles: d, mpg: mpg, pricePence: price)
                }
            }

            self.isLoading = false
            self.station = station
            self.priceHistory = history
            self.selectedFuelType = fuelType
            self.isFavourite = existingFavourite != nil
            self.favouriteId = existingFavourite?.id
            self.nationalAverages = averages
            self.distanceMiles = distance
            self.driveCostPounds = driveCost
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    func setFuelType(_ fuelType: String) async {
        guard fuelType != selectedFuelType else { return }
        selectedFuelType = fuelType
        do {
            priceHistory = try await repository.getPriceHistory(stationId: stationId, fuelType: fuelType).history
        } catch {
            priceHistory = []
        }
    }

    func toggleFavourite() async {
        do {
            if isFavourite, let favouriteId {
                try await repository.removeFavourite(id: favouriteId)
                analytics.trackEvent("remove_from_favourites", params: ["station_id": stationId])
                isFavourite = false
                self.favouriteId = nil
            } else {
                let favourite = try await repository.addFavourite(stationId: stationId)
                analytics.trackEvent("add_to_favourites", params: ["station_id": stationId])
                isFavourite = true
                favouriteId = favourite.id
            }
        } catch {
            // Best-effort, matches Android's empty catch block.
        }
    }
}
