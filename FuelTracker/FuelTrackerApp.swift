import SwiftUI
import SwiftData
import GoogleSignIn
import GoogleMaps

@main
struct FuelTrackerApp: App {
    // AppDelegate owns Firebase configuration + the APNs device-token callback (UIKit-only, no
    // SwiftUI equivalent) — see AppDelegate.swift.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .environment(PushNotificationManager.shared)
                .preferredColorScheme(container.userPreferencesStore.preferences.themeMode.colorScheme)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
