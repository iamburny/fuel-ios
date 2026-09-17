import SwiftUI

struct StationListRow: View {
    let station: StationDTO
    let fuelType: String
    let useLongNames: Bool
    let userLat: Double?
    let userLng: Double?
    /// `nil` while favourite status hasn't loaded yet — the heart renders dimmed/disabled rather
    /// than guessing.
    let isFavourite: Bool?
    let onTap: () -> Void
    let onToggleFavourite: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            // The navigable content is a plain tap-gesture region, not a `Button` — SwiftUI
            // doesn't support a real `Button` (the heart, below) nested inside another `Button`
            // correctly, so this row can't itself be a `Button` anymore. `.contentShape(Rectangle())`
            // makes the whole region (including the `Spacer()`) hit-testable, not just the text/
            // image glyphs themselves.
            HStack {
                Image(systemName: "fuelpump.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).fontWeight(.medium)
                    Text([station.brand, distanceText, station.postcode]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let price = station.cheapestPrice(for: fuelType) {
                    Text(String(format: "%.1fp", price.pricePence))
                        .font(.title3.bold())
                        .foregroundStyle(FuelType.displayColor(forRaw: fuelType))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)

            // A separate, real `Button` — as a sibling of the tap-gesture region above rather than
            // nested inside it, so hit-testing is unambiguous: each screen point falls within
            // exactly one of the two regions' bounds, and SwiftUI simply routes the tap to whatever
            // view occupies that point. The `Button`'s own gesture recognizer also always wins over
            // an ancestor's `.onTapGesture` for the area it covers, but that scenario doesn't even
            // arise here since the two are siblings, not ancestor/descendant.
            Button(action: onToggleFavourite) {
                Image(systemName: (isFavourite ?? false) ? "heart.fill" : "heart")
                    .foregroundStyle(isFavourite == true ? .red : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isFavourite == nil)
            .opacity(isFavourite == nil ? 0.4 : 1.0)
            .accessibilityLabel((isFavourite ?? false) ? "Remove favourite" : "Add favourite")
        }
    }

    private var distanceText: String? {
        guard let distance = station.displayDistance(userLat: userLat, userLng: userLng) else { return nil }
        return (distance.isApproximate ? "~" : "") + String(format: "%.1f mi", distance.miles)
    }
}
