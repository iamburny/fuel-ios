import SwiftUI

/// Direct port of fuel-android's `PricesScreen.kt`.
struct PricesView: View {
    @Environment(\.appContainer) private var appContainer
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @State private var viewModel: PricesViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    if viewModel.isLoading {
                        ProgressView()
                    } else if let error = viewModel.error {
                        Text("Error: \(error)").foregroundStyle(.red)
                    } else {
                        content(viewModel)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Prices & Trends")
            .navigationDestination(for: String.self) { _ in
                HeatmapView()
            }
        }
        .onAppear {
            if viewModel == nil, let appContainer {
                viewModel = PricesViewModel(repository: appContainer.repository)
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: PricesViewModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                NavigationLink(value: "heatmap") {
                    heatmapLinkCard
                }
                .buttonStyle(.plain)
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                if let selected = viewModel.averages.first(where: { $0.fuelType == viewModel.selectedFuelType }) {
                    Text(FuelType.label(forRaw: viewModel.selectedFuelType, useLongNames: preferencesStore.preferences.useLongFuelNames))
                        .font(.title3.bold())
                        .padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                    HStack(spacing: 12) {
                        statCard("Average", String(format: "%.1fp", selected.avgPricePence))
                        statCard("Cheapest", String(format: "%.1fp", selected.minPricePence))
                        statCard("Highest", String(format: "%.1fp", selected.maxPricePence))
                        statCard("Stations", "\(selected.stationCount)")
                    }
                    .padding(.horizontal, 16)
                }

                Divider().padding(.top, 16)

                Text("All Fuel Types").font(.title3.bold()).padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    ForEach(viewModel.averages, id: \.fuelType) { avg in
                        Button {
                            viewModel.setFuelType(avg.fuelType)
                        } label: {
                            fuelTypeCard(avg, isSelected: avg.fuelType == viewModel.selectedFuelType)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()

                Text("Price Trend").font(.title3.bold()).padding(EdgeInsets(top: 12, leading: 16, bottom: 4, trailing: 16))

                HStack(spacing: 8) {
                    ForEach([7, 30, 90], id: \.self) { days in
                        let selected = viewModel.selectedDays == days
                        Text("\(days)d")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(selected ? .white : .primary)
                            .background(Capsule().fill(selected ? Color.accentColor : Color.gray.opacity(0.15)))
                            .onTapGesture { viewModel.setDays(days) }
                    }
                }
                .padding(.horizontal, 16)

                if !viewModel.trend.isEmpty {
                    // Scale to the plotted average line's own range (not the daily all-station
                    // min/max, which would squash the line flat near the bottom).
                    PriceLineChart(
                        values: viewModel.trend.map(\.avgPricePence),
                        dates: viewModel.trend.map(\.date),
                        lineColor: FuelType.displayColor(forRaw: viewModel.selectedFuelType)
                    )
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }

                Divider().padding(.top, 16)

                DataAttributionNotice(
                    noticeText: viewModel.dataNotice.isEmpty ? DataAttributionNotice.defaultText : viewModel.dataNotice
                )
            }
        }
    }

    private var heatmapLinkCard: some View {
        HStack {
            Image(systemName: "flame.fill").foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("UK Price Heat Map").font(.headline.bold()).foregroundStyle(.white)
                Text("See how prices compare to the national average, by area")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Image(systemName: "arrow.forward").foregroundStyle(.white)
        }
        .padding(16)
        .background(
            LinearGradient(colors: [
                Color(red: 0x16 / 255, green: 0xA3 / 255, blue: 0x4A / 255),
                Color(red: 0xEA / 255, green: 0xB3 / 255, blue: 0x08 / 255),
                Color(red: 0xDC / 255, green: 0x26 / 255, blue: 0x26 / 255),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.08)))
    }

    @ViewBuilder
    private func fuelTypeCard(_ avg: NationalAverageDTO, isSelected: Bool) -> some View {
        let color = FuelType.displayColor(forRaw: avg.fuelType)
        VStack(alignment: .leading, spacing: 4) {
            Text(FuelType.label(forRaw: avg.fuelType, useLongNames: preferencesStore.preferences.useLongFuelNames))
                .font(.subheadline.bold())
                .foregroundStyle(color)
            Text(String(format: "%.1fp", avg.avgPricePence)).font(.title3.bold())
            Text(String(format: "%.1f \u{2013} %.1f", avg.minPricePence, avg.maxPricePence))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? color.opacity(0.15) : Color.gray.opacity(0.08)))
    }
}

#Preview {
    PricesView()
}
