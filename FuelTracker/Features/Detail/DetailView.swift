import SwiftUI
import GoogleMaps

/// Direct port of fuel-android's `DetailScreen.kt`.
struct DetailView: View {
    let stationId: Int

    @Environment(\.appContainer) private var appContainer
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @Environment(\.openURL) private var openURL
    @State private var viewModel: DetailViewModel?

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
        .navigationTitle(viewModel?.station?.name ?? "Station")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let viewModel {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.toggleFavourite() }
                    } label: {
                        Image(systemName: viewModel.isFavourite ? "heart.fill" : "heart")
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
        }
    }

    @ViewBuilder
    private func detailContent(station: StationDTO, viewModel: DetailViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FuelMapView(
                    centerLat: station.latitude, centerLng: station.longitude, zoomLevel: 15,
                    markers: [MapMarkerItem(stationId: nil, lat: station.latitude, lng: station.longitude, title: station.name, snippet: nil, color: nil)]
                )
                .frame(height: 200)

                VStack(alignment: .leading, spacing: 4) {
                    if let brand = station.brand {
                        Text(brand).font(.subheadline.bold()).foregroundStyle(.tint)
                    }

                    statusBadges(station)

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

                    Button {
                        let url = URL(string: "https://maps.apple.com/?daddr=\(station.latitude),\(station.longitude)")!
                        openURL(url)
                    } label: {
                        Label("Get directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .padding(16)

                Divider()

                Text("Current Prices").font(.title3.bold()).padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                if station.prices.isEmpty {
                    Text("No prices currently available for this station.")
                        .padding(16)
                } else {
                    ForEach(station.prices.sorted { $0.pricePence < $1.pricePence }, id: \.fuelType) { price in
                        priceRow(price, averages: viewModel.nationalAverages)
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
                            ForEach(FuelType.allCases) { type in
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
                            lineColor: FuelType.color(forRaw: viewModel.selectedFuelType)
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

                Divider()

                DataAttributionNotice()
            }
        }
    }

    @ViewBuilder
    private func statusBadges(_ station: StationDTO) -> some View {
        let badges: [(String, Color)] = [
            station.temporaryClosure ? ("Temporarily Closed", .red) : nil,
            station.isMotorway ? ("Motorway Services", Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)) : nil,
            station.isSupermarket ? ("Supermarket", Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)) : nil,
        ].compactMap { $0 }

        if !badges.isEmpty {
            HStack(spacing: 8) {
                ForEach(badges, id: \.0) { label, color in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.15)))
                }
            }
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private func priceRow(_ price: PriceDTO, averages: [NationalAverageDTO]) -> some View {
        let nationalAvg = averages.first { $0.fuelType == price.fuelType }?.avgPricePence
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FuelType.longLabel(forRaw: price.fuelType)).fontWeight(.medium)
                // Compliance: shown unmodified, original ISO string, not reformatted/relativized.
                Text("Reported: \(price.reportedAt)").font(.caption).foregroundStyle(.secondary)
                if let nationalAvg {
                    let delta = price.pricePence - nationalAvg
                    Text(String(format: "%+.1fp vs national avg", delta))
                        .font(.caption2)
                        .foregroundStyle(delta <= 0 ? Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255) : .red)
                }
            }
            Spacer()
            Text(String(format: "%.1fp", price.pricePence))
                .font(.title2.bold())
                .foregroundStyle(FuelType.color(forRaw: price.fuelType))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func bankHolidayHours(_ holiday: BankHolidayDTO) -> String {
        if holiday.is24Hours == true { return "24 hours" }
        if let open = holiday.openTime, let close = holiday.closeTime { return "\(open) – \(close)" }
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
