import SwiftUI

/// The `notice.viewChangeNotes` flag's variant payload — all fields optional so a partially (or
/// entirely empty) configured variant still resolves to sensible defaults per-field, rather than
/// the whole notice failing to decode. Mirrors fuel-android's `ReleaseNoticeContent`.
struct ReleaseNoticeContent: Decodable, Identifiable {
    var text: String?
    var buttonText: String?
    var buttonUrl: String?
    /// Free-form value (a date, a version tag — whatever) with no meaning beyond being this
    /// notice's dismiss identity: bump it in the variant to force the notice to show again, leave
    /// it as-is to tweak wording/URL without re-showing to everyone who already dismissed it.
    var date: String?

    static let flagName = "notice.viewChangeNotes"

    static let defaultText = "Latest full release notes are available on the fuel tracker website"
    static let defaultButtonText = "View Release Notes"
    static let defaultButtonURL = "https://fueltracker.uk/release-notes"

    var resolvedText: String {
        text?.isEmpty == false ? text! : Self.defaultText
    }

    var resolvedButtonText: String {
        buttonText?.isEmpty == false ? buttonText! : Self.defaultButtonText
    }

    var resolvedButtonURL: URL {
        buttonUrl.flatMap { URL(string: $0) } ?? URL(string: Self.defaultButtonURL)!
    }

    /// Dismiss identity — driven solely by `date`, not the display text/button/url, so editing
    /// copy alone never re-shows a notice someone already dismissed; only bumping `date` does.
    /// Falls back to a fixed constant when the variant doesn't set `date` at all.
    var id: String { date?.isEmpty == false ? date! : "default" }
}

/// Body text + single CTA button shown once per distinct `ReleaseNoticeContent`, modeled on
/// `DataAttributionNotice`'s text+button shape. Presented as a `.sheet(item:)` from `RootView`.
struct ReleaseNoticeModal: View {
    let content: ReleaseNoticeContent

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("What's New")
                .font(.title2.bold())
                .padding(.top, 24)

            Text(content.resolvedText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                openURL(content.resolvedButtonURL)
                dismiss()
            } label: {
                Text(content.resolvedButtonText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)

            Spacer()
        }
        .presentationDetents([.medium])
    }
}
