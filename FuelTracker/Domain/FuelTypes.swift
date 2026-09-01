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
    /// black = diesel) so the in-app colour coding matches what's printed on the pump. Used for
    /// filled backgrounds (a selected chip's Capsule) where a fixed, contrasting foreground is
    /// drawn on top — for that use, the near-black/dark-slate diesel values are fine in both
    /// light and dark mode, since the fill's own contrast doesn't depend on the surrounding
    /// screen background. Don't use this for text/icon/chart-mark colour drawn directly against
    /// the screen background — use `displayColor` instead.
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

    /// `color`, lightened for the two near-neutral diesel shades when the system is in dark mode
    /// — matches fuel-android's `DarkFuelColors` override in `FuelLabelStyle.kt` exactly (diesel
    /// standard → 0xCBD5E1, diesel premium → 0x94A3B8). `color`'s near-black/dark-slate values
    /// are unreadable as a price/chart-line/icon colour directly on the app's dark background;
    /// the other four hues already have enough contrast in both themes and are left unchanged.
    /// Backed by a dynamic `UIColor` so it resolves correctly wherever it's drawn, with no need
    /// to thread `\.colorScheme` through every call site.
    var displayColor: Color {
        switch self {
        case .b7Standard:
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(red: 0xCB / 255, green: 0xD5 / 255, blue: 0xE1 / 255, alpha: 1)
                : UIColor(red: 0x11 / 255, green: 0x18 / 255, blue: 0x27 / 255, alpha: 1)
            })
        case .b7Premium:
            Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
                ? UIColor(red: 0x94 / 255, green: 0xA3 / 255, blue: 0xB8 / 255, alpha: 1)
                : UIColor(red: 0x4B / 255, green: 0x55 / 255, blue: 0x63 / 255, alpha: 1)
            })
        default:
            color
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

    static func displayColor(forRaw raw: String) -> Color {
        FuelType(rawValue: raw)?.displayColor ?? color(forRaw: raw)
    }

    static func shortLabel(forRaw raw: String) -> String {
        FuelType(rawValue: raw)?.shortLabel ?? raw
    }

    static func longLabel(forRaw raw: String) -> String {
        FuelType(rawValue: raw)?.longLabel ?? raw
    }

    static func label(forRaw raw: String, useLongNames: Bool) -> String {
        useLongNames ? longLabel(forRaw: raw) : shortLabel(forRaw: raw)
    }
}
