import SwiftUI

/// Horizontal scrolling row of fuel-type selector chips — shared between `NearbyView`'s search
/// panel and `CheapestSheetView` so both present an identical control.
struct FuelTypeChipRow: View {
    let selectedFuelType: String
    let useLongNames: Bool
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FuelType.allCases) { fuelType in
                    let selected = selectedFuelType == fuelType.rawValue
                    Text(fuelType.label(useLongNames: useLongNames))
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(selected ? .white : .primary)
                        .background(Capsule().fill(selected ? fuelType.color : Color.gray.opacity(0.15)))
                        .onTapGesture { onSelect(fuelType.rawValue) }
                }
            }
            .padding(.horizontal, 12)
        }
    }
}
