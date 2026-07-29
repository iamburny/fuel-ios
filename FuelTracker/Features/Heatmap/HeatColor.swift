import SwiftUI

/// Diverging colour scale for price deviation from the national average — cheaper -> green,
/// about-average -> amber, pricier -> red. Direct port of fuel-android's `HeatColor.kt` (which
/// itself mirrors the web app's lib/heatColor.ts, so all platforms colour the heat map
/// identically). `delta` is pence vs the national mean; `maxAbs` is the deviation that saturates
/// the scale.
enum HeatColor {
    private static let cheap = (r: 22.0 / 255, g: 163.0 / 255, b: 74.0 / 255) // #16a34a green
    private static let mid = (r: 234.0 / 255, g: 179.0 / 255, b: 8.0 / 255) // #eab308 amber
    private static let pricey = (r: 220.0 / 255, g: 38.0 / 255, b: 38.0 / 255) // #dc2626 red

    private static func lerp(_ a: (r: Double, g: Double, b: Double), _ b: (r: Double, g: Double, b: Double), _ t: Double) -> UIColor {
        UIColor(
            red: a.r + (b.r - a.r) * t,
            green: a.g + (b.g - a.g) * t,
            blue: a.b + (b.b - a.b) * t,
            alpha: 1
        )
    }

    static func uiColor(delta: Double, maxAbs: Double) -> UIColor {
        let span = max(maxAbs, 0.1)
        let t = min(max(delta / span, -1), 1)
        return t < 0 ? lerp(mid, cheap, -t) : lerp(mid, pricey, t)
    }

    static func color(delta: Double, maxAbs: Double) -> Color {
        Color(uiColor(delta: delta, maxAbs: maxAbs))
    }
}
