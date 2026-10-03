import SwiftUI
import GoogleMaps

/// Direct port of fuel-android's `DetailScreen.kt`.
struct DetailView: View {
    let stationId: Int

    @Environment(\.appContainer) private var appContainer
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @Environment(FuelRepository.self) private var repository
    @Environment(FeatureFlags.self) private var featureFlags
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: DetailViewModel?
    @State private var ratingsViewModel: StationRatingsViewModel?
    @State private var showingRateSheet = false
    @State private var showingAuth = false
    /// Set when "Rate this station" sent a signed-out user to sign in, so the rate sheet opens
    /// once they're back.
    @State private var rateAfterSignIn = false
    /// A favourite tapped while signed out, saved once the auth sheet closes signed in.
    @State private var favouriteAfterSignIn = false

    /// Defaults to false so ratings can be switched off remotely; see `FeatureFlags`.
    private var ratingsEnabled: Bool { featureFlags.isEnabled("shared.station-ratings", default: false) }

    var body: some View {
        Group {
            if let viewModel {
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let station = viewModel.station {
                    detailContent(station: station, viewModel: viewModel)
                } else if let error = viewModel.error {
                    ContentUnavailableView("Couldn't load station", systemImage: "exclamationmark.triangle", description: Text(error))
                }
            } else {
                ProgressView()
            }
        }
        // No bar title: there's no room for a forecourt name beside the toolbar's buttons, so the
        // name is the heading under the map instead.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let viewModel {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        if ratingsEnabled, let station = viewModel.station {
                            ratingBadge(summary: station.ratingSummary)
                        }
                        if viewModel.isFavourite {
                            Button {
                                Task { await viewModel.toggleNotify() }
                            } label: {
                                Image(systemName: viewModel.notifyOnDrop ? "bell.fill" : "bell.slash")
                                    .floatingBacking()
                            }
                            .disabled(viewModel.pendingFavouriteToggle)
                            .accessibilityLabel(viewModel.notifyOnDrop ? "Mute price-drop alerts" : "Enable price-drop alerts")
                        }
                        Button {
                            if repository.isLoggedIn {
                                Task { await viewModel.toggleFavourite() }
                            } else {
                                favouriteAfterSignIn = true
                                showingAuth = true
                            }
                        } label: {
                            Image(systemName: viewModel.isFavourite ? "heart.fill" : "heart")
                                .floatingBacking()
                        }
                        .disabled(viewModel.pendingFavouriteToggle)
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil, let appContainer {
                viewModel = DetailViewModel(
                    stationId: stationId,
                    repository: appContainer.repository,
                    locationManager: appContainer.locationManager,
                    preferencesStore: appContainer.userPreferencesStore,
                    analytics: appContainer.analytics
                )
            }
            if ratingsViewModel == nil, let appContainer {
                ratingsViewModel = StationRatingsViewModel(
                    stationId: stationId,
                    repository: appContainer.repository,
                    analytics: appContainer.analytics
                )
            }
        }
        .sheet(isPresented: $showingAuth, onDismiss: {
            if favouriteAfterSignIn && repository.isLoggedIn {
                Task { await viewModel?.completeFavouriteAfterSignIn() }
            }
            favouriteAfterSignIn = false
            // Opened only after the auth sheet has fully gone, since one view can't present two
            // sheets at once.
            if rateAfterSignIn && repository.isLoggedIn {
                openRateSheet()
            }
            rateAfterSignIn = false
        }) {
            AuthView(onAuthed: { showingAuth = false })
        }
        .sheet(isPresented: $showingRateSheet) {
            if let ratingsViewModel {
                RateStationSheet(
                    viewModel: ratingsViewModel,
                    stationName: viewModel?.station?.name ?? "",
                    useLongNames: preferencesStore.preferences.useLongFuelNames,
                    onClose: { showingRateSheet = false }
                )
            }
        }
        // Signing in or out (including a session that expired mid-visit) changes what the ratings
        // section offers, so it re-reads the user's own state.
        .onChange(of: repository.isLoggedIn) { _, _ in
            guard ratingsEnabled else { return }
            Task { await ratingsViewModel?.authChanged() }
        }
        // Email verification completes on the website, so coming back to the app is the cue to
        // check whether the user can rate now.
        .onChange(of: scenePhase) { _, phase in
            guard ratingsEnabled, phase == .active else { return }
            Task { await ratingsViewModel?.refreshMine() }
        }
    }

    /// Rating starts from the toolbar star or the Driver reports section; a signed-out user signs
    /// in first and the sheet opens once the auth sheet has gone.
    private func rateTapped() {
        if repository.isLoggedIn {
            openRateSheet()
        } else {
            rateAfterSignIn = true
            showingAuth = true
        }
    }

    @ViewBuilder
    private func stationActions(_ station: StationDTO) -> some View {
        Button {
            let url = URL(string: "https://maps.apple.com/?daddr=\(station.latitude),\(station.longitude)")!
            openURL(url)
        } label: {
            Label("Get directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
        }
        .buttonStyle(.bordered)

        if ratingsEnabled, let ratingsViewModel {
            Button(action: rateTapped) {
                Label(ratingsViewModel.rateButtonTitle, systemImage: "star")
            }
            .buttonStyle(.bordered)
        }
    }

    /// The station's driver score beside the favourite heart, and the quickest way to rate it: the
    /// average with a filled star once enough drivers have rated it, an outlined star until then.
    private func ratingBadge(summary: RatingSummaryDTO?) -> some View {
        Button(action: rateTapped) {
            if let summary {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(AccuracyWarningChip.tint)
                    Text(String(format: "%.1f", summary.avgStars))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 6)
                .floatingBacking()
            } else {
                Image(systemName: "star")
                    .floatingBacking()
            }
        }
        .accessibilityLabel(
            summary.map {
                "Rated \(String(format: "%.1f", $0.avgStars)) out of 5 by \($0.raterCount) drivers. Rate this station"
            } ?? "Rate this station"
        )
    }

    private func openRateSheet() {
        guard let ratingsViewModel, let viewModel, let station = viewModel.station else { return }
        ratingsViewModel.openRateSheet(
            fuelTypes: StationRatingsViewModel.ratableFuelTypes(for: station),
            defaultFuelType: preferencesStore.preferences.fuelType
        )
        showingRateSheet = true
    }

    @ViewBuilder
    private func detailContent(station: StationDTO, viewModel: DetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FuelMapView(
                    centerLat: station.latitude, centerLng: station.longitude, zoomLevel: 15,
                    markers: [MapMarkerItem(stationId: nil, lat: station.latitude, lng: station.longitude, title: station.name, snippet: nil, color: nil)]
                )
                // Taller than the space it shows: the top runs up under the status and navigation
                // bars, which float over it on a faint fade.
                .frame(height: 300)
                .overlay(alignment: .top) {
                    LinearGradient(colors: [.black.opacity(0.18), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 140)
                        .allowsHitTesting(false)
                }

                VStack(alignment: .leading, spacing: 4) {
                    // The feed is mostly ALL CAPS; shown in the same title case as the website.
                    Text(StationText.displayName(station.name))
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                    if let brand = station.brand {
                        Text(brand).font(.subheadline.bold()).foregroundStyle(.tint)
                    }

                    StationStatusBadges(station: station)

                    let address = [station.addressLine1, station.addressLine2, station.town, station.postcode]
                        .compactMap { $0 }.joined(separator: ", ")
                    if !address.isEmpty {
                        Text(address).font(.body)
                    }

                    if let distance = viewModel.distanceMiles {
                        Text(String(format: "%.1f miles away", distance)).font(.caption)
                    }
                    if let driveCost = viewModel.driveCostPounds {
                        Text(String(format: "Est. £%.2f in fuel to get here", driveCost))
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }

                    if let phone = station.phone {
                        Button {
                            if let url = URL(string: "tel:\(phone.filter { !$0.isWhitespace })") { openURL(url) }
                        } label: {
                            Label(phone, systemImage: "phone.fill")
                        }
                        .font(.subheadline)
                        .padding(.top, 4)
                    }

                    // The station's two actions, side by side, stacking when the screen is too narrow.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) { stationActions(station) }
                        VStack(alignment: .leading, spacing: 8) { stationActions(station) }
                    }
                    .padding(.top, 8)
                }
                .padding(16)

                Divider()

                Text("Current Prices").font(.title3.bold()).padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                if station.prices.isEmpty {
                    Text("No prices currently available for this station.")
                        .padding(16)
                } else {
                    ForEach(station.prices.sorted { $0.headlineSortKey < $1.headlineSortKey }, id: \.fuelType) { price in
                        StationPriceRow(price: price, nationalAverages: viewModel.nationalAverages)
                        Divider().padding(.leading, 16)
                    }
                }

                Divider()

                let amenities = AmenitiesFormatter.displayList(for: station.amenities)
                if !amenities.isEmpty {
                    Text("Amenities").font(.title3.bold()).padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                    FlowLayout(spacing: 8) {
                        ForEach(amenities, id: \.self) { label in
                            Text(label)
                                .font(.footnote)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.gray.opacity(0.15)))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    Divider()
                }

                if let usualDays = station.openingHours?.usualDays {
                    Text("Opening Hours").font(.title3.bold()).padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))
                    OpeningHoursTableView(days: usualDays)

                    if let holidays = station.openingHours?.bankHolidays, !holidays.isEmpty {
                        Text("Bank Holidays").font(.subheadline.bold()).padding(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))
                        ForEach(Array(holidays.enumerated()), id: \.offset) { _, holiday in
                            HStack {
                                Text(holiday.type ?? "Bank Holiday")
                                Spacer()
                                Text(bankHolidayHours(holiday))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                    Divider()
                }

                if !station.prices.isEmpty {
                    Text("Price History (30 days)").font(.title3.bold()).padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(station.availableFuelTypes) { type in
                                let selected = viewModel.selectedFuelType == type.rawValue
                                Text(type.label(useLongNames: preferencesStore.preferences.useLongFuelNames))
                                    .font(.caption.bold())
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(selected ? .white : .primary)
                                    .background(Capsule().fill(selected ? type.color : Color.gray.opacity(0.15)))
                                    .onTapGesture { Task { await viewModel.setFuelType(type.rawValue) } }
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if !viewModel.priceHistory.isEmpty {
                        PriceLineChart(
                            values: viewModel.priceHistory.map(\.pricePence),
                            dates: viewModel.priceHistory.map(\.reportedAt),
                            lineColor: FuelType.displayColor(forRaw: viewModel.selectedFuelType)
                        )
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    } else {
                        Text("No price history available for this fuel type.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                }

                if ratingsEnabled, let ratingsViewModel {
                    Divider()

                    StationRatingsSection(
                        viewModel: ratingsViewModel,
                        summary: station.ratingSummary,
                        useLongNames: preferencesStore.preferences.useLongFuelNames,
                        onSignIn: { showingAuth = true }
                    )
                }

                Divider()

                DataAttributionNotice()
            }
        }
        // The navigation bar is see-through over the map and turns solid as content scrolls under it.
        .ignoresSafeArea(edges: .top)
    }

    private func bankHolidayHours(_ holiday: BankHolidayDTO) -> String {
        if holiday.is24Hours == true { return "24 hours" }
        if let open = holiday.openTime, let close = holiday.closeTime {
            return "\(OpeningHoursFormatter.format(open)) – \(OpeningHoursFormatter.format(close))"
        }
        return "Closed"
    }
}

/// Minimal flow layout for amenity chips (SwiftUI has no built-in wrap-row container pre-iOS 18's
/// `HFlow`/`VFlow` from the Layout protocol becoming broadly available; this keeps the deployment
/// target at iOS 17).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: width == .infinity ? rowWidth : width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension View {
    /// A round backing so a toolbar button stays legible over the map that runs under the bar.
    func floatingBacking() -> some View {
        frame(minWidth: 34, minHeight: 34)
            .background(.regularMaterial, in: Capsule())
    }
}
