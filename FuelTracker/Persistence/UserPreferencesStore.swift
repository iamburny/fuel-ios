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
    var appOpenCount: Int = 0
    var coffeePromptPausedUntilOpen: Int = 0
    var dismissedAnnouncementMessage: String?

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
        static let appOpenCount = "app_open_count"
        static let coffeePromptPausedUntil = "coffee_prompt_paused_until"
        static let dismissedAnnouncement = "dismissed_announcement_message"
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

    /// Increment the cold-launch counter and return the new value.
    @discardableResult
    func incrementAppOpenCount() -> Int {
        let newCount = defaults.integer(forKey: Keys.appOpenCount) + 1
        defaults.set(newCount, forKey: Keys.appOpenCount)
        reload()
        return newCount
    }

    /// Suppress the support prompt until the app-open count reaches `untilOpen`.
    func pauseCoffeePrompt(untilOpen: Int) {
        defaults.set(untilOpen, forKey: Keys.coffeePromptPausedUntil)
        reload()
    }

    /// Records `message` as dismissed — the announcement banner stays hidden until the flag's
    /// variant text changes to something else.
    func dismissAnnouncement(_ message: String) {
        defaults.set(message, forKey: Keys.dismissedAnnouncement)
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
            appOpenCount: defaults.integer(forKey: Keys.appOpenCount),
            coffeePromptPausedUntilOpen: defaults.integer(forKey: Keys.coffeePromptPausedUntil),
            dismissedAnnouncementMessage: defaults.string(forKey: Keys.dismissedAnnouncement)
        )
    }
}
