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
    @State private var deepLinkStationId: Int?
    @State private var selectedTab: AppTab = .nearby

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
    }
}

#Preview {
    RootView()
}
