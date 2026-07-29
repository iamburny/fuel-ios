import Foundation
import SwiftData

/// Offline station cache — the SwiftData equivalent of Room's `StationEntity`. Complex nested
/// fields (amenities, opening hours) are stored as raw encoded JSON `Data` and decoded back on
/// read, mirroring the Room entity's `amenitiesJson`/`openingHoursJson` string columns; SwiftData
/// relationship/array support for irregular JSON shapes isn't worth the friction here.
@Model
final class CachedStation {
    @Attribute(.unique) var id: Int
    var govId: String
    var name: String
    var brand: String?
    var operatorName: String?
    var phone: String?
    var addressLine1: String?
    var addressLine2: String?
    var town: String?
    var county: String?
    var postcode: String?
    var latitude: Double
    var longitude: Double
    var temporaryClosure: Bool
    var isMotorway: Bool
    var isSupermarket: Bool
    var amenitiesJSON: Data?
    var openingHoursJSON: Data?
    var lastFetchedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \CachedFuelPrice.station)
    var prices: [CachedFuelPrice] = []

    init(
        id: Int, govId: String, name: String, brand: String?, operatorName: String?, phone: String?,
        addressLine1: String?, addressLine2: String?, town: String?, county: String?, postcode: String?,
        latitude: Double, longitude: Double, temporaryClosure: Bool, isMotorway: Bool, isSupermarket: Bool,
        amenitiesJSON: Data?, openingHoursJSON: Data?, lastFetchedAt: Date
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
        self.amenitiesJSON = amenitiesJSON
        self.openingHoursJSON = openingHoursJSON
        self.lastFetchedAt = lastFetchedAt
    }
}

@Model
final class CachedFuelPrice {
    var fuelType: String
    var pricePence: Double
    var reportedAt: String
    var station: CachedStation?

    init(fuelType: String, pricePence: Double, reportedAt: String, station: CachedStation? = nil) {
        self.fuelType = fuelType
        self.pricePence = pricePence
        self.reportedAt = reportedAt
        self.station = station
    }
}

extension CachedStation {
    /// `originLat`/`originLng` recompute `distanceMiles` client-side — it's relative to the query
    /// point, not an intrinsic station property, so it isn't stored on the entity. Pass `nil` when
    /// there's no meaningful origin (a lookup by id or a text search).
    func toDTO(originLat: Double?, originLng: Double?) -> StationDTO {
        let decoder = JSONDecoder()
        let amenities = amenitiesJSON.flatMap { try? decoder.decode(AmenitiesValue.self, from: $0) }
        let openingHours = openingHoursJSON.flatMap { try? decoder.decode(OpeningHoursDTO.self, from: $0) }
        let distance: Double? = if let originLat, let originLng {
            FuelCostCalculator.haversineMiles(lat1: originLat, lng1: originLng, lat2: latitude, lng2: longitude)
        } else {
            nil
        }
        return StationDTO(
            id: id, govId: govId, name: name, brand: brand, operatorName: operatorName, phone: phone,
            addressLine1: addressLine1, addressLine2: addressLine2, town: town, county: county, postcode: postcode,
            latitude: latitude, longitude: longitude, temporaryClosure: temporaryClosure,
            isMotorway: isMotorway, isSupermarket: isSupermarket, amenities: amenities, openingHours: openingHours,
            distanceMiles: distance,
            prices: prices.map { PriceDTO(fuelType: $0.fuelType, pricePence: $0.pricePence, reportedAt: $0.reportedAt) }
        )
    }
}
