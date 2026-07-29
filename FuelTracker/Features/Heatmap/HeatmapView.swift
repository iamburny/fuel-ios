import SwiftUI

/// Direct port of fuel-android's `HeatmapScreen.kt`. Reached via a card button on Prices, not a
/// tab — pushed as a NavigationStack destination.
struct HeatmapView: View {
    @Environment(\.appContainer) private var appContainer
    @Environment(UserPreferencesStore.self) private var preferencesStore
    @State private var viewModel: HeatmapViewModel?
    @State private var selectedCell: HeatmapCell?

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Price Heat Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if viewModel == nil, let appContainer {
                viewModel = HeatmapViewModel(repository: appContainer.repository, preferencesStore: appContainer.userPreferencesStore)
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: HeatmapViewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FuelType.allCases) { fuelType in
                        let isSelected = viewModel.fuelType == fuelType.rawValue
                        Text(fuelType.label(useLongNames: preferencesStore.preferences.useLongFuelNames))
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .background(Capsule().fill(isSelected ? fuelType.color : Color.gray.opacity(0.15)))
                            .onTapGesture {
                                selectedCell = nil
                                viewModel.setFuelType(fuelType.rawValue)
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Text(String(format: "National average: %.1fp", viewModel.nationalAvg))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)

            ZStack {
                HeatmapMapView(cells: viewModel.cells, maxAbs: viewModel.maxAbs) { cell in
                    selectedCell = cell
                }
                .ignoresSafeArea(edges: .bottom)

                if viewModel.loading {
                    ProgressView()
                }

                if let error = viewModel.error {
                    Text(error)
                        .padding(16)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.15)))
                        .padding(24)
                }

                if let cell = selectedCell {
                    VStack {
                        cellDetailCard(cell)
                            .padding(12)
                        Spacer()
                    }
                }

                if !viewModel.loading && viewModel.error == nil {
                    VStack {
                        Spacer()
                        HStack {
                            legend(maxAbs: viewModel.maxAbs)
                            Spacer()
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    @ViewBuilder
    private func cellDetailCard(_ cell: HeatmapCell) -> some View {
        let sign = cell.deltaPence > 0 ? "+" : ""
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.1fp avg", cell.avgPricePence)).font(.subheadline.bold())
            Text("\(sign)\(String(format: "%.1fp", cell.deltaPence)) vs national (\(sign)\(String(format: "%.1f%%", cell.deltaPercent)))")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(cell.stationCount) station\(cell.stationCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        .shadow(radius: 3)
    }

    @ViewBuilder
    private func legend(maxAbs: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Price vs national").font(.caption2).foregroundStyle(.secondary)
            LinearGradient(
                colors: [HeatColor.color(delta: -maxAbs, maxAbs: maxAbs), HeatColor.color(delta: 0, maxAbs: maxAbs), HeatColor.color(delta: maxAbs, maxAbs: maxAbs)],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: 140, height: 10)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            HStack {
                Text(String(format: "\u{2212}%.1fp", maxAbs)).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "+%.1fp", maxAbs)).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 140)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.regularMaterial))
        .shadow(radius: 3)
    }
}
