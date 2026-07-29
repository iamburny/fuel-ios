import Foundation

/// Pure fuel-cost math — direct port of fuel-android's `FuelCostCalculator.kt`.
enum FuelCostCalculator {
    private static let litresPerUKGallon = 4.546
    private static let earthRadiusMiles = 3958.8

    /// Haversine distance in miles between two lat/lng points.
    static func haversineMiles(lat1: Double, lng1: Double, lat2: Double, lng2: Double) -> Double {
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = pow(sin(dLat / 2), 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * pow(sin(dLng / 2), 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusMiles * c
    }

    /// Estimated one-way fuel cost (£) to drive `distanceMiles` at `mpg`, using `pricePence`
    /// (pence per litre) as the cost basis.
    static func estimateDriveCostPounds(distanceMiles: Double, mpg: Double, pricePence: Double) -> Double {
        let costPerMilePounds = (pricePence / 100.0 * litresPerUKGallon) / mpg
        return costPerMilePounds * distanceMiles
    }

    /// Net value (£) of filling half a tank at `station` at its price for the preferred fuel
    /// type, versus the national average price, minus the estimated round-trip fuel cost of
    /// driving there (using the national average price as the cost basis for the fuel already in
    /// the tank). Positive means the detour is worth it; negative means it costs more than it
    /// saves. Returns `nil` if preferences don't have enough info yet, or the station has no
    /// distance or no price for the preferred fuel type.
    ///
    /// Not consumed by the phone UI (car-app-only sort in Android) but ported anyway — small,
    /// self-contained, and a natural fit if a future screen needs it.
    static func estimateNetSavingsPounds(
        station: StationDTO,
        averages: [NationalAverageDTO],
        preferences: UserPreferences
    ) -> Double? {
        guard let mpg = preferences.mpg,
              let tankCapacityLitres = preferences.tankCapacityLitres,
              let distanceMiles = station.distanceMiles,
              let stationPricePence = station.prices.first(where: { $0.fuelType == preferences.fuelType })?.pricePence,
              let avgPricePence = averages.first(where: { $0.fuelType == preferences.fuelType })?.avgPricePence
        else { return nil }

        let litresToFill = tankCapacityLitres / 2
        let grossSavingsPounds = (avgPricePence - stationPricePence) / 100.0 * litresToFill
        let roundTripCostPounds = estimateDriveCostPounds(distanceMiles: distanceMiles, mpg: mpg, pricePence: avgPricePence) * 2

        return grossSavingsPounds - roundTripCostPounds
    }
}
