import Foundation
import Observation
import SwiftUI

enum ThemeMode: String, CaseIterable, Sendable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"

    /// Maps to SwiftUI's `.preferredColorScheme(_:)` — `nil` means "follow the system", matching
    /// Android's `MainActivity.kt` mapping `LIGHT`/`DARK`/else->`isSystemInDarkTheme()`.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Snapshot of all non-secret user prefs — the iOS equivalent of Android's `UserPreferences` data
/// class (`UserPreferencesStore.kt`). Mirrors its field set exactly.
struct UserPreferences: Sendable, Equatable {
    var fuelType: String = FuelType.default.rawValue
    var mpg: Double?
    var tankCapacityLitres: Double?
    var useLongFuelNames: Bool = false
    var themeMode: ThemeMode = .system
    var dismissedAnnouncementMessage: String?
    var dismissedReleaseNoticeKey: String?

    /// True once there's enough info to estimate a driving cost (see `FuelCostCalculator`).
    var canEstimateDriveCost: Bool { mpg != nil && tankCapacityLitres != nil }
}

/// UserDefaults-backed preferences — the non-secret iOS equivalent of Android's DataStore-backed
/// `UserPreferencesStore`. `save()` only touches the user-editable settings, matching Android's
/// note that the launch counters are written by their own dedicated methods so a `save()` call
/// never clobbers them.
@Observable
@MainActor
final class UserPreferencesStore {
    private enum Keys {
        static let fuelType = "fuel_type"
        static let mpg = "mpg"
        static let tankCapacityLitres = "tank_capacity_litres"
        static let useLongFuelNames = "use_long_fuel_names"
        static let themeMode = "theme_mode"
        static let dismissedAnnouncement = "dismissed_announcement_message"
        static let dismissedReleaseNotice = "dismissed_release_notice_key"
    }

    private let defaults: UserDefaults
    private(set) var preferences: UserPreferences

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = UserPreferences()
        reload()
    }

    func save(fuelType: String, mpg: Double?, tankCapacityLitres: Double?, useLongFuelNames: Bool, themeMode: ThemeMode) {
        defaults.set(fuelType, forKey: Keys.fuelType)
        setOptionalDouble(mpg, forKey: Keys.mpg)
        setOptionalDouble(tankCapacityLitres, forKey: Keys.tankCapacityLitres)
        defaults.set(useLongFuelNames, forKey: Keys.useLongFuelNames)
        defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        reload()
    }

    /// Records `message` as dismissed — the announcement banner stays hidden until the flag's
    /// variant text changes to something else.
    func dismissAnnouncement(_ message: String) {
        defaults.set(message, forKey: Keys.dismissedAnnouncement)
        reload()
    }

    /// Records `key` (a `ReleaseNoticeContent.id`) as dismissed — the release notice stays hidden
    /// until the flag's variant content changes to something else.
    func dismissReleaseNotice(_ key: String) {
        defaults.set(key, forKey: Keys.dismissedReleaseNotice)
        reload()
    }

    private func setOptionalDouble(_ value: Double?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private func optionalDouble(forKey key: String) -> Double? {
        defaults.object(forKey: key) as? Double
    }

    private func reload() {
        preferences = UserPreferences(
            fuelType: defaults.string(forKey: Keys.fuelType) ?? FuelType.default.rawValue,
            mpg: optionalDouble(forKey: Keys.mpg),
            tankCapacityLitres: optionalDouble(forKey: Keys.tankCapacityLitres),
            useLongFuelNames: defaults.bool(forKey: Keys.useLongFuelNames),
            themeMode: ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system,
            dismissedAnnouncementMessage: defaults.string(forKey: Keys.dismissedAnnouncement),
            dismissedReleaseNoticeKey: defaults.string(forKey: Keys.dismissedReleaseNotice)
        )
    }
}
