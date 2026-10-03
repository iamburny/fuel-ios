import SwiftUI
import StoreKit

/// App Clip entry point. iOS launches it from a `https://fueltracker.uk/...` link (Safari, Messages,
/// Maps, a Smart App Banner) and hands over that URL as a browsing-web user activity: a station
/// link opens that station, anything else shows the get-the-app screen.
@main
struct FuelTrackerClipApp: App {
    var body: some Scene {
        WindowGroup {
            ClipRootView()
        }
    }
}

struct ClipRootView: View {
    private enum Destination: Equatable {
        case waiting
        case station(Int)
        case getApp
    }

    @State private var destination: Destination = .waiting
    @State private var showAppOverlay = false

    var body: some View {
        Group {
            switch destination {
            case .waiting:
                ProgressView()
            case .station(let id):
                // A fresh view per station, so a second link while the clip is open loads it
                // instead of keeping the first station's state.
                ClipStationView(stationId: id)
                    .id(id)
            case .getApp:
                ClipGetAppView()
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            if case .station(let id) = DeepLink.from(url: url) {
                destination = .station(id)
            } else {
                destination = .getApp
            }
        }
        // The invocation URL normally arrives straight away; a launch without one (e.g. from
        // Xcode with no `_XCAppClipURL` set) would otherwise spin forever.
        .task {
            try? await Task.sleep(for: .seconds(2))
            if destination == .waiting { destination = .getApp }
        }
        .onChange(of: destination) { _, newValue in
            showAppOverlay = newValue != .waiting
        }
        .appStoreOverlay(isPresented: $showAppOverlay) {
            SKOverlay.AppClipConfiguration(position: .bottom)
        }
    }
}

/// Shown for any link that isn't a station: the clip only covers single stations, so it points
/// to the full app (offered by the App Store overlay underneath) for everything else.
struct ClipGetAppView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "fuelpump.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Fuel Tracker UK")
                .font(.title.bold())
            Text("Find the cheapest petrol and diesel near you, with price alerts and favourite stations in the full app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding(32)
    }
}
