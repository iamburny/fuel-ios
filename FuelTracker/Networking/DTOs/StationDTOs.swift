import Foundation

// The backend stores `amenities` as whatever JSON the Gov Fuel Finder ingestion produced —
// sometimes a flat array of enabled amenity keys (["adblue_packaged", "car_wash"]), sometimes an
// object of key -> boolean. It's never guaranteed to match a fixed schema, so this decodes either
// shape rather than assuming one. Mirrors `JsonElement?.toAmenitiesDisplayList()` in Models.kt.
private struct AmenitiesCodingKey: CodingKey {
    let stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

enum AmenitiesValue: Codable, Sendable {
    case array([String])
    case object([String: Bool])
    case none

    init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer(), let array = try? container.decode([String].self) {
            self = .array(array)
            return
        }
        // Decoded key-by-key (not as a single `[String: Bool]`) so a stray non-boolean value only
        // drops that one key, matching Kotlin's per-entry filter
        // (`(v as? JsonPrimitive)?.booleanOrNull == true`) instead of failing the whole object.
        if let keyed = try? decoder.container(keyedBy: AmenitiesCodingKey.self) {
            var result: [String: Bool] = [:]
            for key in keyed.allKeys {
                if let value = try? keyed.decode(Bool.self, forKey: key) {
                    result[key.stringValue] = value
                }
            }
            self = .object(result)
            return
        }
        self = .none
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let keys): try container.encode(keys)
        case .object(let flags): try container.encode(flags)
        case .none: try container.encodeNil()
        }
    }
}

struct DayHoursDTO: Codable, Sendable {
    let open: String?
    let close: String?
    let is24Hours: Bool?

    enum CodingKeys: String, CodingKey {
        case open, close
        case is24Hours = "is_24_hours"
    }
}

struct BankHolidayDTO: Codable, Sendable {
    let type: String?
    let openTime: String?
    let closeTime: String?
    let is24Hours: Bool?

    enum CodingKeys: String, CodingKey {
        case type
        case openTime = "open_time"
        case closeTime = "close_time"
        case is24Hours = "is_24_hours"
    }
}

struct UsualDaysDTO: Codable, Sendable {
    let monday: DayHoursDTO?
    let tuesday: DayHoursDTO?
    let wednesday: DayHoursDTO?
    let thursday: DayHoursDTO?
    let friday: DayHoursDTO?
    let saturday: DayHoursDTO?
    let sunday: DayHoursDTO?

    /// Ordered Monday-first, mirrors `UsualDaysDto.asList()`.
    var asList: [(day: String, hours: DayHoursDTO?)] {
        [
            ("Monday", monday), ("Tuesday", tuesday), ("Wednesday", wednesday),
            ("Thursday", thursday), ("Friday", friday),
            ("Saturday", saturday), ("Sunday", sunday),
        ]
    }
}

struct OpeningHoursDTO: Codable, Sendable {
    let usualDays: UsualDaysDTO?
    let bankHolidays: [BankHolidayDTO]?

    enum CodingKeys: String, CodingKey {
        case usualDays = "usual_days"
        case bankHolidays = "bank_holidays"
    }
}

struct PriceDTO: Decodable, Sendable, Hashable {
    let fuelType: String
    let pricePence: Double
    let reportedAt: String

    enum CodingKeys: String, CodingKey {
        case fuelType = "fuel_type"
        case pricePence = "price_pence"
        case reportedAt = "reported_at"
    }
}

struct StationDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let govId: String
    let name: String
    let brand: String?
    let operatorName: String?
    let phone: String?
    let addressLine1: String?
    let addressLine2: String?
    let town: String?
    let county: String?
    let postcode: String?
    let latitude: Double
    let longitude: Double
    let temporaryClosure: Bool
    let isMotorway: Bool
    let isSupermarket: Bool
    let amenities: AmenitiesValue?
    let openingHours: OpeningHoursDTO?
    /// `GET /api/stations/{id}` never populates this — distance is always computed client-side
    /// via `haversineMiles` against the current location. Only nearby/bounds/search/cheapest
    /// responses set it.
    let distanceMiles: Double?
    let prices: [PriceDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case govId = "gov_id"
        case name, brand
        case operatorName = "operator"
        case phone
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case town, county, postcode, latitude, longitude
        case temporaryClosure = "temporary_closure"
        case isMotorway = "is_motorway"
        case isSupermarket = "is_supermarket"
        case amenities
        case openingHours = "opening_hours"
        case distanceMiles = "distance_miles"
        case prices
    }

    /// Explicit memberwise init — needed because `init(from:)` below suppresses the synthesized
    /// one. Used by `CachedStation.toDTO` to reconstruct a `StationDTO` from cached fields.
    init(
        id: Int, govId: String, name: String, brand: String?, operatorName: String?, phone: String?,
        addressLine1: String?, addressLine2: String?, town: String?, county: String?, postcode: String?,
        latitude: Double, longitude: Double, temporaryClosure: Bool, isMotorway: Bool, isSupermarket: Bool,
        amenities: AmenitiesValue?, openingHours: OpeningHoursDTO?, distanceMiles: Double?, prices: [PriceDTO]
    ) {
        self.id = id
        self.govId = govId
        self.name = name
        self.brand = brand
        self.operatorName = operatorName
        self.phone = phone
        self.addressLine1 = addressLine1
        self.addressLine2 = addressLine2
        self.town = town
        self.county = county
        self.postcode = postcode
        self.latitude = latitude
        self.longitude = longitude
        self.temporaryClosure = temporaryClosure
        self.isMotorway = isMotorway
        self.isSupermarket = isSupermarket
        self.amenities = amenities
        self.openingHours = openingHours
        self.distanceMiles = distanceMiles
        self.prices = prices
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        govId = try c.decode(String.self, forKey: .govId)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        operatorName = try c.decodeIfPresent(String.self, forKey: .operatorName)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        addressLine1 = try c.decodeIfPresent(String.self, forKey: .addressLine1)
        addressLine2 = try c.decodeIfPresent(String.self, forKey: .addressLine2)
        town = try c.decodeIfPresent(String.self, forKey: .town)
        county = try c.decodeIfPresent(String.self, forKey: .county)
        postcode = try c.decodeIfPresent(String.self, forKey: .postcode)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        temporaryClosure = try c.decodeIfPresent(Bool.self, forKey: .temporaryClosure) ?? false
        isMotorway = try c.decodeIfPresent(Bool.self, forKey: .isMotorway) ?? false
        isSupermarket = try c.decodeIfPresent(Bool.self, forKey: .isSupermarket) ?? false
        amenities = try c.decodeIfPresent(AmenitiesValue.self, forKey: .amenities)
        openingHours = try c.decodeIfPresent(OpeningHoursDTO.self, forKey: .openingHours)
        distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles)
        prices = try c.decodeIfPresent([PriceDTO].self, forKey: .prices) ?? []
    }
}

// MARK: - Response wrappers

struct StationListResponse: Decodable, Sendable {
    let count: Int
    let stations: [StationDTO]
}

struct CheapestEntry: Decodable, Sendable {
    let station: StationDTO
    let pricePence: Double
    let distanceMiles: Double?

    enum CodingKeys: String, CodingKey {
        case station
        case pricePence = "price_pence"
        case distanceMiles = "distance_miles"
    }
}

struct CheapestResponse: Decodable, Sendable {
    let results: [CheapestEntry]
    let discrepancyReportUrl: String
    let dataNotice: String

    enum CodingKeys: String, CodingKey {
        case results
        case discrepancyReportUrl = "discrepancy_report_url"
        case dataNotice = "data_notice"
    }
}

struct NationalAverageDTO: Decodable, Sendable {
    let fuelType: String
    let avgPricePence: Double
    let minPricePence: Double
    let maxPricePence: Double
    let stationCount: Int
    let asOf: String

    enum CodingKeys: String, CodingKey {
        case fuelType = "fuel_type"
        case avgPricePence = "avg_price_pence"
        case minPricePence = "min_price_pence"
        case maxPricePence = "max_price_pence"
        case stationCount = "station_count"
        case asOf = "as_of"
    }
}

struct AveragesResponse: Decodable, Sendable {
    let averages: [NationalAverageDTO]
    let discrepancyReportUrl: String
    let dataNotice: String

    enum CodingKeys: String, CodingKey {
        case averages
        case discrepancyReportUrl = "discrepancy_report_url"
        case dataNotice = "data_notice"
    }
}

struct TrendPoint: Decodable, Sendable {
    let date: String
    let avgPricePence: Double
    let minPricePence: Double
    let maxPricePence: Double
    let observations: Int

    enum CodingKeys: String, CodingKey {
        case date
        case avgPricePence = "avg_price_pence"
        case minPricePence = "min_price_pence"
        case maxPricePence = "max_price_pence"
        case observations
    }
}

struct TrendsResponse: Decodable, Sendable {
    let trend: [TrendPoint]
    let discrepancyReportUrl: String
    let dataNotice: String

    enum CodingKeys: String, CodingKey {
        case trend
        case discrepancyReportUrl = "discrepancy_report_url"
        case dataNotice = "data_notice"
    }
}

struct HeatmapCell: Decodable, Sendable, Identifiable {
    let latitude: Double
    let longitude: Double
    let avgPricePence: Double
    let deltaPence: Double
    let deltaPercent: Double
    let stationCount: Int

    var id: String { "\(latitude),\(longitude)" }

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case avgPricePence = "avg_price_pence"
        case deltaPence = "delta_pence"
        case deltaPercent = "delta_percent"
        case stationCount = "station_count"
    }
}

struct HeatmapResponse: Decodable, Sendable {
    let fuelType: String
    let nationalAvgPricePence: Double
    let cellSizeDegrees: Double
    let cells: [HeatmapCell]
    let discrepancyReportUrl: String
    let dataNotice: String

    enum CodingKeys: String, CodingKey {
        case fuelType = "fuel_type"
        case nationalAvgPricePence = "national_avg_price_pence"
        case cellSizeDegrees = "cell_size_degrees"
        case cells
        case discrepancyReportUrl = "discrepancy_report_url"
        case dataNotice = "data_notice"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fuelType = try c.decode(String.self, forKey: .fuelType)
        nationalAvgPricePence = try c.decode(Double.self, forKey: .nationalAvgPricePence)
        cellSizeDegrees = try c.decodeIfPresent(Double.self, forKey: .cellSizeDegrees) ?? 0.4
        cells = try c.decode([HeatmapCell].self, forKey: .cells)
        discrepancyReportUrl = try c.decodeIfPresent(String.self, forKey: .discrepancyReportUrl) ?? ""
        dataNotice = try c.decodeIfPresent(String.self, forKey: .dataNotice) ?? ""
    }
}

struct PriceHistoryPoint: Decodable, Sendable {
    let pricePence: Double
    let reportedAt: String

    enum CodingKeys: String, CodingKey {
        case pricePence = "price_pence"
        case reportedAt = "reported_at"
    }
}

struct PriceHistoryResponse: Decodable, Sendable {
    let stationId: Int
    let stationName: String
    let fuelType: String
    let history: [PriceHistoryPoint]

    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case stationName = "station_name"
        case fuelType = "fuel_type"
        case history
    }
}

extension StationDTO {
    /// The cheapest reported price for `fuelType` at this station, if any.
    func cheapestPrice(for fuelType: String) -> PriceDTO? {
        prices.filter { $0.fuelType == fuelType }.min { $0.pricePence < $1.pricePence }
    }
}
