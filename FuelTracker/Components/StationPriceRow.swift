import SwiftUI

/// One fuel's current price on a station screen, with its reported time and either its price
/// warning or how it compares with the national average. Shared by the app's Detail screen and
/// the App Clip.
struct StationPriceRow: View {
    let price: PriceDTO
    let nationalAverages: [NationalAverageDTO]

    var body: some View {
        let nationalAvg = nationalAverages.first { $0.fuelType == price.fuelType }?.avgPricePence
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(FuelType.longLabel(forRaw: price.fuelType)).fontWeight(.medium)
                // Compliance: shown unmodified, original ISO string, not reformatted/relativized.
                Text("Reported: \(price.reportedAt)").font(.caption).foregroundStyle(.secondary)
                // A flagged price keeps its value and timestamp but drops the national-average
                // comparison, which would present a likely-wrong price as a real saving or premium.
                if let warning = price.warning {
                    Text(warning.badgeLabel)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                        .padding(.top, 2)
                    Text(warning.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let nationalAvg {
                    let delta = price.pricePence - nationalAvg
                    Text(String(format: "%+.1fp vs national avg", delta))
                        .font(.caption2)
                        .foregroundStyle(delta <= 0 ? Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255) : .red)
                }
            }
            Spacer()
            Text(String(format: "%.1fp", price.pricePence))
                .font(.title2.bold())
                .foregroundStyle(FuelType.displayColor(forRaw: price.fuelType))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

/// Closed / motorway / supermarket capsules under a station's name. Renders nothing when none
/// apply.
struct StationStatusBadges: View {
    let station: StationDTO

    var body: some View {
        let badges: [(String, Color)] = [
            station.temporaryClosure ? ("Temporarily Closed", .red) : nil,
            station.isMotorway ? ("Motorway Services", Color(red: 0x3B / 255, green: 0x82 / 255, blue: 0xF6 / 255)) : nil,
            station.isSupermarket ? ("Supermarket", Color(red: 0x22 / 255, green: 0xC5 / 255, blue: 0x5E / 255)) : nil,
        ].compactMap { $0 }

        if !badges.isEmpty {
            HStack(spacing: 8) {
                ForEach(badges, id: \.0) { label, color in
                    Text(label)
                        .font(.caption2)
                        .foregroundStyle(color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(color.opacity(0.15)))
                }
            }
            .padding(.bottom, 4)
        }
    }
}
