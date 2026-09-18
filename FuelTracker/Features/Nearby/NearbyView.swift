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
    @State private var showingAuth = false

    private let cheapestToggleTip = CheapestToggleTip()
    private let fuelTypePillTip = FuelTypePillTip()

    /// Matches Android's `failureThreshold = 2` — one transient blip shouldn't nag the user.
    private var apiUnreachable: Bool { repository.apiFailureCount >= 2 }

    /// The coach mark only ever makes sense to show while the panel is closed (it points at the
    /// button that opens it), and only until the user has seen it once, ever.
    private var shouldShowCheapestTip: Bool {
        !showPanel && !preferencesStore.preferences.hasSeenCheapestToggleTip
    }

    /// Chained to the Cheapest-toggle tip: eligible as soon as that one is marked seen, so it
    /// appears right after that tip is dismissed. Not tied to `showPanel` — unlike the toolbar
    /// button, the fuel-type pill lives on the map itself and stays visible regardless of the
    /// search panel's state. Gating on `hasSeenCheapestToggleTip` also means this never competes
    /// with the still-showing first tip, and an existing user who already dismissed the first tip
    /// before this shipped becomes eligible for this one immediately.
    private var shouldShowFuelTypePillTip: Bool {
        preferencesStore.preferences.hasSeenCheapestToggleTip && !preferencesStore.preferences.hasSeenFuelTypePillTip
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
            .sheet(isPresented: $showingAuth) {
                AuthView(onAuthed: {
                    showingAuth = false
                    Task { await viewModel?.refreshFavourites() }
                })
            }
            // Attached here — to the stack's own root content (the `Group` above, via this shared
            // modifier chain) — rather than to the `NavigationStack` itself below. `NavigationStack`
            // pushing/popping `DetailView` (via `.navigationDestination` above) only swaps what's
            // currently visible *inside* the stack; the `NavigationStack` view's own identity in
            // `NearbyView`'s body never disappears/reappears for that, so an `.onAppear` chained onto
            // it (as this used to be) only fires once, when `NearbyView` itself first mounts (or
            // remounts on a genuine tab switch — see `RootView`'s `hasRecordedAppOpen` comment) —
            // never on a Detail pop-back. The stack's *root content* view, in contrast, really is
            // removed from the visible hierarchy while `DetailView` is pushed and reinserted when the
            // user pops back, so an `.onAppear` here re-fires on exactly that transition — which is
            // what lets a favourite toggled on Detail be reflected back in this list's hearts without
            // requiring a tab switch away and back.
            .onAppear {
                if viewModel == nil, let appContainer {
                    viewModel = NearbyViewModel(
                        repository: appContainer.repository,
                        locationManager: appContainer.locationManager,
                        preferencesStore: appContainer.userPreferencesStore,
                        analytics: appContainer.analytics
                    )
                }
                // Refresh every time this screen's root content (re)appears — e.g. popping back from
                // Detail, where a station could have just been favourited/unfavourited there —
                // matching `FavouritesView`'s existing reappearance-reload convention.
                Task { await viewModel?.refreshFavourites() }
            }
        }
        .alert("Sign in required", isPresented: Binding(
            get: { viewModel?.needsSignIn ?? false },
            set: { newValue in if !newValue { viewModel?.needsSignIn = false } }
        )) {
            Button("Sign In") {
                viewModel?.needsSignIn = false
                showingAuth = true
            }
            Button("Cancel", role: .cancel) {
                viewModel?.needsSignIn = false
            }
        } message: {
            Text("Sign in to save favourite stations.")
        }
    }

    @ViewBuilder
    private func content(_ viewModel: NearbyViewModel) -> some View {
        VStack(spacing: 0) {
            AnnouncementBanner()
            ZStack {
                mapLayer(viewModel)
                fuelTypePill(viewModel)
                bottomLeftMapControls(viewModel)
                connectivityBanner(viewModel)
                viewportLoadingBar(viewModel)
                if showPanel {
                    searchPanel(viewModel)
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let message = viewModel.favouriteActionMessage {
                Text(message)
                    .font(.subheadline)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
                    .shadow(radius: 4)
                    .padding(.bottom, 24)
                    .task {
                        try? await Task.sleep(for: .seconds(3))
                        viewModel.clearFavouriteActionMessage()
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
                color: UIColor(FuelType.color(forRaw: viewModel.selectedFuelType)),
                isFavourite: viewModel.favouritesByStationId?[station.id] != nil
            )
        }

        // Don't render the map until a location is resolved — showing it centered on a hardcoded
        // fallback first, then jumping once the real one arrives, reads as a flash.
        if let userLat = viewModel.userLat, let userLng = viewModel.userLng {
            FuelMapView(
                centerLat: userLat,
                centerLng: userLng,
                zoomLevel: 12,
                bearing: viewModel.mapBearing,
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
                // Same `.popoverTip(_:)`-only-accepts-non-optional-Tip constraint as the toolbar
                // toggle's tip above, so this is gated by conditionally applying the modifier at
                // all, rather than by passing nil.
                let pillButton = Button {
                    let wasShowingTip = shouldShowFuelTypePillTip
                    let all = FuelType.allCases.map(\.rawValue)
                    let nextIndex = ((all.firstIndex(of: viewModel.selectedFuelType) ?? 0) + 1) % all.count
                    viewModel.setFuelType(all[nextIndex])
                    if wasShowingTip {
                        preferencesStore.markFuelTypePillTipSeen()
                    }
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

                if shouldShowFuelTypePillTip {
                    // The pill sits near the top of the screen, so — same reasoning as the toolbar
                    // toggle's tip — `arrowEdge` names the edge of the anchor (this pill) the tip's
                    // arrow touches: `.bottom` touches the pill's bottom edge, arrow pointing up
                    // into it, rendering the tip's body below the pill.
                    pillButton.popoverTip(fuelTypePillTip, arrowEdge: .bottom)
                } else {
                    pillButton
                }
            }
            Spacer()
        }
    }

    /// Bottom-left FAB stack: the orientation toggle is always visible at the anchor position, with
    /// the recenter button (only shown once the user's dragged off GPS-center) appearing above it —
    /// so the always-visible toggle's position never shifts depending on whether recenter happens
    /// to be showing.
    @ViewBuilder
    private func bottomLeftMapControls(_ viewModel: NearbyViewModel) -> some View {
        VStack {
            Spacer()
            HStack {
                VStack(spacing: 12) {
                    if viewModel.isOffGpsCenter {
                        recenterButton(viewModel)
                    }
                    mapOrientationButton(viewModel)
                }
                .padding(16)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func recenterButton(_ viewModel: NearbyViewModel) -> some View {
        Button {
            viewModel.recenterOnGps()
        } label: {
            Image(systemName: "location.fill")
                .padding(14)
                .background(Circle().fill(.background))
                .shadow(radius: 4)
        }
        .accessibilityLabel("Recenter on my location")
    }

    @ViewBuilder
    private func mapOrientationButton(_ viewModel: NearbyViewModel) -> some View {
        Button {
            viewModel.toggleMapOrientation()
        } label: {
            Image(systemName: viewModel.mapOrientationMode == .northUp ? "location.north.line.fill" : "location.north.fill")
                .padding(14)
                .background(Circle().fill(.background))
                .shadow(radius: 4)
        }
        .accessibilityLabel(
            viewModel.mapOrientationMode == .northUp
                ? "North up. Tap to follow direction of travel."
                : "Following direction of travel. Tap to switch to north up."
        )
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
                    // `DataAttributionNotice` (the Guideline-5.6 "Report a price discrepancy" +
                    // source-attribution block) must stay visible in every non-error state, not
                    // only when there happen to be rows — so the `List` itself is always present,
                    // and only the row content above the notice switches between the empty state
                    // and the real rows.
                    List {
                        if !isSearching && rows.isEmpty {
                            emptyNearbyState(viewModel)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                        } else {
                            ForEach(rows, id: \.id) { station in
                                StationListRow(
                                    station: station,
                                    fuelType: viewModel.selectedFuelType,
                                    useLongNames: preferencesStore.preferences.useLongFuelNames,
                                    userLat: viewModel.userLat,
                                    userLng: viewModel.userLng,
                                    isFavourite: viewModel.favouritesByStationId.map { $0[station.id] != nil },
                                    isPending: viewModel.pendingFavouriteToggles.contains(station.id),
                                    onTap: {
                                        viewModel.trackStationClick(station.id, source: "list")
                                        navigate(to: station.id)
                                    },
                                    onToggleFavourite: { Task { await viewModel.toggleFavourite(station) } }
                                )
                            }
                        }

                        DataAttributionNotice()
                            .listRowInsets(EdgeInsets())
                    }
                    .listStyle(.plain)
                }
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.background))
            .frame(height: UIScreen.main.bounds.height * 0.67)
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
