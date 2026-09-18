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
    var useLongFuelNames: Bool = true
    var themeMode: ThemeMode = .system
    var dismissedAnnouncementMessage: String?
    var dismissedReleaseNoticeKey: String?
    var hasSeenCheapestToggleTip: Bool = false
    var hasSeenFuelTypePillTip: Bool = false

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
        static let hasSeenCheapestToggleTip = "has_seen_cheapest_toggle_tip"
        static let hasSeenFuelTypePillTip = "has_seen_fuel_type_pill_tip"
    }

    private let defaults: UserDefaults
    private(set) var preferences: UserPreferences

    /// The most recently active fuel-type filter from a browsing screen (Nearby's pill), if any
    /// — deliberately session-only, never written to `UserDefaults`/`reload()`d from it, unlike
    /// everything else in this class. Lets a favourite created from Detail after navigating from
    /// Nearby with a non-default filter active inherit that filter instead of `preferences.fuelType`
    /// ("usual fuel") — which stays reserved for exactly one job, seeding the very first pin state
    /// on a fresh launch. `nil` until the first pill interaction of this app session, and reset to
    /// `nil` again on the next cold launch, matching that "usual fuel is only the fresh-open default"
    /// rule exactly.
    var lastActiveFuelType: String?

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

    /// Records the Cheapest-toggle coach mark as seen — persisted locally, never re-armed (unlike
    /// the announcement/release-notice flags above, this hint has no remote content to change).
    func markCheapestToggleTipSeen() {
        defaults.set(true, forKey: Keys.hasSeenCheapestToggleTip)
        reload()
    }

    /// Records the fuel-type-pill coach mark as seen — chained to show right after the Cheapest
    /// toggle's tip (see `FuelTypePillTip`/`NearbyView`), same "app flag + TipKit's own
    /// `MaxDisplayCount(1)` as the authoritative backstop" pattern as `markCheapestToggleTipSeen()`.
    func markFuelTypePillTipSeen() {
        defaults.set(true, forKey: Keys.hasSeenFuelTypePillTip)
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
            // `defaults.bool(forKey:)` returns `false` whenever the key has never been written,
            // regardless of `UserPreferences.useLongFuelNames`'s own Swift default — so a plain
            // `.bool(forKey:)` here would silently ignore that default for every install, new and
            // existing alike. Read the key as an optional instead: `nil` means "never explicitly
            // set", which is the only case that should fall back to the new default of `true`; a
            // user who ever toggled it (to true OR false) keeps their explicit choice.
            useLongFuelNames: defaults.object(forKey: Keys.useLongFuelNames) as? Bool ?? true,
            themeMode: ThemeMode(rawValue: defaults.string(forKey: Keys.themeMode) ?? "") ?? .system,
            dismissedAnnouncementMessage: defaults.string(forKey: Keys.dismissedAnnouncement),
            dismissedReleaseNoticeKey: defaults.string(forKey: Keys.dismissedReleaseNotice),
            hasSeenCheapestToggleTip: defaults.bool(forKey: Keys.hasSeenCheapestToggleTip),
            hasSeenFuelTypePillTip: defaults.bool(forKey: Keys.hasSeenFuelTypePillTip)
        )
    }
}
