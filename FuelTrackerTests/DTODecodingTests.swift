import Testing
import Foundation
@testable import FuelTracker

struct DTODecodingTests {
    @Test func decodesStationWithArrayAmenities() throws {
        let json = """
        {
          "id": 431, "gov_id": "abc123", "name": "SuperFuel Loughborough", "brand": "SuperFuel",
          "latitude": 52.77, "longitude": -1.21, "temporary_closure": false,
          "is_motorway": false, "is_supermarket": true,
          "amenities": ["adblue_packaged", "car_wash"],
          "prices": [{"fuel_type": "B7_STANDARD", "price_pence": 139.9, "reported_at": "2026-01-01T08:00:00Z"}]
        }
        """.data(using: .utf8)!

        let station = try JSONDecoder().decode(StationDTO.self, from: json)
        #expect(station.id == 431)
        #expect(station.brand == "SuperFuel")
        #expect(station.prices.first?.fuelType == "B7_STANDARD")
        #expect(AmenitiesFormatter.displayList(for: station.amenities).contains("AdBlue Packaged"))
        #expect(FuelType(rawValue: station.prices.first!.fuelType) == .b7Standard)
    }

    @Test func decodesStationWithObjectAmenities() throws {
        let json = """
        {
          "id": 1, "gov_id": "x", "name": "Test", "latitude": 0, "longitude": 0,
          "amenities": {"car_wash": true, "lpg_pumps": false},
          "prices": []
        }
        """.data(using: .utf8)!

        let station = try JSONDecoder().decode(StationDTO.self, from: json)
        let display = AmenitiesFormatter.displayList(for: station.amenities)
        #expect(display.contains("Car Wash"))
        #expect(!display.contains("LPG"))
    }

    @Test func amenitiesObjectDecodeSkipsOnlyBadKeysNotWholeObject() throws {
        // A stray non-boolean value for one amenity key must not blank out the others — the
        // backend's amenities JSON has no fixed schema, so this needs to degrade per-key.
        let json = """
        {
          "id": 1, "gov_id": "x", "name": "Test", "latitude": 0, "longitude": 0,
          "amenities": {"car_wash": true, "lpg_pumps": "unexpected_string_value", "customer_toilets": false},
          "prices": []
        }
        """.data(using: .utf8)!

        let station = try JSONDecoder().decode(StationDTO.self, from: json)
        let display = AmenitiesFormatter.displayList(for: station.amenities)
        #expect(display.contains("Car Wash"))
        #expect(!display.contains("Toilets"))
        #expect(display.count == 1)
    }

    @Test func decodesTokenResponseWithRole() throws {
        let json = """
        {"access_token": "abc.def.ghi", "token_type": "bearer", "role": "user"}
        """.data(using: .utf8)!
        let token = try JSONDecoder().decode(TokenResponse.self, from: json)
        #expect(token.accessToken == "abc.def.ghi")
        #expect(token.role == "user")
        #expect(token.refreshToken == nil)
    }

    @Test func decodesTokenResponseWithRefreshToken() throws {
        let json = """
        {"access_token": "abc.def.ghi", "refresh_token": "opaque-refresh-value", "token_type": "bearer", "role": "user"}
        """.data(using: .utf8)!
        let token = try JSONDecoder().decode(TokenResponse.self, from: json)
        #expect(token.accessToken == "abc.def.ghi")
        #expect(token.refreshToken == "opaque-refresh-value")
    }

    @Test func decodesFavouriteDTOWithNotifyOnDrop() throws {
        let json = """
        {"id": 5, "station_id": 501, "fuel_type": "HVO", "notify_on_drop": false, "price_threshold_pence": 129.9}
        """.data(using: .utf8)!
        let favourite = try JSONDecoder().decode(FavouriteDTO.self, from: json)
        #expect(favourite.id == 5)
        #expect(favourite.stationId == 501)
        #expect(favourite.fuelType == "HVO")
        #expect(favourite.notifyOnDrop == false)
        #expect(favourite.priceThresholdPence == 129.9)
    }

    @Test func encodesFavouriteUpdateRequest() throws {
        let data = try FavouriteUpdateRequest(notifyOnDrop: false).asJSONData()
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["notify_on_drop"] as? Bool == false)
    }

    @Test func encodesFavouriteFuelTypeUpdateRequest() throws {
        let data = try FavouriteFuelTypeUpdateRequest(fuelType: "HVO").asJSONData()
        let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(decoded?["fuel_type"] as? String == "HVO")
    }

    @Test func fuelTypeRawValuesStayExactCase() {
        #expect(FuelType.b7Standard.rawValue == "B7_STANDARD")
        #expect(FuelType.b7Premium.rawValue == "B7_PREMIUM")
        #expect(FuelType.allCases.map(\.rawValue) == ["E10", "E5", "B7_STANDARD", "B7_PREMIUM", "B10", "HVO"])
    }
}

struct PriceWarningTests {
    private func decodePrice(warningField: String) throws -> PriceDTO {
        let json = """
        {"fuel_type": "E10", "price_pence": 299.9, "reported_at": "2026-01-01T08:00:00Z"\(warningField)}
        """.data(using: .utf8)!
        return try JSONDecoder().decode(PriceDTO.self, from: json)
    }

    @Test func absentWarningDecodesAsNil() throws {
        let price = try decodePrice(warningField: "")
        #expect(price.warning == nil)
        #expect(price.pricePence == 299.9)
    }

    @Test func nullWarningDecodesAsNil() throws {
        #expect(try decodePrice(warningField: #", "warning": null"#).warning == nil)
    }

    @Test func knownWarningsDecode() throws {
        #expect(try decodePrice(warningField: #", "warning": "stale""#).warning == .stale)
        #expect(try decodePrice(warningField: #", "warning": "unusually_low""#).warning == .unusuallyLow)
        #expect(try decodePrice(warningField: #", "warning": "unusually_high""#).warning == .unusuallyHigh)
    }

    @Test func unknownOrMalformedWarningDecodesAsNilWithoutFailing() throws {
        #expect(try decodePrice(warningField: #", "warning": "some_future_value""#).warning == nil)
        #expect(try decodePrice(warningField: #", "warning": 3"#).warning == nil)
    }

    @Test func unknownWarningDoesNotFailStationDecode() throws {
        let json = """
        {
          "id": 1, "gov_id": "x", "name": "Test", "latitude": 0, "longitude": 0,
          "prices": [
            {"fuel_type": "E10", "price_pence": 139.9, "reported_at": "2026-01-01T08:00:00Z", "warning": "brand_new"},
            {"fuel_type": "E5", "price_pence": 149.9, "reported_at": "2026-01-01T08:00:00Z", "warning": "stale"}
          ]
        }
        """.data(using: .utf8)!
        let station = try JSONDecoder().decode(StationDTO.self, from: json)
        #expect(station.prices.count == 2)
        #expect(station.prices[0].warning == nil)
        #expect(station.prices[1].warning == .stale)
    }

    private func station(prices: [PriceDTO], distanceMiles: Double? = nil) -> StationDTO {
        StationDTO(
            id: 1, govId: "abc", name: "Test", brand: nil, operatorName: nil, phone: nil,
            addressLine1: nil, addressLine2: nil, town: nil, county: nil, postcode: nil,
            latitude: 51.5, longitude: -0.1, temporaryClosure: false, isMotorway: false, isSupermarket: false,
            amenities: nil, openingHours: nil, distanceMiles: distanceMiles, prices: prices
        )
    }

    @Test func cheapestPriceSkipsFlaggedPriceWhenAnUnflaggedOneExists() {
        let s = station(prices: [
            PriceDTO(fuelType: "E10", pricePence: 50.0, reportedAt: "t", warning: .unusuallyLow),
            PriceDTO(fuelType: "E10", pricePence: 139.9, reportedAt: "t"),
            PriceDTO(fuelType: "E10", pricePence: 99.9, reportedAt: "t", warning: .stale),
        ])
        #expect(s.cheapestPrice(for: "E10")?.pricePence == 139.9)
    }

    @Test func cheapestPriceFallsBackToFlaggedWhenThatIsAllThereIs() {
        let s = station(prices: [
            PriceDTO(fuelType: "E10", pricePence: 299.9, reportedAt: "t", warning: .unusuallyHigh),
            PriceDTO(fuelType: "E10", pricePence: 199.9, reportedAt: "t", warning: .stale),
            PriceDTO(fuelType: "E5", pricePence: 149.9, reportedAt: "t"),
        ])
        #expect(s.cheapestPrice(for: "E10")?.pricePence == 199.9)
        #expect(s.cheapestPrice(for: "E10")?.warning == .stale)
    }

    @Test func headlineSortKeyOrdersFlaggedPricesLast() {
        let flaggedCheap = PriceDTO(fuelType: "E10", pricePence: 50.0, reportedAt: "t", warning: .unusuallyLow)
        let normal = PriceDTO(fuelType: "E10", pricePence: 139.9, reportedAt: "t")
        #expect(normal.headlineSortKey < flaggedCheap.headlineSortKey)
    }

    @Test func netSavingsIgnoresFlaggedPrice() {
        let s = station(
            prices: [PriceDTO(fuelType: "E10", pricePence: 50, reportedAt: "t", warning: .unusuallyLow)],
            distanceMiles: 1
        )
        let averages = [NationalAverageDTO(fuelType: "E10", avgPricePence: 140, minPricePence: 120, maxPricePence: 150, stationCount: 100, asOf: "2026-01-01")]
        let prefs = UserPreferences(fuelType: "E10", mpg: 60, tankCapacityLitres: 50)
        #expect(FuelCostCalculator.estimateNetSavingsPounds(station: s, averages: averages, preferences: prefs) == nil)
    }
}
