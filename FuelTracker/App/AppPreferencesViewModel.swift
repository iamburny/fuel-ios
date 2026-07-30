import Foundation
import Observation

/// Ports fuel-android's `AppPreferencesViewModel.kt` — held at the app root (like Android's
/// Activity-scoped instance) so `RootView` (which calls `onAppOpened()` once per cold launch and
/// renders the prompt) is the single owner. `useLongFuelNames`/`themeMode` aren't duplicated here
/// the way Android re-exposes them as separate `StateFlow`s — every iOS view already reads
/// `UserPreferencesStore.preferences` directly via the shared `@Environment` instance, so there's
/// nothing to bridge.
@Observable
@MainActor
final class AppPreferencesViewModel {
    private let store: UserPreferencesStore
    private let featureFlags: FeatureFlags

    private(set) var showCoffeePrompt = false
    /// The open count at which the prompt is currently showing — used to compute the pause target.
    private var currentOpenCount = 0

    private static let promptEvery = 5
    private static let pauseOpens = 20

    init(store: UserPreferencesStore, featureFlags: FeatureFlags) {
        self.store = store
        self.featureFlags = featureFlags
    }

    /// Record a cold app launch and decide whether to show the support prompt. Called once per
    /// launch from `RootView.onAppear` (guarded there against re-firing on tab switches). Shows on
    /// the first launch and then every `promptEvery` opens (opens 1, 6, 11, …), unless suppressed
    /// until a later open by a previous CTA tap.
    func onAppOpened() {
        let count = store.incrementAppOpenCount()
        currentOpenCount = count
        let pausedUntil = store.preferences.coffeePromptPausedUntilOpen
        let cadenceDue = (count - 1) % Self.promptEvery == 0 && count >= pausedUntil
        // shared.buy-me-a-coffee gates the whole prompt, not just its cadence. Default MUST be
        // false: Unleash's Frontend API (what this client polls) only ever returns flags that are
        // currently enabled — a flag deliberately toggled off is indistinguishable from one that's
        // unknown/not-yet-fetched, both are just absent from the response. A `default: true` here
        // would make it impossible to ever actually turn this off remotely, since a real "off"
        // toggle would silently keep falling back to true forever.
        if cadenceDue && featureFlags.isEnabled("shared.buy-me-a-coffee", default: false) {
            showCoffeePrompt = true
        }
    }

    /// CTA tapped: hide and pause the prompt for `pauseOpens` launches (caller opens the URL).
    func onCoffeeClicked() {
        showCoffeePrompt = false
        store.pauseCoffeePrompt(untilOpen: currentOpenCount + Self.pauseOpens)
    }

    /// Dismissed without tapping the CTA: just hide; it returns at the next `promptEvery` opens.
    func onDismissCoffee() {
        showCoffeePrompt = false
    }
}
