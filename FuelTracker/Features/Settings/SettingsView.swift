import SwiftUI
import SwiftData

/// Direct port of fuel-android's `PreferencesScreen.kt`. The "Buy me a coffee" and "Also available
/// on the web" cards (Unleash-flag-gated on Android) are deliberately not ported here — they land
/// in the Extras phase alongside the rest of the feature-flag wiring.
struct SettingsView: View {
    @Environment(FuelRepository.self) private var repository
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @State private var viewModel: SettingsViewModel?
    @State private var showingAuth = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAuth) {
                AuthView(onAuthed: { showingAuth = false })
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(preferencesStore: preferencesStore)
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: SettingsViewModel) -> some View {
        Form {
            Section("Account") {
                if repository.isLoggedIn {
                    HStack {
                        Text("Signed in" + (repository.currentEmail.map { " as \($0)" } ?? ""))
                        Spacer()
                        Button("Sign out", role: .destructive) {
                            repository.logout()
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sign in to save favourite stations and get price-drop alerts.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Sign in") { showingAuth = true }
                    }
                }
            }

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FuelType.allCases) { type in
                            let selected = viewModel.fuelType == type.rawValue
                            Text(type.label(useLongNames: viewModel.useLongFuelNames))
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? .white : .primary)
                                .background(Capsule().fill(selected ? type.color : Color.gray.opacity(0.15)))
                                .onTapGesture { viewModel.setFuelType(type.rawValue) }
                        }
                    }
                }
                .listRowInsets(EdgeInsets())
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } header: {
                Text("Your usual fuel")
            }

            Section {
                Toggle("Long fuel names", isOn: Binding(
                    get: { viewModel.useLongFuelNames },
                    set: { viewModel.setUseLongFuelNames($0) }
                ))
                Text("Show \"Unleaded (E10)\" instead of \"E10\" throughout the app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: Binding(
                    get: { viewModel.themeMode },
                    set: { viewModel.setThemeMode($0) }
                )) {
                    Text("System").tag(ThemeMode.system)
                    Text("Light").tag(ThemeMode.light)
                    Text("Dark").tag(ThemeMode.dark)
                }
                .pickerStyle(.segmented)
            }

            Section {
                TextField("Average MPG", text: Binding(
                    get: { viewModel.mpgText },
                    set: { viewModel.setMpgText($0) }
                ))
                .keyboardType(.decimalPad)

                TextField("Tank capacity (litres)", text: Binding(
                    get: { viewModel.tankCapacityText },
                    set: { viewModel.setTankCapacityText($0) }
                ))
                .keyboardType(.decimalPad)

                if viewModel.justSaved {
                    Text("Saved").font(.footnote).foregroundStyle(.tint)
                }
            } header: {
                Text("Your car")
            } footer: {
                Text("Used to estimate whether driving to a cheaper station is actually worth it, factoring in the fuel it takes to get there.")
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(FuelRepository(api: FuelPricesAPIClient(client: APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: TokenStore())), modelContext: try! ModelContainer(for: CachedStation.self, CachedFuelPrice.self).mainContext, tokenStore: TokenStore()))
        .environment(UserPreferencesStore())
}
