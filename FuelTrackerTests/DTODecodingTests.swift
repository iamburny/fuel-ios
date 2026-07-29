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
    }

    @Test func fuelTypeRawValuesStayExactCase() {
        #expect(FuelType.b7Standard.rawValue == "B7_STANDARD")
        #expect(FuelType.b7Premium.rawValue == "B7_PREMIUM")
        #expect(FuelType.allCases.map(\.rawValue) == ["E10", "E5", "B7_STANDARD", "B7_PREMIUM", "B10", "HVO"])
    }
}
