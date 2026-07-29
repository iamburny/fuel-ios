import SwiftUI

/// Placeholder — real implementation lands in the Nearby+Detail build phase (map, GPS-anchored
/// list vs viewport-anchored pins, search/filter panel, recenter FAB).
struct NearbyView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Nearby", systemImage: "map", description: Text("Coming in the Nearby + Detail phase."))
                .navigationTitle("Fuel Tracker UK")
        }
    }
}

#Preview {
    NearbyView()
}
