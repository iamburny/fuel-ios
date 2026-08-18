import Foundation
import Observation

/// Direct port of fuel-android's `PreferencesViewModel.kt`. The `showAlsoAvailableOnWeb`
/// (Unleash-gated) "extras" piece is deliberately not ported here — it's read directly in
/// `SettingsView` instead. `showBuyMeCoffee` has no iOS equivalent at all: Apple rejected
/// submission 1.0 (1) under Guideline 3.1.1 for the external buymeacoffee.com link.
@Observable
@MainActor
final class SettingsViewModel {
    var fuelType: String
    var mpgText: String
    var tankCapacityText: String
    var useLongFuelNames: Bool
    var themeMode: ThemeMode
    var justSaved = false

    private let preferencesStore: UserPreferencesStore
    private var saveTask: Task<Void, Never>?

    init(preferencesStore: UserPreferencesStore) {
        self.preferencesStore = preferencesStore
        let prefs = preferencesStore.preferences
        fuelType = prefs.fuelType
        mpgText = prefs.mpg.map(Self.formatNumber) ?? ""
        tankCapacityText = prefs.tankCapacityLitres.map(Self.formatNumber) ?? ""
        useLongFuelNames = prefs.useLongFuelNames
        themeMode = prefs.themeMode
    }

    func setFuelType(_ type: String) {
        fuelType = type
        saveNow()
    }

    func setMpgText(_ text: String) {
        mpgText = text
        saveDebounced()
    }

    func setTankCapacityText(_ text: String) {
        tankCapacityText = text
        saveDebounced()
    }

    func setUseLongFuelNames(_ value: Bool) {
        useLongFuelNames = value
        saveNow()
    }

    func setThemeMode(_ mode: ThemeMode) {
        themeMode = mode
        saveNow()
    }

    // Discrete choices (chips, switch, segmented control) persist immediately.
    private func saveNow() {
        saveTask?.cancel()
        saveTask = Task { await persist() }
    }

    // Text fields debounce so we don't write to UserDefaults on every keystroke.
    private func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await persist()
        }
    }

    private func persist() async {
        preferencesStore.save(
            fuelType: fuelType,
            mpg: Double(mpgText),
            tankCapacityLitres: Double(tankCapacityText),
            useLongFuelNames: useLongFuelNames,
            themeMode: themeMode
        )
        justSaved = true
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        justSaved = false
    }

    private static func formatNumber(_ value: Double) -> String {
        let intValue = Int(value)
        return value == Double(intValue) ? "\(intValue)" : "\(value)"
    }
}
