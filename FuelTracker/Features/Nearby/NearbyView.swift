import SwiftUI
import GoogleMaps

/// Direct port of fuel-android's `NearbyScreen.kt`.
struct NearbyView: View {
    @Environment(FuelRepository.self) private var repository
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @Environment(\.appContainer) private var appContainer

    @State private var viewModel: NearbyViewModel?
    @State private var showPanel = false
    @State private var path: [Int] = []

    /// Matches Android's `failureThreshold = 2` — one transient blip shouldn't nag the user.
    private var apiUnreachable: Bool { repository.apiFailureCount >= 2 }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Fuel Tracker UK")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let viewModel {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.refresh()
                        } label: {
                            if viewModel.isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(viewModel.isLoading)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if showPanel, !viewModel.searchQuery.isEmpty {
                                viewModel.setSearchQuery("")
                            }
                            showPanel.toggle()
                        } label: {
                            Image(systemName: showPanel ? "xmark" : "magnifyingglass")
                        }
                    }
                }
            }
            .navigationDestination(for: Int.self) { stationId in
                DetailView(stationId: stationId)
            }
        }
        .onAppear {
            if viewModel == nil, let appContainer {
                viewModel = NearbyViewModel(
                    repository: appContainer.repository,
                    locationManager: appContainer.locationManager,
                    preferencesStore: appContainer.userPreferencesStore,
                    analytics: appContainer.analytics
                )
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: NearbyViewModel) -> some View {
        VStack(spacing: 0) {
            AnnouncementBanner()
            ZStack {
                mapLayer(viewModel)
                fuelTypePill(viewModel)
                recenterButton(viewModel)
                connectivityBanner(viewModel)
                if showPanel {
                    searchPanel(viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private func mapLayer(_ viewModel: NearbyViewModel) -> some View {
        // Falls back to the GPS-anchored station set until the user's first drag produces a
        // viewport load; the bottom list panel always keeps using viewModel.stations, unaffected
        // by dragging.
        let mapMarkers: [MapMarkerItem] = viewModel.isLoading ? [] : (viewModel.viewportStations ?? viewModel.stations).map { station in
            let cheapest = station.cheapestPrice(for: viewModel.selectedFuelType)
            return MapMarkerItem(
                stationId: station.id,
                lat: station.latitude,
                lng: station.longitude,
                title: station.name,
                snippet: cheapest.map { String(format: "%.1fp", $0.pricePence) } ?? "No price",
                color: UIColor(FuelType.color(forRaw: viewModel.selectedFuelType))
            )
        }

        // Don't render the map until a location is resolved — showing it centered on a hardcoded
        // fallback first, then jumping once the real one arrives, reads as a flash.
        if let userLat = viewModel.userLat, let userLng = viewModel.userLng {
            FuelMapView(
                centerLat: userLat,
                centerLng: userLng,
                zoomLevel: 12,
                markers: mapMarkers,
                onMarkerClick: { id in
                    viewModel.trackStationClick(id, source: "map")
                    // Handled via NavigationLink-style push below.
                    navigate(to: id)
                },
                recenterKey: viewModel.cameraRecenterToken,
                onCameraIdle: { bounds in viewModel.loadStationsInBounds(bounds) },
                showMyLocation: true
            )
            .ignoresSafeArea(edges: .bottom)
        } else {
            ProgressView()
        }
    }

    private func navigate(to stationId: Int) {
        path.append(stationId)
    }

    @ViewBuilder
    private func fuelTypePill(_ viewModel: NearbyViewModel) -> some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    let all = FuelType.allCases.map(\.rawValue)
                    let nextIndex = ((all.firstIndex(of: viewModel.selectedFuelType) ?? 0) + 1) % all.count
                    viewModel.setFuelType(all[nextIndex])
                } label: {
                    Text(FuelType(rawValue: viewModel.selectedFuelType)?.label(useLongNames: preferencesStore.preferences.useLongFuelNames) ?? viewModel.selectedFuelType)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(FuelType.color(forRaw: viewModel.selectedFuelType)))
                        .shadow(radius: 4)
                }
                .padding(12)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func recenterButton(_ viewModel: NearbyViewModel) -> some View {
        if viewModel.isOffGpsCenter {
            VStack {
                Spacer()
                HStack {
                    Button {
                        viewModel.recenterOnGps()
                    } label: {
                        Image(systemName: "location.fill")
                            .padding(14)
                            .background(Circle().fill(.background))
                            .shadow(radius: 4)
                    }
                    .padding(16)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func connectivityBanner(_ viewModel: NearbyViewModel) -> some View {
        if apiUnreachable {
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "wifi.slash")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Can't reach the fuel price service").font(.subheadline.bold())
                        Text("Check your connection — showing saved prices where available.")
                            .font(.caption)
                    }
                    Spacer()
                    Button("Retry") { viewModel.refresh() }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.red.opacity(0.15)))
                .padding(.horizontal, 12)
                .padding(.top, 64)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func searchPanel(_ viewModel: NearbyViewModel) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 0) {
                TextField("Search by name, postcode, or brand", text: Binding(
                    get: { viewModel.searchQuery },
                    set: { viewModel.setSearchQuery($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                if viewModel.searchQuery.count < 2 {
                    Picker("Mode", selection: Binding(
                        get: { viewModel.mode },
                        set: { viewModel.setMode($0) }
                    )) {
                        Text("Nearby").tag(ListMode.nearby)
                        Text("Cheapest").tag(ListMode.cheapest)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FuelType.allCases) { fuelType in
                            let selected = viewModel.selectedFuelType == fuelType.rawValue
                            Text(fuelType.label(useLongNames: preferencesStore.preferences.useLongFuelNames))
                                .font(.caption.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .foregroundStyle(selected ? .white : .primary)
                                .background(Capsule().fill(selected ? fuelType.color : Color.gray.opacity(0.15)))
                                .onTapGesture { viewModel.setFuelType(fuelType.rawValue) }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 8)

                if let error = viewModel.error {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                } else {
                    List {
                        Text("Prices: UK Gov Fuel Finder scheme (gov.uk/government/collections/fuel-finder). Independent app, not government-affiliated. Tap ⚠ to report incorrect data.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        ForEach(viewModel.stations, id: \.id) { station in
                            StationListRow(station: station, fuelType: viewModel.selectedFuelType, useLongNames: preferencesStore.preferences.useLongFuelNames) {
                                viewModel.trackStationClick(station.id, source: "list")
                                navigate(to: station.id)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background))
            .frame(height: UIScreen.main.bounds.height * 0.8)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

private struct StationListRow: View {
    let station: StationDTO
    let fuelType: String
    let useLongNames: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "fuelpump.fill").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).fontWeight(.medium)
                    Text([station.brand, station.distanceMiles.map { String(format: "%.1f mi", $0) }, station.postcode]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let price = station.cheapestPrice(for: fuelType) {
                    Text(String(format: "%.1fp", price.pricePence))
                        .font(.title3.bold())
                        .foregroundStyle(FuelType.color(forRaw: fuelType))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NearbyView()
}
