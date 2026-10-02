import SwiftUI

/// Marks a station whose drivers often found the pump price didn't match the published one
/// (the API's `price_accuracy_warning`). It is driver-reported, so it sits beside the price and
/// says so; it never changes sorting, filtering or how the price itself is shown.
struct AccuracyWarningChip: View {
    static let label = "Drivers report price differences"
    static let detail = "Drivers who rated this station often found the pump price didn't match the published price. Driver reports, not Fuel Finder data."

    /// Amber, matching the website's warning tint; dark mode gets a lighter shade for contrast.
    static let tint = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0xFB / 255, green: 0xBF / 255, blue: 0x24 / 255, alpha: 1)
        : UIColor(red: 0xB4 / 255, green: 0x53 / 255, blue: 0x09 / 255, alpha: 1)
    })

    var body: some View {
        Label(Self.label, systemImage: "exclamationmark.triangle.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Self.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(Self.tint.opacity(0.15)))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Self.label)
            .accessibilityHint(Self.detail)
    }
}
