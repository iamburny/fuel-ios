import SwiftUI

/// Bottom navigation shell — four tabs mirroring the Android phone app's Nearby/Prices/
/// Favourites/Settings bottom nav. Detail (Phase 2) and Heatmap (Phase 3) are pushed
/// destinations, not tabs, matching Android.
struct RootView: View {
    @Environment(FuelRepository.self) private var repository
    @Environment(PushNotificationManager.self) private var pushManager
    @State private var deepLinkStationId: Int?

    var body: some View {
        TabView {
            NearbyView()
                .tabItem { Label("Nearby", systemImage: "map") }

            PricesView()
                .tabItem { Label("Prices", systemImage: "chart.line.uptrend.xyaxis") }

            FavouritesView()
                .tabItem { Label("Favourites", systemImage: "heart") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
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
        .onChange(of: pushManager.pendingDeepLinkStationId) { _, stationId in
            guard let stationId else { return }
            deepLinkStationId = stationId
            pushManager.pendingDeepLinkStationId = nil
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
