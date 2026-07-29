import SwiftUI
import SwiftData
import GoogleSignIn
import GoogleMaps

@main
struct FuelTrackerApp: App {
    @State private var container = AppContainer()

    init() {
        if let clientID = AppConfig.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
        if let mapsKey = AppConfig.googleMapsAPIKey {
            GMSServices.provideAPIKey(mapsKey)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container.modelContainer)
                .environment(container.repository)
                .environment(container.userPreferencesStore)
                .environment(\.appContainer, container)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
