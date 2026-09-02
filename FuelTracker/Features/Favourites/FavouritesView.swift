import SwiftUI

/// Direct port of fuel-android's `FavouritesScreen.kt`.
struct FavouritesView: View {
    @Environment(\.appContainer) private var appContainer
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @State private var viewModel: FavouritesViewModel?
    @State private var path: [Int] = []
    @State private var showingAuth = false
    @State private var showingCreateAlert = false

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Favourites")
            .navigationDestination(for: Int.self) { stationId in
                DetailView(stationId: stationId)
            }
            .sheet(isPresented: $showingAuth) {
                AuthView(onAuthed: {
                    showingAuth = false
                    Task { await viewModel?.load() }
                })
            }
            .sheet(isPresented: $showingCreateAlert) {
                if let viewModel {
                    CreateAlertSheet(useLongNames: preferencesStore.preferences.useLongFuelNames) { radius, fuelType in
                        showingCreateAlert = false
                        Task { await viewModel.createAlertNearMe(radiusMiles: radius, fuelType: fuelType) }
                    } onCancel: {
                        showingCreateAlert = false
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil, let appContainer {
                viewModel = FavouritesViewModel(repository: appContainer.repository, locationManager: appContainer.locationManager, analytics: appContainer.analytics)
            }
            // Reload every time this tab (re)appears — e.g. after signing in elsewhere — matching
            // Android's LaunchedEffect(Unit) re-triggering on every navigation into this screen.
            Task { await viewModel?.load() }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: FavouritesViewModel) -> some View {
        Group {
            if viewModel.isLoading {
                ProgressView()
            } else if !viewModel.isLoggedIn {
                loggedOutCta
            } else if let error = viewModel.error {
                Text("Error: \(error)").foregroundStyle(.red)
            } else {
                List {
                    Section {
                        areaAlertsSection(viewModel)
                    }

                    Section {
                        if viewModel.favourites.isEmpty {
                            Text("No favourites yet. Tap the heart icon on a station to add it here.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(viewModel.favourites, id: \.id) { favourite in
                                Button {
                                    viewModel.trackStationClick(favourite.stationId)
                                    path.append(favourite.stationId)
                                } label: {
                                    favouriteRow(favourite)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        Task { await viewModel.removeFavourite(id: favourite.id, stationId: favourite.stationId) }
                                    } label: {
                                        Label("Remove favourite", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } header: {
                        Text("Favourite stations")
                    }
                }
                .listStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.message {
                Text(message)
                    .font(.subheadline)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                    .shadow(radius: 4)
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        viewModel.clearMessage()
                    }
            }
        }
    }

    private var loggedOutCta: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .padding(.bottom, 8)
            Text("Sign up to receive notifications of price drops in your area")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Create a free account to save favourite stations and get alerted when fuel prices drop near you.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showingAuth = true
            } label: {
                Text("Sign up / Log in").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 16)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func areaAlertsSection(_ viewModel: FavouritesViewModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Area alerts").font(.headline)
            Text("Get notified when prices drop near a location.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)

        ForEach(viewModel.alerts, id: \.id) { alert in
            HStack {
                Image(systemName: "bell.badge.fill").foregroundStyle(FuelType.displayColor(forRaw: alert.fuelType))
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(FuelType.shortLabel(forRaw: alert.fuelType)) within \(Int(alert.radiusMiles)) mi")
                    Text(String(format: "%.3f, %.3f", alert.latitude, alert.longitude))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.removeAlert(id: alert.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
            }
        }

        Button {
            showingCreateAlert = true
        } label: {
            if viewModel.creatingAlert {
                ProgressView().frame(maxWidth: .infinity)
            } else {
                Text("Notify me of drops near me").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.creatingAlert)
    }

    @ViewBuilder
    private func favouriteRow(_ favourite: FavouriteDTO) -> some View {
        HStack {
            Image(systemName: "heart.fill").foregroundStyle(FuelType.displayColor(forRaw: favourite.fuelType))
            VStack(alignment: .leading, spacing: 2) {
                Text(favourite.station?.name ?? "Station #\(favourite.stationId)").fontWeight(.medium)
                Text(FuelType.label(forRaw: favourite.fuelType, useLongNames: preferencesStore.preferences.useLongFuelNames))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if favourite.notifyOnDrop {
                Text("Alerts on").font(.caption2).foregroundStyle(.tint)
            }
        }
    }
}

/// Matches Android's `CreateAlertDialog`. Presented as a sheet rather than a native `.alert` since
/// SwiftUI alerts don't support custom controls (a fuel-type chip row + slider).
private struct CreateAlertSheet: View {
    let useLongNames: Bool
    let onCreate: (Double, String) -> Void
    let onCancel: () -> Void

    @State private var radius: Double = 10
    @State private var fuelType: String = FuelType.default.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section("Fuel type") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FuelType.allCases) { type in
                                let selected = fuelType == type.rawValue
                                Text(type.label(useLongNames: useLongNames))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(selected ? .white : .primary)
                                    .background(Capsule().fill(selected ? type.color : Color.gray.opacity(0.15)))
                                    .onTapGesture { fuelType = type.rawValue }
                            }
                        }
                    }
                }

                Section("Radius: \(Int(radius)) miles") {
                    Slider(value: $radius, in: 1...50, step: 1)
                }
            }
            .navigationTitle("Alert me near my location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create alert") { onCreate(radius, fuelType) }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    FavouritesView()
}
