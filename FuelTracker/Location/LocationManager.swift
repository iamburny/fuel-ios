import CoreLocation
import Observation

/// Ports fuel-android's `LocationHelper.kt`. CoreLocation has no distinct "one-shot vs continuous"
/// request pair the way FusedLocationProviderClient does, so both `getCurrentLocation()` and
/// `locationUpdates()` share one underlying `CLLocationManager` with `startUpdatingLocation()`:
/// the one-shot call returns the cached fix immediately if we already have one (mirrors Android's
/// fast, reliable `lastLocation` fallback — simulators are flaky for a genuinely fresh fix), else
/// waits up to 5s for the first delivery.
@Observable
@MainActor
final class LocationManager: NSObject {
    private let manager = CLLocationManager()
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var currentLocation: CLLocation?

    /// Fires whenever authorization transitions to granted — NearbyViewModel waits briefly on
    /// this before its first load, matching Android's short wait for the permission dialog to be
    /// answered so it doesn't flash London then immediately correct.
    let permissionGranted: AsyncStream<Void>
    private var permissionContinuation: AsyncStream<Void>.Continuation?

    private var streamContinuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]
    private var oneShotContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var isUpdating = false

    override init() {
        authorizationStatus = CLLocationManager().authorizationStatus
        var continuation: AsyncStream<Void>.Continuation!
        permissionGranted = AsyncStream { continuation = $0 }
        super.init()
        permissionContinuation = continuation
        manager.delegate = self
        // Rough analogue of Android's PRIORITY_BALANCED_POWER_ACCURACY; CoreLocation has no direct
        // update-interval knob, distanceFilter is the closest equivalent to "don't over-deliver".
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 10
    }

    var hasPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestPermissionIfNeeded() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// One-shot current location; `nil` if permission isn't granted or no fix arrives in time.
    func getCurrentLocation() async -> CLLocation? {
        guard hasPermission else { return nil }
        startUpdatingIfNeeded()
        if let currentLocation { return currentLocation }
        return await waitForFirstFix(timeoutSeconds: 5)
    }

    /// Continuous stream of fixes so the caller's map can follow the user in real time. Supports
    /// multiple concurrent subscribers.
    func locationUpdates() -> AsyncStream<CLLocation> {
        startUpdatingIfNeeded()
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            self?.streamContinuations[id] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor in self?.streamContinuations[id] = nil }
            }
        }
    }

    private func startUpdatingIfNeeded() {
        guard hasPermission, !isUpdating else { return }
        isUpdating = true
        manager.startUpdatingLocation()
    }

    private func waitForFirstFix(timeoutSeconds: Double) async -> CLLocation? {
        await withCheckedContinuation { continuation in
            oneShotContinuations.append(continuation)
            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                await MainActor.run { self.resolvePendingLocationRequests(with: self.currentLocation) }
            }
        }
    }

    private func resolvePendingLocationRequests(with location: CLLocation?) {
        let pending = oneShotContinuations
        oneShotContinuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: location)
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if hasPermission {
                permissionContinuation?.yield()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            currentLocation = location
            resolvePendingLocationRequests(with: location)
            for continuation in streamContinuations.values {
                continuation.yield(location)
            }
        }
    }
}
