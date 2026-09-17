import SwiftUI

struct StationListRow: View {
    let station: StationDTO
    let fuelType: String
    let useLongNames: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Image(systemName: "fuelpump.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).fontWeight(.medium)
                    Text([station.brand, station.distanceMiles.map { String(format: "%.1f mi", $0) }, station.postcode]
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
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
