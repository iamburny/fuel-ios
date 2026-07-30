import SwiftUI
import Charts

/// Price line chart using Swift Charts (the idiomatic iOS approach) rather than a pixel-identical
/// port of Android's hand-rolled `PriceLineChart.kt` Canvas drawing — same data/summary shape
/// (line + filled area + points, start/mid/end date labels, a Low/High/Δ summary row), native
/// rendering. Used for both a station's price history (Detail) and the national trend (Prices).
struct PriceLineChart: View {
    let values: [Double]
    let dates: [String]
    let lineColor: Color

    private struct Point: Identifiable {
        let id: Int
        let value: Double
        let dateLabel: String
    }

    private var points: [Point] {
        values.enumerated().map { index, value in
            Point(id: index, value: value, dateLabel: Self.shortDate(dates.indices.contains(index) ? dates[index] : ""))
        }
    }

    var body: some View {
        if values.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 8) {
                Chart(points) { point in
                    AreaMark(x: .value("Index", point.id), y: .value("Price", point.value))
                        .foregroundStyle(lineColor.opacity(0.12))
                    LineMark(x: .value("Index", point.id), y: .value("Price", point.value))
                        .foregroundStyle(lineColor)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    PointMark(x: .value("Index", point.id), y: .value("Price", point.value))
                        .foregroundStyle(lineColor)
                        .symbolSize(30)
                }
                .chartXAxis {
                    AxisMarks(values: xAxisIndices) { value in
                        if let idx = value.as(Int.self), points.indices.contains(idx) {
                            AxisValueLabel(points[idx].dateLabel)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartYScale(domain: yDomain)
                .frame(height: 200)
                // AreaMark's fill shape isn't clipped to the chart's own frame by default — with a
                // non-zero-floored yDomain (see below) its rendered extent can spill past the 200pt
                // frame into whatever content sits below it. Clip explicitly rather than relying on
                // Charts' own (apparently frame-unaware) bounds.
                .clipped()

                HStack(spacing: 24) {
                    Text("Low: \(String(format: "%.1fp", values.min() ?? 0))")
                    Text("High: \(String(format: "%.1fp", values.max() ?? 0))")
                    Text("Δ \(String(format: "%.1fp", (values.max() ?? 0) - (values.min() ?? 0)))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        }
    }

    /// Without an explicit domain, Swift Charts anchors an AreaMark's baseline at 0 — for a
    /// pence series that only ever moves within a ~10-20p band, that squashes the line flat near
    /// the bottom. Mirrors Android's PriceLineChart.kt: pad the data's own min/max by 10% of its
    /// range, floored at 0.5p so a flat/near-flat series still gets a visible span.
    private var yDomain: ClosedRange<Double> {
        let minV = values.min() ?? 0
        let maxV = values.max() ?? 0
        let pad = max((maxV - minV) * 0.1, 0.5)
        return (minV - pad)...(maxV + pad)
    }

    private var xAxisIndices: [Int] {
        let lastIndex = points.count - 1
        guard lastIndex >= 0 else { return [] }
        return Array(Set([0, lastIndex / 2, lastIndex])).sorted()
    }

    /// "2026-07-24T…" -> "24 Jul"; falls back to the first 10 chars if it can't be parsed.
    private static func shortDate(_ iso: String) -> String {
        let datePart = String(iso.prefix(10))
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        guard let date = inputFormatter.date(from: datePart) else { return datePart }
        let outputFormatter = DateFormatter()
        outputFormatter.dateFormat = "d MMM"
        return outputFormatter.string(from: date)
    }
}
