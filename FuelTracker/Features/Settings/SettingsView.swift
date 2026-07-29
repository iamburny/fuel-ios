import SwiftUI
import SwiftData

/// Account section is wired now (Phase 1: Auth) since it's the primary sign-in entry point,
/// matching Android's Preferences screen owning the primary Account card. The rest of this screen
/// (fuel/units prefs, theme picker) is a placeholder until the Settings phase.
struct SettingsView: View {
    @Environment(FuelRepository.self) private var repository
    @State private var showingAuth = false

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if repository.isLoggedIn {
                        LabeledContent("Signed in as", value: repository.currentEmail ?? "—")
                        Button("Sign out", role: .destructive) {
                            repository.logout()
                        }
                    } else {
                        Button("Sign in") { showingAuth = true }
                    }
                }

                Section {
                    ContentUnavailableView("More settings coming soon", systemImage: "gearshape", description: Text("Usual fuel, MPG, tank capacity, and theme land in the Settings phase."))
                        .listRowInsets(EdgeInsets())
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAuth) {
                AuthView(onAuthed: { showingAuth = false })
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(FuelRepository(api: FuelPricesAPIClient(client: APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: TokenStore())), modelContext: try! ModelContainer(for: CachedStation.self, CachedFuelPrice.self).mainContext, tokenStore: TokenStore()))
}
