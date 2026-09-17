import SwiftUI

/// Modal overlay listing the exact same stations currently pinned on the map, re-sorted by price
/// for the selected fuel type — entirely client-side (see `NearbyViewModel.cheapestStations`), no
/// network call. Tapping a row dismisses the sheet and centers the map on that station's pin; it
/// never navigates to Detail.
struct CheapestSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UserPreferencesStore.self) private var preferencesStore

    let viewModel: NearbyViewModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cheapest nearby")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            FuelTypeChipRow(
                selectedFuelType: viewModel.selectedFuelType,
                useLongNames: preferencesStore.preferences.useLongFuelNames,
                onSelect: { viewModel.setFuelType($0) }
            )
            .padding(.vertical, 8)

            let stations = viewModel.cheapestStations
            if stations.isEmpty {
                emptyState
            } else {
                List(stations, id: \.id) { station in
                    StationListRow(
                        station: station,
                        fuelType: viewModel.selectedFuelType,
                        useLongNames: preferencesStore.preferences.useLongFuelNames
                    ) {
                        viewModel.focusStation(station)
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    /// Two distinct empty states: nothing pinned on the map yet at all (still loading, or a
    /// transient failure), vs. a pinned set that exists but none of those stations report a price
    /// for the currently selected fuel type.
    @ViewBuilder
    private var emptyState: some View {
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
