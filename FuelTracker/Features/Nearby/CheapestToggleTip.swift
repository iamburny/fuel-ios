import TipKit

/// One-time coach mark pointing at `NearbyView`'s toolbar toggle, so users discover it now surfaces
/// cheapest-first prices rather than just "search." Shown once ever, gated to only ever appear
/// while the panel is closed — see `NearbyView`'s `.popoverTip(_:)` call site. "Seen" is persisted
/// via `UserPreferencesStore.markCheapestToggleTipSeen()`, called only after the tip actually shows
/// (not at trigger time), so an interrupted first-show doesn't burn the user's only chance to see it.
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
}
