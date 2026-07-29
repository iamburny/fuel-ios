import SwiftUI

/// Placeholder — real implementation (sign-in gate, swipe-to-delete, Area Alerts section) lands
/// in the Favourites + Area Alerts build phase.
struct FavouritesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Favourites", systemImage: "heart", description: Text("Coming in the Favourites + Area Alerts phase."))
                .navigationTitle("Favourites")
        }
    }
}

#Preview {
    FavouritesView()
}
