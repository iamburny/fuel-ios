import Testing
import CoreLocation
import SwiftData
@testable import FuelTracker

/// Stands in for CoreLocation so authorization and fixes can be driven by the test. Delegate
/// callbacks are invoked directly with this instance, so `authorizationStatus` is what
/// `LocationManager` reads back.
private final class FakeCLLocationManager: CLLocationManager {
    var stubbedStatus: CLAuthorizationStatus
    private(set) var startUpdatingCount = 0

    init(status: CLAuthorizationStatus) {
        stubbedStatus = status
        super.init()
    }

    override var authorizationStatus: CLAuthorizationStatus { stubbedStatus }
    override func requestWhenInUseAuthorization() {}
    override func startUpdatingLocation() { startUpdatingCount += 1 }
}

/// First element the stream yields, or nil if none arrives within `seconds`.
private func firstValue<T: Sendable>(of stream: AsyncStream<T>, within seconds: Double = 1) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            for await value in stream { return value }
            return nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

/// The Nearby screen waits up to 3s for the permission dialog, then keeps listening for a later
/// grant. If the user answers the dialog after that wait has timed out, the later listener must
/// still hear the grant and GPS must start — otherwise the map stays on the London fallback.
@MainActor
struct LocationManagerTests {
    private func grant(_ fake: FakeCLLocationManager, on locationManager: LocationManager) {
        fake.stubbedStatus = .authorizedWhenInUse
        locationManager.locationManagerDidChangeAuthorization(fake)
    }

    @Test func grantReachesListenerAfterAnotherSubscriberWasCancelled() async {
        let fake = FakeCLLocationManager(status: .notDetermined)
        let locationManager = LocationManager(manager: fake)
        let timedOutWait = locationManager.permissionGrantedUpdates()
        let laterListener = locationManager.permissionGrantedUpdates()

        let waitTask = Task { for await _ in timedOutWait {} }
        waitTask.cancel()
        await waitTask.value

        grant(fake, on: locationManager)

        #expect(await firstValue(of: laterListener) != nil)
    }

    @Test func locationUpdatesSubscribedBeforePermissionStartOnGrant() async {
        let fake = FakeCLLocationManager(status: .notDetermined)
        let locationManager = LocationManager(manager: fake)
        let updates = locationManager.locationUpdates()
        let granted = locationManager.permissionGrantedUpdates()
        #expect(fake.startUpdatingCount == 0)

        grant(fake, on: locationManager)
        _ = await firstValue(of: granted)
        #expect(fake.startUpdatingCount == 1)

        locationManager.locationManager(fake, didUpdateLocations: [CLLocation(latitude: 55.8642, longitude: -4.2518)])
        let latitude = await firstValue(of: updates)?.coordinate.latitude
        #expect(latitude == 55.8642)
    }

    /// CoreLocation calls the authorization delegate as soon as it's set, even when nothing has
    /// changed — an app that already had permission must not see that as a fresh grant.
    @Test func alreadyAuthorizedCallbackIsNotAGrant() async {
        let fake = FakeCLLocationManager(status: .authorizedWhenInUse)
        let locationManager = LocationManager(manager: fake)
        let granted = locationManager.permissionGrantedUpdates()

        locationManager.locationManagerDidChangeAuthorization(fake)

        var grants = 0
        for await _ in granted { grants += 1 }
        #expect(grants == 0)
    }

    /// A fix that lands before anyone subscribes (e.g. just after the one-shot request timed out)
    /// isn't repeated by CoreLocation until the device moves, so a new subscriber must get it.
    @Test func newSubscriberReceivesLastKnownFix() async {
        let fake = FakeCLLocationManager(status: .authorizedWhenInUse)
        let locationManager = LocationManager(manager: fake)
        locationManager.locationManager(fake, didUpdateLocations: [CLLocation(latitude: 55.8642, longitude: -4.2518)])
        #expect(await waitUntil { locationManager.currentLocation != nil })

        let latitude = await firstValue(of: locationManager.locationUpdates())?.coordinate.latitude
        #expect(latitude == 55.8642)
    }

    @Test func updatesRestartAfterPermissionIsRevokedAndGrantedAgain() async {
        let fake = FakeCLLocationManager(status: .authorizedWhenInUse)
        let locationManager = LocationManager(manager: fake)
        let updates = locationManager.locationUpdates()
        #expect(fake.startUpdatingCount == 1)

        fake.stubbedStatus = .notDetermined
        locationManager.locationManagerDidChangeAuthorization(fake)
        #expect(await waitUntil { !locationManager.hasPermission })
        let granted = locationManager.permissionGrantedUpdates()
        grant(fake, on: locationManager)
        _ = await firstValue(of: granted)

        #expect(fake.startUpdatingCount == 2)
        withExtendedLifetime(updates) {}
    }

    @Test func grantIsDeliveredOnceThenFinishes() async {
        let fake = FakeCLLocationManager(status: .notDetermined)
        let locationManager = LocationManager(manager: fake)
        let granted = locationManager.permissionGrantedUpdates()

        grant(fake, on: locationManager)
        locationManager.locationManagerDidChangeAuthorization(fake)

        var grants = 0
        for await _ in granted { grants += 1 }
        #expect(grants == 1)
    }
}

/// Polls `condition` until it holds or `seconds` pass; returns whether it held.
@MainActor
private func waitUntil(within seconds: Double = 2, _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(seconds)
    while !condition() {
        if ContinuousClock.now > deadline { return false }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return true
}

/// The on-device failure end to end: the permission dialog is answered after the Nearby screen's
/// 3s wait, so its first load uses the London fallback. Once permission lands, the first real fix
/// must move the camera and reload stations around it — exactly once. Takes ~3s for that wait.
@MainActor
struct NearbyViewModelLocationTests {
    @Test func lateGrantRecentersAndReloadsOnceAroundRealPosition() async throws {
        let fake = FakeCLLocationManager(status: .notDetermined)
        let locationManager = LocationManager(manager: fake)
        let api = StubFuelPricesAPI()
        let container = try ModelContainer(
            for: CachedStation.self, CachedFuelPrice.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suiteName = "NearbyViewModelLocationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let viewModel = NearbyViewModel(
            repository: FuelRepository(api: api, modelContext: ModelContext(container), tokenStore: TokenStore()),
            locationManager: locationManager,
            preferencesStore: UserPreferencesStore(defaults: defaults),
            analytics: NoOpAppAnalytics()
        )

        #expect(await waitUntil(within: 6) { api.nearbyRequests.count == 1 })
        #expect(api.nearbyRequests.first?.lat == 51.5074)
        #expect(!viewModel.hasGpsFix)
        #expect(await waitUntil { viewModel.cameraRecenterToken == 1 })

        fake.stubbedStatus = .authorizedWhenInUse
        locationManager.locationManagerDidChangeAuthorization(fake)
        #expect(await waitUntil { fake.startUpdatingCount == 1 })
        locationManager.locationManager(fake, didUpdateLocations: [CLLocation(latitude: 55.8642, longitude: -4.2518)])

        #expect(await waitUntil { api.nearbyRequests.count == 2 })
        #expect(api.nearbyRequests.last?.lat == 55.8642)
        #expect(viewModel.userLat == 55.8642)
        #expect(viewModel.hasGpsFix)
        #expect(viewModel.cameraRecenterToken > 1)

        try await Task.sleep(for: .milliseconds(300))
        #expect(api.nearbyRequests.count == 2)
    }
}
