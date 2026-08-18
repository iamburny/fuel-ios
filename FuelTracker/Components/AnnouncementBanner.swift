import SwiftUI

/// Ports fuel-android's `AnnouncementBanner.kt`/`AnnouncementBannerViewModel`. Deliberately a plain
/// `View` with no dedicated view model — `FeatureFlags` and `UserPreferencesStore` are both already
/// `@Observable` and reach every screen via `@Environment`, so `message` can just be a computed
/// property read live in the body (automatically reactive to both) instead of needing to bridge
/// Android's `featureFlags.version.collect { refresh() }` re-evaluation dance into a second
/// observable object.
///
/// Demo of the shared.announcement-banner feature flag — proves the Unleash wiring end-to-end.
/// Renders nothing when the flag's off, unconfigured, or its current message was already
/// dismissed. Note the flag's `isEnabled` call here has NO explicit default (so it defaults to
/// `false`/hidden when Unleash is unreachable) — unlike the web-card flag, this is new UI, not
/// pre-existing behaviour to preserve, so hidden is the correct unconfigured fallback.
struct AnnouncementBanner: View {
    private static let flagName = "shared.announcement-banner"

    @Environment(FeatureFlags.self) private var featureFlags
    @Environment(UserPreferencesStore.self) private var preferencesStore

    private var message: String? {
        let text = featureFlags.isEnabled(Self.flagName) ? featureFlags.variantText(Self.flagName) : nil
        let dismissed = preferencesStore.preferences.dismissedAnnouncementMessage
        return (text != nil && text != dismissed) ? text : nil
    }

    var body: some View {
        if let message {
            HStack(alignment: .center) {
                Text(message)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    preferencesStore.dismissAnnouncement(message)
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.accentColor.opacity(0.15)))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
