import SwiftUI

/// Direct port of fuel-android's `FavouritesScreen.kt`.
struct FavouritesView: View {
    @Environment(\.appContainer) private var appContainer
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @State private var viewModel: FavouritesViewModel?
    @State private var path: [Int] = []
    @State private var showingAuth = false
    @State private var showingCreateAlert = false
    @State private var editingFuelTypeFor: FavouriteDTO?

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
            .sheet(item: $editingFuelTypeFor) { favourite in
                if let viewModel {
                    FuelTypePickerSheet(
                        currentFuelType: favourite.fuelType,
                        useLongNames: preferencesStore.preferences.useLongFuelNames
                    ) { newType in
                        editingFuelTypeFor = nil
                        Task { await viewModel.updateFuelType(favourite, to: newType) }
                    } onCancel: {
                        editingFuelTypeFor = nil
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
                                favouriteRow(
                                    favourite,
                                    isNotifyPending: viewModel.pendingUpdateIds.contains(favourite.id),
                                    onTap: {
                                        viewModel.trackStationClick(favourite.stationId)
                                        path.append(favourite.stationId)
                                    },
                                    onToggleNotify: { Task { await viewModel.toggleNotify(favourite) } },
                                    onEditFuelType: { editingFuelTypeFor = favourite }
                                )
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

    /// Three independently tappable, non-overlapping regions (not nested inside one another) —
    /// the navigate-to-Detail region uses `.onTapGesture` rather than a `Button` specifically so
    /// the fuel-type and bell `Button`s can sit alongside it as true siblings with their own
    /// separate bounds; nesting either of those `Button`s *inside* the tap-gesture region's frame
    /// would compete with its gesture rather than reliably winning within their own bounds. This
    /// is also why the fuel-type control lives beside the name rather than stacked as a subtitle
    /// underneath it, as it now visually reads a caption but isn't nested inside that region.
    @ViewBuilder
    private func favouriteRow(_ favourite: FavouriteDTO, isNotifyPending: Bool, onTap: @escaping () -> Void, onToggleNotify: @escaping () -> Void, onEditFuelType: @escaping () -> Void) -> some View {
        HStack(spacing: 0) {
            HStack {
                Image(systemName: "heart.fill").foregroundStyle(FuelType.displayColor(forRaw: favourite.fuelType))
                Text(favourite.station?.name ?? "Station #\(favourite.stationId)").fontWeight(.medium)
                Spacer()
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            Button(action: onEditFuelType) {
                Text(FuelType.label(forRaw: favourite.fuelType, useLongNames: preferencesStore.preferences.useLongFuelNames))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .underline()
                    .padding(.horizontal, 8)
                    .frame(height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change tracked fuel type, currently \(FuelType.label(forRaw: favourite.fuelType, useLongNames: preferencesStore.preferences.useLongFuelNames))")

            Button(action: onToggleNotify) {
                Image(systemName: favourite.notifyOnDrop ? "bell.fill" : "bell.slash")
                    .foregroundStyle(favourite.notifyOnDrop ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isNotifyPending)
            .opacity(isNotifyPending ? 0.5 : 1)
            .buttonStyle(.plain)
            .accessibilityLabel(favourite.notifyOnDrop ? "Mute price-drop alerts" : "Enable price-drop alerts")
        }
    }
}

/// Reuses `CreateAlertSheet`'s fuel-type chip row, just without the radius slider — lets the user
/// change which fuel type an existing favourite tracks.
private struct FuelTypePickerSheet: View {
    let currentFuelType: String
    let useLongNames: Bool
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FuelType.allCases) { type in
                        let selected = currentFuelType == type.rawValue
                        Text(type.label(useLongNames: useLongNames))
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(Capsule().fill(selected ? type.color : Color.gray.opacity(0.15)))
                            .onTapGesture { onSelect(type.rawValue) }
                    }
                }
                .padding(16)
            }
            .navigationTitle("Track a different fuel type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.height(160)])
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
