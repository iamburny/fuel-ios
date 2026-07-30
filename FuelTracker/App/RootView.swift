import SwiftUI

/// Bottom navigation shell — four tabs mirroring the Android phone app's Nearby/Prices/
/// Favourites/Settings bottom nav. Detail (Phase 2) and Heatmap (Phase 3) are pushed
/// destinations, not tabs, matching Android.
enum AppTab: Hashable {
    case nearby, prices, favourites, settings
}

struct RootView: View {
    @Environment(FuelRepository.self) private var repository
    @Environment(PushNotificationManager.self) private var pushManager
    @Environment(AppPreferencesViewModel.self) private var appPreferences
    @Environment(\.openURL) private var openURL
    @State private var deepLinkStationId: Int?
    @State private var selectedTab: AppTab = .nearby
    @State private var hasRecordedAppOpen = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NearbyView()
                .tabItem { Label("Nearby", systemImage: "map") }
                .tag(AppTab.nearby)

            PricesView()
                .tabItem { Label("Prices", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppTab.prices)

            FavouritesView()
                .tabItem { Label("Favourites", systemImage: "heart") }
                .tag(AppTab.favourites)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        // Registers with the backend whenever Firebase issues a new/rotated FCM token — mirrors
        // Android's FcmService.onNewToken firing unconditionally (best-effort; 401s silently if
        // not signed in).
        .onChange(of: pushManager.latestToken) { _, newToken in
            guard let newToken else { return }
            Task { try? await repository.registerFcmToken(newToken) }
        }
        // Tapping a price-drop notification deep-links straight to that station's Detail screen,
        // matching Android's stationId-extra dispatch through MainActivity/Navigation.kt.
        // `initial: true` matters for a cold launch (app not running, user taps the notification):
        // UIKit can deliver the tap to PushNotificationManager and set this property before
        // RootView's first render, and a plain .onChange only fires on a subsequent *change* —
        // it would silently miss a value that was already non-nil at first attachment.
        .onChange(of: pushManager.pendingDeepLinkStationId, initial: true) { _, stationId in
            guard let stationId else { return }
            deepLinkStationId = stationId
            pushManager.pendingDeepLinkStationId = nil
        }
        // Universal Links (https://fueltracker.uk/...) — mirrors Android's DeepLinkTarget.fromUri
        // dispatch. Requires Associated Domains (entitlement side is done) + an
        // apple-app-site-association file published on fueltracker.uk (a web-team action item
        // outside this repo; the URL parsing/dispatch here works regardless of when that lands).
        .onOpenURL { url in
            guard let target = DeepLink.from(url: url) else { return }
            switch target {
            case .station(let id): deepLinkStationId = id
            case .prices: selectedTab = .prices
            case .settings: selectedTab = .settings
            case .home: selectedTab = .nearby
            }
        }
        .sheet(isPresented: Binding(
            get: { deepLinkStationId != nil },
            set: { if !$0 { deepLinkStationId = nil } }
        )) {
            if let stationId = deepLinkStationId {
                NavigationStack { DetailView(stationId: stationId) }
            }
        }
        // Ports AppPreferencesViewModel.kt's launch-cadence support prompt (Navigation.kt's
        // CoffeeSupportDialog). `hasRecordedAppOpen` is the SwiftUI equivalent of Android's
        // `savedInstanceState == null` check — `.onAppear` can otherwise refire on tab switches.
        // The short delay avoids racing NearbyView's location-permission system dialog, which also
        // fires on cold launch and can win the one modal-presentation slot iOS grants at a time,
        // silently swallowing this .alert's presentation if both fire on the same frame.
        .onAppear {
            guard !hasRecordedAppOpen else { return }
            hasRecordedAppOpen = true
            Task {
                try? await Task.sleep(for: .seconds(1))
                appPreferences.onAppOpened()
            }
            // An already-logged-in user relaunching the app (not going through AuthViewModel's
            // post-sign-in hook) still needs registerForRemoteNotifications() called every launch
            // and its FCM token kept fresh — currentToken() sets pushManager.latestToken on
            // success, which the .onChange above then registers with the backend.
            guard repository.isLoggedIn else { return }
            Task { _ = await pushManager.currentToken() }
        }
        .alert(
            "Keep Fuel Tracker free?",
            isPresented: Binding(
                get: { appPreferences.showCoffeePrompt },
                set: { if !$0 { appPreferences.onDismissCoffee() } }
            )
        ) {
            Button("Buy me a coffee") {
                appPreferences.onCoffeeClicked()
                openURL(URL(string: "https://buymeacoffee.com/iamburny")!)
            }
            Button("Maybe later", role: .cancel) {
                appPreferences.onDismissCoffee()
            }
        } message: {
            Text("I want to keep this app free. Apple charges to host apps on the App Store — has it saved you money? Buy me a coffee to help!")
        }
    }
}

#Preview {
    RootView()
}
