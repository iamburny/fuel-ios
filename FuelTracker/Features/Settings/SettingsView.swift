import SwiftUI

/// Placeholder — real implementation (fuel/units prefs, theme picker, account card) lands in the
/// Settings build phase.
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Settings", systemImage: "gearshape", description: Text("Coming in the Settings phase."))
                .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
