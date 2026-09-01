import Foundation

/// The account's stored preferences (`GET`/`PUT /api/auth/preferences`). Every field is optional —
/// `nil` means the account has never set that field, distinct from an explicit value, so the
/// client-side sync can tell "adopt this device's local value" apart from "the account wants this
/// cleared" (the backend never clears a field the client omits from a `PUT` body either).
struct PreferencesDTO: Codable, Sendable {
    var fuelType: String?
    var mpg: Double?
    var tankCapacityLitres: Double?
    var useLongFuelNames: Bool?
    var themeMode: String?

    enum CodingKeys: String, CodingKey {
        case fuelType = "fuel_type"
        case mpg
        case tankCapacityLitres = "tank_capacity_litres"
        case useLongFuelNames = "use_long_fuel_names"
        case themeMode = "theme_mode"
    }
}
