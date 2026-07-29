import Foundation

struct FavouriteDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let stationId: Int
    let fuelType: String
    let notifyOnDrop: Bool
    let priceThresholdPence: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case stationId = "station_id"
        case fuelType = "fuel_type"
        case notifyOnDrop = "notify_on_drop"
        case priceThresholdPence = "price_threshold_pence"
    }
}

struct FavouriteCreateRequest: Encodable, Sendable {
    let stationId: Int
    let fuelType: String
    let notifyOnDrop: Bool
    let priceThresholdPence: Double?

    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case fuelType = "fuel_type"
        case notifyOnDrop = "notify_on_drop"
        case priceThresholdPence = "price_threshold_pence"
    }

    init(stationId: Int, fuelType: String = FuelType.default.rawValue, notifyOnDrop: Bool = true, priceThresholdPence: Double? = nil) {
        self.stationId = stationId
        self.fuelType = fuelType
        self.notifyOnDrop = notifyOnDrop
        self.priceThresholdPence = priceThresholdPence
    }
}

/// Area-radius push alert subscription — a DISTINCT feature/endpoint from `FavouriteDTO`'s
/// per-station `notify_on_drop`. Deliberately has **no** price-threshold field; don't conflate
/// the two shapes.
struct AlertSubscriptionDTO: Decodable, Sendable, Identifiable {
    let id: Int
    let latitude: Double
    let longitude: Double
    let radiusMiles: Double
    let fuelType: String
    let notify: Bool
    let label: String?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude
        case radiusMiles = "radius_miles"
        case fuelType = "fuel_type"
        case notify, label
    }
}

struct AlertCreateRequest: Encodable, Sendable {
    let latitude: Double
    let longitude: Double
    let radiusMiles: Double
    let fuelType: String
    let label: String?

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case radiusMiles = "radius_miles"
        case fuelType = "fuel_type"
        case label
    }

    init(latitude: Double, longitude: Double, radiusMiles: Double = 10.0, fuelType: String = FuelType.default.rawValue, label: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMiles = radiusMiles
        self.fuelType = fuelType
        self.label = label
    }
}

struct DiscrepancyReportRequest: Encodable, Sendable {
    let stationId: Int?
    let fuelType: String?
    let reportedPricePence: Double?
    let expectedPricePence: Double?
    let description: String
    let reporterEmail: String?

    enum CodingKeys: String, CodingKey {
        case stationId = "station_id"
        case fuelType = "fuel_type"
        case reportedPricePence = "reported_price_pence"
        case expectedPricePence = "expected_price_pence"
        case description
        case reporterEmail = "reporter_email"
    }
}
