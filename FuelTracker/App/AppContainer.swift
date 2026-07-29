import Foundation
import SwiftData

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
    }
}
