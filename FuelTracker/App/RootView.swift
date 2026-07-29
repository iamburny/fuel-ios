import SwiftUI

/// Bottom navigation shell — four tabs mirroring the Android phone app's Nearby/Prices/
/// Favourites/Settings bottom nav. Detail (Phase 2) and Heatmap (Phase 3) are pushed
/// destinations, not tabs, matching Android.
struct RootView: View {
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
    }
}

#Preview {
    RootView()
}
