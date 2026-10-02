import SwiftUI

/// Shared "Report a price discrepancy" + gov.uk source attribution block used on Nearby, Prices,
/// and Detail — anywhere government fuel-price data is shown. Includes a real tappable `Link` to
/// the source collection page (not just a bare mention of the domain in `noticeText`), required by
/// Apple's Guideline 5.6 accuracy expectations for apps presenting government data.
struct DataAttributionNotice: View {
    var noticeText: String = DataAttributionNotice.defaultText

    @Environment(\.openURL) private var openURL

    /// Destination of "Report a price discrepancy", which the Fuel Finder scheme requires apps
    /// showing its prices to offer. GOV.UK's guidance page explains how to report a wrong price and
    /// links on to the service's report form, so the app doesn't depend on the form's own URL.
    /// Same URL as Android's `DataAttributionNotice`.
    static let discrepancyURL = URL(string: "https://www.gov.uk/guidance/report-an-error-in-fuel-prices-or-forecourt-details")!

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
