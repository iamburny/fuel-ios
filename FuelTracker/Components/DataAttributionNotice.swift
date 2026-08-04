import SwiftUI

/// Shared "Report a price discrepancy" + gov.uk source attribution block used on Nearby, Prices,
/// and Detail — anywhere government fuel-price data is shown. Includes a real tappable `Link` to
/// the source collection page (not just a bare mention of the domain in `noticeText`), required by
/// Apple's Guideline 5.6 accuracy expectations for apps presenting government data.
struct DataAttributionNotice: View {
    var noticeText: String = DataAttributionNotice.defaultText

    @Environment(\.openURL) private var openURL

    /// The specific /report-discrepancy path 404s (confirmed both on Android and as the backend's
    /// own configured default) — points at the working base domain until there's a real report
    /// page to link to. Matches Android's hardcoded URL exactly.
    static let discrepancyURL = URL(string: "https://www.fuel-finder.service.gov.uk/")!

    static let sourceURL = URL(string: "https://www.gov.uk/government/collections/fuel-finder")!

    static let defaultText = "Prices sourced from the UK Government's Fuel Finder scheme under the Open Government Licence. Data is presented without modification. Fuel Tracker UK is an independent app and is not affiliated with or endorsed by HM Government."

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                openURL(DataAttributionNotice.discrepancyURL)
            } label: {
                Label("Report a price discrepancy", systemImage: "exclamationmark.triangle")
            }
            .padding(.bottom, 8)

            Text(noticeText)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Link("gov.uk/government/collections/fuel-finder", destination: DataAttributionNotice.sourceURL)
                .font(.caption2)
        }
        .padding(EdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16))
    }
}
