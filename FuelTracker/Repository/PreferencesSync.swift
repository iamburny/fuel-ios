import Foundation

/// Reconciles this device's local preferences with the account's stored ones: a field the account
/// has already set wins over the local value; a field the account has never set (nil) adopts this
/// device's local value instead, seeding the account the first time it's fetched. Saves the merged
/// result locally and pushes it back (so a field just adopted from local gets persisted server-side
/// too), then returns it.
///
/// Best-effort — returns `nil` on any failure (including being signed out), so callers can no-op
/// rather than surface an error for what's just a background reconciliation.
///
/// Direct port of fuel-android's `PreferencesSync.kt`. Shared by `AuthViewModel` (right after a
/// successful sign-in) and `SettingsViewModel` (every time the Settings screen is (re)appears
/// while already signed in — login alone only reconciles once, so a change made on another
/// device/platform after that first login would otherwise never reach this one).
@MainActor
func syncPreferencesBestEffort(
    repository: FuelRepository,
    preferencesStore: UserPreferencesStore
) async -> UserPreferences? {
    guard repository.isLoggedIn else { return nil }
    do {
        let remote = try await repository.getPreferences()
        let local = preferencesStore.preferences
        let merged = UserPreferences(
            fuelType: remote.fuelType ?? local.fuelType,
            mpg: remote.mpg ?? local.mpg,
            tankCapacityLitres: remote.tankCapacityLitres ?? local.tankCapacityLitres,
            useLongFuelNames: remote.useLongFuelNames ?? local.useLongFuelNames,
            themeMode: remote.themeMode.flatMap(ThemeMode.init(rawValue:)) ?? local.themeMode
        )
        preferencesStore.save(
            fuelType: merged.fuelType,
            mpg: merged.mpg,
            tankCapacityLitres: merged.tankCapacityLitres,
            useLongFuelNames: merged.useLongFuelNames,
            themeMode: merged.themeMode
        )
        _ = try? await repository.updatePreferences(PreferencesDTO(
            fuelType: merged.fuelType,
            mpg: merged.mpg,
            tankCapacityLitres: merged.tankCapacityLitres,
            useLongFuelNames: merged.useLongFuelNames,
            themeMode: merged.themeMode.rawValue
        ))
        return preferencesStore.preferences
    } catch {
        return nil
    }
}
