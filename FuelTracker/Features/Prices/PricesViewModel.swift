import Foundation
import Observation

/// Direct port of fuel-android's `PricesViewModel.kt`.
@Observable
@MainActor
final class PricesViewModel {
    var isLoading = true
    var averages: [NationalAverageDTO] = []
    var trend: [TrendPoint] = []
    var selectedFuelType = FuelType.default.rawValue
    var selectedDays = 30
    var discrepancyReportUrl = ""
    var dataNotice = ""
    var error: String?

    private let repository: FuelRepository

    init(repository: FuelRepository) {
        self.repository = repository
        Task { await loadAll() }
    }

    func loadAll() async {
        isLoading = true
        error = nil
        do {
            let avg = try await repository.getNationalAverages()
            let trendResponse = try await repository.getNationalTrends(fuelType: selectedFuelType, days: selectedDays)
            isLoading = false
            averages = avg.averages
            trend = trendResponse.trend
            discrepancyReportUrl = avg.discrepancyReportUrl
            dataNotice = avg.dataNotice
        } catch {
            isLoading = false
            self.error = error.localizedDescription
        }
    }

    func setFuelType(_ type: String) {
        selectedFuelType = type
        Task { await loadTrend() }
    }

    func setDays(_ days: Int) {
        selectedDays = days
        Task { await loadTrend() }
    }

    private func loadTrend() async {
        do {
            let trendResponse = try await repository.getNationalTrends(fuelType: selectedFuelType, days: selectedDays)
            trend = trendResponse.trend
        } catch {
            // Best-effort, matches Android's empty catch block.
        }
    }
}
