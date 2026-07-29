import Foundation
import Observation

/// Direct port of fuel-android's `HeatmapViewModel.kt`.
@Observable
@MainActor
final class HeatmapViewModel {
    var loading = true
    var error: String?
    var fuelType = FuelType.default.rawValue
    var nationalAvg: Double = 0
    var cells: [HeatmapCell] = []
    /// Pence deviation that saturates the colour scale (90th-percentile of |delta|, floored at 3p).
    var maxAbs: Double = 3.0

    private let repository: FuelRepository

    init(repository: FuelRepository, preferencesStore: UserPreferencesStore) {
        self.repository = repository
        fuelType = preferencesStore.preferences.fuelType
        Task { await load() }
    }

    func setFuelType(_ newFuelType: String) {
        guard newFuelType != fuelType else { return }
        fuelType = newFuelType
        Task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        do {
            let response = try await repository.getHeatmap(fuelType: fuelType)
            loading = false
            nationalAvg = response.nationalAvgPricePence
            cells = response.cells
            maxAbs = Self.computeMaxAbs(response.cells)
        } catch {
            loading = false
            self.error = "Couldn't load the heat map. Check your connection and try again."
        }
    }

    /// Saturate the scale at the 90th-percentile deviation so a couple of outliers don't wash out
    /// the rest; floor at 3p so a flat market still shows contrast.
    private static func computeMaxAbs(_ cells: [HeatmapCell]) -> Double {
        guard !cells.isEmpty else { return 3.0 }
        let sorted = cells.map { abs($0.deltaPence) }.sorted()
        let p90Index = min(Int(Double(sorted.count) * 0.9), sorted.count - 1)
        let p90 = sorted[p90Index]
        return max(3.0, (p90 * 10).rounded() / 10)
    }
}
