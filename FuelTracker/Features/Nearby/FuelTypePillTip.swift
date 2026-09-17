import TipKit

/// One-time coach mark pointing at `NearbyView`'s fuel-type pill, chained to appear right after
/// `CheapestToggleTip` is dismissed (see `NearbyView`'s `shouldShowFuelTypePillTip`) — the fuel
/// pill sits on the map itself and is always visible regardless of the search panel's state, unlike
/// the toggle button this tip follows. "Seen" is persisted via
/// `UserPreferencesStore.markFuelTypePillTipSeen()`, mirroring `CheapestToggleTip`'s own comment and
/// reasoning below verbatim, since both tips share the exact same discovery/dismiss mechanics.
///
/// That app-level flag only fires from the fuel pill's own tap action, so it can't catch every way
/// TipKit lets someone dismiss the popover (its built-in "X" close button, tapping elsewhere on
/// screen, etc.) — leaving the app's own gate open in those cases. `options` closes that gap
/// authoritatively: `MaxDisplayCount(1)` is TipKit's own guarantee, tracked in its own per-device
/// datastore independent of this app's dismiss-handling, that the tip is shown at most once ever no
/// matter how it's dismissed. The UserDefaults flag stays as-is on top of this — it's this app's own
/// simple, inspectable record of whether the hint was ever offered (matching `AnnouncementBanner`/
/// `ReleaseNoticeModal`'s precedent of not just trusting an opaque system store), and remains
/// harmless/redundant once TipKit's own one-time guarantee is in place.
struct FuelTypePillTip: Tip {
    var title: Text {
        Text("Switch fuel type")
    }

    var message: Text? {
        Text("Tap to cycle between petrol, diesel, and other fuel types.")
    }

    var options: [Self.Option] {
        MaxDisplayCount(1)
    }
}
