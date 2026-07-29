import SwiftUI

/// Placeholder — real implementation (stat cards, all-fuel-types grid, Swift Charts trend,
/// Heatmap entry point) lands in the Prices + Heatmap build phase.
struct PricesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Prices & Trends", systemImage: "chart.line.uptrend.xyaxis", description: Text("Coming in the Prices + Heatmap phase."))
                .navigationTitle("Prices")
        }
    }
}

#Preview {
    PricesView()
}
