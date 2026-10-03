import SwiftUI
import MapKit

@Observable
@MainActor
final class ClipStationViewModel {
    enum State {
        case loading
        case loaded(StationDTO)
        case failed
    }

    private(set) var state: State = .loading
    private(set) var nationalAverages: [NationalAverageDTO] = []

    private let stationId: Int
    private let api: FuelPricesAPI

    init(stationId: Int, api: FuelPricesAPI) {
        self.stationId = stationId
        self.api = api
    }

    func load() async {
        state = .loading
        async let averages = api.getNationalAverages()
        do {
            state = .loaded(try await api.getStation(id: stationId))
        } catch {
            state = .failed
        }
        // Only used for the "vs national avg" line, so a failure just leaves it off.
        nationalAverages = (try? await averages.averages) ?? []
    }
}

/// A single station's prices, the App Clip's whole job. Uses MapKit rather than the full app's
/// Google Maps SDK, which would push the clip past its size limit.
struct ClipStationView: View {
    let stationId: Int

    @State private var viewModel: ClipStationViewModel?
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            switch viewModel?.state {
            case .loaded(let station):
                content(station)
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't load this station", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Check your connection and try again.")
                } actions: {
                    Button("Try Again") { Task { await viewModel?.load() } }
                }
            case .loading, nil:
                ProgressView()
            }
        }
        .task {
            if viewModel == nil {
                let client = APIClient(baseURL: AppConfig.apiBaseURL, tokenStore: TokenStore())
                viewModel = ClipStationViewModel(stationId: stationId, api: FuelPricesAPIClient(client: client))
            }
            await viewModel?.load()
        }
    }

    private func content(_ station: StationDTO) -> some View {
        let coordinate = CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)
        let name = StationText.displayName(station.name)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 800, longitudinalMeters: 800))) {
                    Marker(name, coordinate: coordinate)
                }
                .frame(height: 240)

                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
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

                    Button {
                        openURL(URL(string: "https://maps.apple.com/?daddr=\(station.latitude),\(station.longitude)")!)
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
                    ForEach(station.prices.sorted { $0.headlineSortKey < $1.headlineSortKey }, id: \.fuelType) { price in
                        StationPriceRow(price: price, nationalAverages: viewModel?.nationalAverages ?? [])
                        Divider().padding(.leading, 16)
                    }
                }

                DataAttributionNotice()
                    .padding(.top, 16)
            }
            // Room for the App Store overlay that slides up over the bottom of the screen.
            .padding(.bottom, 100)
        }
    }
}
