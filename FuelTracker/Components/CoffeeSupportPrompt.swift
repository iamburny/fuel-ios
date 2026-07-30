import SwiftUI

/// Ports fuel-android's `CoffeeSupportDialog.kt` — a custom-styled confirm button (Buy Me a
/// Coffee's own brand yellow, `#FFDD00`, matching `BuyMeACoffeeYellow` there, plus the brand's
/// script-style wordmark) rather than a plain system button. SwiftUI's native `.alert(...)` can't
/// render custom button styling at all (it's backed by `UIAlertController`, which only supports
/// plain-text default/cancel/destructive buttons) — so this is a hand-built overlay card standing
/// in for `.alert`, not a stylistic preference. `RootView` presents/dismisses it with the same
/// `showCoffeePrompt`/`onDismissCoffee`/`onCoffeeClicked` flow `.alert` used before.
struct CoffeeSupportPrompt: View {
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    /// Buy Me a Coffee's brand yellow (`#FFDD00`) — same value already used for the cup icon tint
    /// on Settings' "Buy me a coffee" row, and for Android's `BuyMeACoffeeYellow`.
    private static let brandYellow = Color(red: 1, green: 0xDD / 255, blue: 0)

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.primary)

                Text("Keep Fuel Tracker free?")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)

                Text("I want to keep this app free. Apple charges to host apps on the App Store — has it saved you money? Buy me a coffee to help!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button(action: onConfirm) {
                    HStack(spacing: 8) {
                        Image(systemName: "cup.and.saucer.fill")
                            .font(.system(size: 18))
                        // Snell Roundhand ships as a built-in iOS system font (no bundling
                        // needed) — its script style is what gives the Buy Me a Coffee badge its
                        // distinctive handwritten look, rather than a plain system label font.
                        Text("Buy me a coffee")
                            .font(.custom("SnellRoundhand-Bold", size: 22))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Self.brandYellow))
                }

                Button("Maybe later", action: onDismiss)
                    .font(.subheadline)
                    .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 340)
            .background(RoundedRectangle(cornerRadius: 20).fill(Color(.secondarySystemBackground)))
            .padding(32)
        }
        .transition(.opacity)
    }
}

#Preview {
    CoffeeSupportPrompt(onConfirm: {}, onDismiss: {})
}
