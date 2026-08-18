import SwiftUI
import SwiftData

/// Direct port of fuel-android's `PreferencesScreen.kt`, including the Unleash-flag-gated
/// "Also available on the web" card. Android's "Buy me a coffee" card is deliberately NOT
/// ported — see the note below.
struct SettingsView: View {
    @Environment(FuelRepository.self) private var repository
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @Environment(FeatureFlags.self) private var featureFlags
    @Environment(\.openURL) private var openURL
    @State private var viewModel: SettingsViewModel?
    @State private var showingAuth = false
    @State private var showingDeleteConfirm = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

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
            .alert("Delete account?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { deleteAccount() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your account, favourites, and alerts. This can't be undone.")
            }
            .alert("Couldn't delete account", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(deleteAccountError ?? "")
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = SettingsViewModel(preferencesStore: preferencesStore)
            }
        }
    }

    private func deleteAccount() {
        isDeletingAccount = true
        Task {
            defer { isDeletingAccount = false }
            do {
                try await repository.deleteAccount()
            } catch {
                deleteAccountError = (error as? AuthError)?.errorDescription ?? "Please try again."
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: SettingsViewModel) -> some View {
        Form {
            // Mirrors PreferencesScreen.kt's flag-gated card — fuel-ios.also-available-on-web
            // (Android's own flag is fuel-android.also-available-on-web). Defaults to false:
            // Unleash's Frontend API only ever returns currently-enabled flags, so a real "off"
            // toggle is indistinguishable from "unknown" — a `true` default would make this
            // impossible to ever disable remotely.
            //
            // NOTE: Android also has a "Buy me a coffee" card here (shared.buy-me-a-coffee),
            // deliberately NOT ported to iOS — Apple rejected submission 1.0 (1) under Guideline
            // 3.1.1 for linking to an external (buymeacoffee.com) purchase mechanism from within
            // the app. Do not re-add a donation/tip link on iOS without routing it through IAP.
            if featureFlags.isEnabled("fuel-ios.also-available-on-web", default: false) {
                Section {
                    Button {
                        openURL(URL(string: "https://fueltracker.uk")!)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "globe")
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Also available on the web").font(.headline).foregroundStyle(.primary)
                                Text("fueltracker.uk — same account, same favourites")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Account") {
                if repository.isLoggedIn {
                    HStack {
                        Text("Signed in" + (repository.currentEmail.map { " as \($0)" } ?? ""))
                        Spacer()
                        Button("Sign out", role: .destructive) {
                            repository.logout()
                        }
                    }
                    HStack {
                        Button("Delete account", role: .destructive) {
                            showingDeleteConfirm = true
                        }
                        .disabled(isDeletingAccount)
                        if isDeletingAccount {
                            Spacer()
                            ProgressView()
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
        .environment(FeatureFlags(url: nil, clientKey: nil))
}
