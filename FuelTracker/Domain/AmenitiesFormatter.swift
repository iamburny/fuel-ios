import Foundation

/// Direct port of `Models.kt`'s `AMENITY_LABELS` map + `prettifyAmenityKey`/`toAmenitiesDisplayList`.
enum AmenitiesFormatter {
    private static let labels: [String: String] = [
        "adblue_pumps": "AdBlue Pumps",
        "adblue_packaged": "AdBlue Packaged",
        "lpg_pumps": "LPG",
        "car_wash": "Car Wash",
        "air_pump_or_screenwash": "Air / Screenwash",
        "water_filling": "Water",
        "twenty_four_hour_fuel": "24-Hour Fuel",
        "customer_toilets": "Toilets",
    ]

    private static func prettify(_ key: String) -> String {
        if let label = labels[key] { return label }
        return key.replacingOccurrences(of: "_", with: " ").prefix(1).uppercased() + key.replacingOccurrences(of: "_", with: " ").dropFirst()
    }

    static func displayList(for amenities: AmenitiesValue?) -> [String] {
        switch amenities ?? .none {
        case .array(let keys):
            keys.map(prettify)
        case .object(let flags):
            flags.filter(\.value).keys.map(prettify)
        case .none:
            []
        }
    }
}
