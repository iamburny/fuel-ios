import SwiftUI
import SwiftData

@main
struct FuelTrackerApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container.modelContainer)
                .environment(container.repository)
                .environment(container.userPreferencesStore)
        }
    }
}
