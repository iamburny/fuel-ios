import Foundation
import SwiftData
import SwiftUI

/// Manual dependency container — the lightweight iOS equivalent of Android's Hilt `AppModule`.
/// Constructed once in `FuelTrackerApp` and threaded through the view hierarchy via SwiftUI's
/// `@Environment`.
@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let tokenStore: TokenStore
    let userPreferencesStore: UserPreferencesStore
    let apiClient: APIClient
    let api: FuelPricesAPI
    let repository: FuelRepository
    let locationManager: LocationManager
    let analytics: AppAnalytics
    let featureFlags: FeatureFlags
    let appPreferencesViewModel: AppPreferencesViewModel

    init() {
        let schema = Schema([CachedStation.self, CachedFuelPrice.self])
        let configuration = ModelConfiguration(schema: schema)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("Failed to initialize the SwiftData model container")
        }
        modelContainer = container

        tokenStore = TokenStore()
        userPreferencesStore = UserPreferencesStore()
        apiClient = APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: tokenStore)
        api = FuelPricesAPIClient(client: apiClient)
        repository = FuelRepository(api: api, modelContext: container.mainContext, tokenStore: tokenStore)
        locationManager = LocationManager()
        analytics = FirebaseAppAnalytics() // gated internally on FirebaseApp.app() != nil
        featureFlags = FeatureFlags(url: AppConfig.unleashURL, clientKey: AppConfig.unleashClientKey)
        appPreferencesViewModel = AppPreferencesViewModel(store: userPreferencesStore, featureFlags: featureFlags)
    }
}

/// Custom `EnvironmentKey` so any view can pull the whole container (needed to construct view
/// models with several dependencies — e.g. `NearbyViewModel` needs the repository, location
/// manager, preferences store, AND analytics) without threading each one through separately.
/// `repository`/`userPreferencesStore` are ALSO injected individually via `.environment(_:)` in
/// `FuelTrackerApp` so views can read them reactively (`@Environment(FuelRepository.self)`)
/// without going through this key.
private struct AppContainerKey: EnvironmentKey {
    static let defaultValue: AppContainer? = nil
}

extension EnvironmentValues {
    var appContainer: AppContainer? {
        get { self[AppContainerKey.self] }
        set { self[AppContainerKey.self] = newValue }
    }
}
