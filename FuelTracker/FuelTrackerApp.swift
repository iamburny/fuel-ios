import SwiftUI
import SwiftData
import GoogleSignIn

@main
struct FuelTrackerApp: App {
    @State private var container = AppContainer()

    init() {
        if let clientID = AppConfig.googleClientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .modelContainer(container.modelContainer)
                .environment(container.repository)
                .environment(container.userPreferencesStore)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
