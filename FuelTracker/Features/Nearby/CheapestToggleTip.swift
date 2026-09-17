import TipKit

/// One-time coach mark pointing at `NearbyView`'s toolbar toggle, so users discover it now surfaces
/// cheapest-first prices rather than just "search." Shown once ever, gated to only ever appear
/// while the panel is closed — see `NearbyView`'s `.popoverTip(_:)` call site. "Seen" is persisted
/// via `UserPreferencesStore.markCheapestToggleTipSeen()`, called only after the tip actually shows
/// (not at trigger time), so an interrupted first-show doesn't burn the user's only chance to see it.
///
/// That app-level flag only fires from the toolbar button's own tap action, so it can't catch every
/// way TipKit lets someone dismiss the popover (its built-in "X" close button, tapping elsewhere on
/// screen, etc.) — leaving the app's own gate open in those cases. `options` closes that gap
/// authoritatively: `MaxDisplayCount(1)` is TipKit's own guarantee, tracked in its own per-device
/// datastore independent of this app's dismiss-handling, that the tip is shown at most once ever no
/// matter how it's dismissed. The UserDefaults flag stays as-is on top of this — it's this app's own
/// simple, inspectable record of whether the hint was ever offered (matching `AnnouncementBanner`/
/// `ReleaseNoticeModal`'s precedent of not just trusting an opaque system store), and remains
/// harmless/redundant once TipKit's own one-time guarantee is in place.
struct CheapestToggleTip: Tip {
    var title: Text {
        Text("Cheapest prices nearby")
    }

    var message: Text? {
        Text("Tap here to see nearby stations sorted by price, low to high.")
    }

    var image: Image? {
        Image(systemName: "sterlingsign.circle")
    }

    var options: [Self.Option] {
        MaxDisplayCount(1)
    }
}
