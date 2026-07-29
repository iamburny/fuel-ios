import Testing
@testable import FuelTracker

struct FuelCostCalculatorTests {
    @Test func haversineZeroDistanceForSamePoint() {
        let distance = FuelCostCalculator.haversineMiles(lat1: 51.5, lng1: -0.1, lat2: 51.5, lng2: -0.1)
        #expect(distance == 0)
    }

    @Test func haversineKnownDistanceLondonToManchester() {
        // London (51.5074, -0.1278) to Manchester (53.4808, -2.2426) is ~163 miles.
        let distance = FuelCostCalculator.haversineMiles(lat1: 51.5074, lng1: -0.1278, lat2: 53.4808, lng2: -2.2426)
        #expect(distance > 155 && distance < 175)
    }

    @Test func driveCostScalesWithDistanceAndPrice() {
        // 10 miles at 40mpg with fuel at 140p/litre.
        let cost = FuelCostCalculator.estimateDriveCostPounds(distanceMiles: 10, mpg: 40, pricePence: 140)
        let expectedCostPerMile = (140.0 / 100.0 * 4.546) / 40.0
        #expect(abs(cost - expectedCostPerMile * 10) < 0.0001)
    }

    @Test func netSavingsReturnsNilWithoutMPG() {
        let station = StationDTO(
            id: 1, govId: "abc", name: "Test", brand: nil, operatorName: nil, phone: nil,
            addressLine1: nil, addressLine2: nil, town: nil, county: nil, postcode: nil,
            latitude: 51.5, longitude: -0.1, temporaryClosure: false, isMotorway: false, isSupermarket: false,
            amenities: nil, openingHours: nil, distanceMiles: 5,
            prices: [PriceDTO(fuelType: "E10", pricePence: 130, reportedAt: "2026-01-01T00:00:00Z")]
        )
        let averages = [NationalAverageDTO(fuelType: "E10", avgPricePence: 140, minPricePence: 120, maxPricePence: 150, stationCount: 100, asOf: "2026-01-01")]
        let prefs = UserPreferences(fuelType: "E10", mpg: nil, tankCapacityLitres: 50)
        #expect(FuelCostCalculator.estimateNetSavingsPounds(station: station, averages: averages, preferences: prefs) == nil)
    }

    @Test func netSavingsPositiveWhenStationIsCheaperThanAverage() {
        let station = StationDTO(
            id: 1, govId: "abc", name: "Test", brand: nil, operatorName: nil, phone: nil,
            addressLine1: nil, addressLine2: nil, town: nil, county: nil, postcode: nil,
            latitude: 51.5, longitude: -0.1, temporaryClosure: false, isMotorway: false, isSupermarket: false,
            amenities: nil, openingHours: nil, distanceMiles: 1,
            prices: [PriceDTO(fuelType: "E10", pricePence: 100, reportedAt: "2026-01-01T00:00:00Z")]
        )
        let averages = [NationalAverageDTO(fuelType: "E10", avgPricePence: 200, minPricePence: 90, maxPricePence: 210, stationCount: 100, asOf: "2026-01-01")]
        let prefs = UserPreferences(fuelType: "E10", mpg: 60, tankCapacityLitres: 50)
        let savings = FuelCostCalculator.estimateNetSavingsPounds(station: station, averages: averages, preferences: prefs)
        #expect(savings != nil && savings! > 0)
    }
}
