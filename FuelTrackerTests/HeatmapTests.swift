import Testing
import UIKit
@testable import FuelTracker

struct HeatmapTests {
    private func cell(delta: Double) -> HeatmapCell {
        HeatmapCell(latitude: 0, longitude: 0, avgPricePence: 150, deltaPence: delta, deltaPercent: 0, stationCount: 1)
    }

    @Test func computeMaxAbsFloorsAtThreeForEmptyOrFlatData() {
        #expect(HeatmapViewModel.computeMaxAbs([]) == 3.0)
        #expect(HeatmapViewModel.computeMaxAbs([cell(delta: 0), cell(delta: 0.1)]) == 3.0)
    }

    @Test func computeMaxAbsSingleCell() {
        // p90 index for count=1 must clamp to index 0, not go out of bounds.
        #expect(HeatmapViewModel.computeMaxAbs([cell(delta: 5.0)]) == 5.0)
    }

    @Test func computeMaxAbsUsesNinetiethPercentileNotMax() {
        // 100 cells, deltas 1...100 — a couple of outliers shouldn't set maxAbs to the true max
        // (100); the 90th percentile (index 90, value 91) should win instead.
        let cells = (1...100).map { cell(delta: Double($0)) }
        let result = HeatmapViewModel.computeMaxAbs(cells)
        #expect(result == 91.0)
        #expect(result < 100.0)
    }

    @Test func computeMaxAbsRoundsToOneDecimalPlace() {
        let cells = [cell(delta: 4.26), cell(delta: 4.26)]
        #expect(HeatmapViewModel.computeMaxAbs(cells) == 4.3)
    }
}

struct HeatColorTests {
    @Test func zeroDeltaIsMidColor() {
        let color = HeatColor.uiColor(delta: 0, maxAbs: 10)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // #eab308 amber
        #expect(abs(r - 234.0 / 255) < 0.01)
        #expect(abs(g - 179.0 / 255) < 0.01)
        #expect(abs(b - 8.0 / 255) < 0.01)
    }

    @Test func positiveDeltaLerpsTowardPricey() {
        let color = HeatColor.uiColor(delta: 10, maxAbs: 10)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // #dc2626 red, fully saturated at delta == maxAbs
        #expect(abs(r - 220.0 / 255) < 0.01)
        #expect(abs(g - 38.0 / 255) < 0.01)
        #expect(abs(b - 38.0 / 255) < 0.01)
    }

    @Test func negativeDeltaLerpsTowardCheap() {
        let color = HeatColor.uiColor(delta: -10, maxAbs: 10)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        // #16a34a green, fully saturated at delta == -maxAbs
        #expect(abs(r - 22.0 / 255) < 0.01)
        #expect(abs(g - 163.0 / 255) < 0.01)
        #expect(abs(b - 74.0 / 255) < 0.01)
    }

    @Test func deltaBeyondMaxAbsClampsRatherThanOvershoots() {
        let atLimit = HeatColor.uiColor(delta: 10, maxAbs: 10)
        let beyond = HeatColor.uiColor(delta: 50, maxAbs: 10)
        #expect(atLimit == beyond)
    }
}
