import SwiftUI
import GoogleMaps
import TipKit

/// Direct port of fuel-android's `NearbyScreen.kt`.
struct NearbyView: View {
    @Environment(FuelRepository.self) private var repository
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @Environment(\.appContainer) private var appContainer

    @State private var viewModel: NearbyViewModel?
    @State private var showPanel = false
    @State private var path: [Int] = []

    private let cheapestToggleTip = CheapestToggleTip()

    /// Matches Android's `failureThreshold = 2` — one transient blip shouldn't nag the user.
    private var apiUnreachable: Bool { repository.apiFailureCount >= 2 }

    /// The coach mark only ever makes sense to show while the panel is closed (it points at the
    /// button that opens it), and only until the user has seen it once, ever.
    private var shouldShowCheapestTip: Bool {
        !showPanel && !preferencesStore.preferences.hasSeenCheapestToggleTip
    }

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
                                // Matches Android's compact in-bar CircularProgressIndicator
                                // (20dp, 2dp stroke) rather than SwiftUI's larger default size.
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(viewModel.isLoading)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // `.popoverTip(_:)` only accepts a non-optional Tip at our iOS 17 deployment
                        // target (passing an Optional Tip resolves to an iOS 26+-only overload), so
                        // the tip is gated by conditionally applying the modifier at all, rather than
                        // by passing nil.
                        let toggleButton = Button {
                            // Was the tip visible before this tap? If so, this interaction is what
                            // dismisses it, so mark it seen now rather than at trigger time.
                            let wasShowingTip = shouldShowCheapestTip
                            if showPanel, !viewModel.searchQuery.isEmpty {
                                viewModel.setSearchQuery("")
                            }
                            showPanel.toggle()
                            if wasShowingTip {
                                preferencesStore.markCheapestToggleTipSeen()
                            }
                        } label: {
                            Image(systemName: showPanel ? "xmark" : "sterlingsign.circle")
                        }
                        .accessibilityLabel(showPanel ? "Close" : "Cheapest prices")

                        if shouldShowCheapestTip {
                            // `arrowEdge` names the edge of the *anchor* (this button) that the
                            // tip's arrow touches — `.bottom` means the arrow touches the
                            // button's bottom edge, pointing up into it, which puts the tip's
                            // speech-bubble body below the button (the default, `.top`, would
                            // render it above the button with the arrow pointing down).
                            toggleButton.popoverTip(cheapestToggleTip, arrowEdge: .bottom)
                        } else {
                            toggleButton
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
                viewportLoadingBar(viewModel)
                if showPanel {
                    searchPanel(viewModel)
                }
            }
        }
    }

    @ViewBuilder
    private func mapLayer(_ viewModel: NearbyViewModel) -> some View {
        // Falls back to the GPS-anchored station set until the user's first drag produces a
        // viewport load; the bottom list panel's default (non-search) list tracks the same set via
        // `nearbyStationsSortedByPrice`, so it stays in sync with the map, including after a drag.
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

    /// Thin browser-style progress bar while a drag-triggered viewport reload is in flight — the
    /// pins themselves don't disappear (old ones stay until the new response lands), so without
    /// this the long pause after a drag reads as the app being stuck. Mirrors Android's top
    /// `LinearProgressIndicator` and web's `.map-loading-bar`.
    @ViewBuilder
    private func viewportLoadingBar(_ viewModel: NearbyViewModel) -> some View {
        if viewModel.isLoadingViewport {
            VStack {
                ProgressView()
                    .progressViewStyle(.linear)
                    .frame(height: 3)
                    .tint(.accentColor)
                Spacer()
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
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search by name, postcode, or brand", text: Binding(
                        get: { viewModel.searchQuery },
                        set: { viewModel.setSearchQuery($0) }
                    ))
                    if !viewModel.searchQuery.isEmpty {
                        Button {
                            viewModel.setSearchQuery("")
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator)))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)

                FuelTypeChipRow(
                    selectedFuelType: viewModel.selectedFuelType,
                    useLongNames: preferencesStore.preferences.useLongFuelNames,
                    onSelect: { viewModel.setFuelType($0) }
                )
                .padding(.bottom, 8)

                if let error = viewModel.error {
                    Text("Error: \(error)")
                        .foregroundStyle(.red)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                } else {
                    let isSearching = viewModel.searchQuery.count >= 2
                    let rows = isSearching ? viewModel.stations : viewModel.nearbyStationsSortedByPrice
                    if !isSearching && rows.isEmpty {
                        emptyNearbyState(viewModel)
                    } else {
                        List {
                            ForEach(rows, id: \.id) { station in
                                StationListRow(station: station, fuelType: viewModel.selectedFuelType, useLongNames: preferencesStore.preferences.useLongFuelNames) {
                                    viewModel.trackStationClick(station.id, source: "list")
                                    navigate(to: station.id)
                                }
                            }

                            DataAttributionNotice()
                                .listRowInsets(EdgeInsets())
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background))
            .frame(height: UIScreen.main.bounds.height * 0.8)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    /// Two distinct empty states, ported from the now-deleted `CheapestSheetView`: nothing pinned on
    /// the map yet at all (still loading, or a transient failure), vs. a pinned set that exists but
    /// none of those stations report a price for the currently selected fuel type. Only shown for
    /// the non-search, zero-results case — search keeps its existing (list-with-no-rows) behavior.
    @ViewBuilder
    private func emptyNearbyState(_ viewModel: NearbyViewModel) -> some View {
        let pinnedStations = viewModel.viewportStations ?? viewModel.stations
        let fuelLabel = FuelType(rawValue: viewModel.selectedFuelType)?
            .label(useLongNames: preferencesStore.preferences.useLongFuelNames) ?? viewModel.selectedFuelType

        VStack(spacing: 8) {
            Image(systemName: "fuelpump.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            if pinnedStations.isEmpty {
                Text("No stations loaded yet")
                    .font(.headline)
                Text("Hang tight while nearby stations load.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No nearby stations currently report a \(fuelLabel) price")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NearbyView()
}
