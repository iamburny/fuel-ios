import SwiftUI

/// Canonical fuel-type raw values, exact-case, as defined by the backend. Never normalize.
/// Modeled as a `String`-backed enum (not a plain `String`) for compile-time exhaustiveness in
/// `switch`, but with explicit raw values so the case name never implicitly determines the wire
/// value — mirrors `FuelTypes.ALL` in fuel-android's `Models.kt`.
enum FuelType: String, Codable, CaseIterable, Identifiable, Sendable {
    case e10 = "E10"
    case e5 = "E5"
    case b7Standard = "B7_STANDARD"
    case b7Premium = "B7_PREMIUM"
    case b10 = "B10"
    case hvo = "HVO"

    var id: String { rawValue }

    static let `default`: FuelType = .e10

    /// Loosely follows real UK fuel pump nozzle colour conventions (green = unleaded,
    /// black = diesel) so the in-app colour coding matches what's printed on the pump.
    var color: Color {
        switch self {
        case .e10: Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)
        case .e5: Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)
        case .b7Standard: Color(red: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255)
        case .b7Premium: Color(red: 0x4B / 255, green: 0x55 / 255, blue: 0x63 / 255)
        case .b10: Color(red: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255)
        case .hvo: Color(red: 0x14 / 255, green: 0xB8 / 255, blue: 0xA6 / 255)
        }
    }

    var shortLabel: String {
        switch self {
        case .e10: "E10"
        case .e5: "E5"
        case .b7Standard: "Diesel"
        case .b7Premium: "Super Diesel"
        case .b10: "B10"
        case .hvo: "HVO"
        }
    }

    var longLabel: String {
        switch self {
        case .e10: "Unleaded (E10)"
        case .e5: "Super Unleaded (E5)"
        case .b7Standard: "Diesel (B7)"
        case .b7Premium: "Premium Diesel (B7)"
        case .b10: "Biodiesel (B10)"
        case .hvo: "HVO Diesel"
        }
    }

    /// Respects the user's short/long name preference — the iOS equivalent of Android's
    /// `fuelLabel()` helper that reads `LocalUseLongFuelNames`.
    func label(useLongNames: Bool) -> String {
        useLongNames ? longLabel : shortLabel
    }

    /// Fallback color for a raw fuel-type string that doesn't match a known case (forward-compat
    /// with a backend-added 7th fuel type), mirrors `FuelTypes.color()`'s `?: Color(0xFF9CA3AF)`.
    static func color(forRaw raw: String) -> Color {
        FuelType(rawValue: raw)?.color ?? Color(red: 0x9C / 255, green: 0xA3 / 255, blue: 0xAF / 255)
    }

    static func shortLabel(forRaw raw: String) -> String {
        FuelType(rawValue: raw)?.shortLabel ?? raw
    }

    static func longLabel(forRaw raw: String) -> String {
        FuelType(rawValue: raw)?.longLabel ?? raw
    }
}
