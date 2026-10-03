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
    private let manager: CLLocationManager
    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var currentLocation: CLLocation?

    private var permissionContinuations: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var streamContinuations: [UUID: AsyncStream<CLLocation>.Continuation] = [:]
    private var oneShotContinuations: [CheckedContinuation<CLLocation?, Never>] = []
    private var isUpdating = false

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        authorizationStatus = manager.authorizationStatus
        super.init()
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

    /// Yields once on the next transition to granted, then finishes; already finished if
    /// permission is granted now. NearbyViewModel waits briefly on this before its first load so
    /// it doesn't flash London then immediately correct. Each call returns its own stream:
    /// cancelling a task iterating an `AsyncStream` finishes that stream, so a shared one would be
    /// killed for every subscriber by the first timed-out wait.
    func permissionGrantedUpdates() -> AsyncStream<Void> {
        if hasPermission { return AsyncStream { $0.finish() } }
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { [weak self] continuation in
            self?.permissionContinuations[id] = continuation
            continuation.onTermination = { _ in
                Task { @MainActor in self?.permissionContinuations[id] = nil }
            }
        }
    }

    /// Continuous stream of fixes so the caller's map can follow the user in real time. Supports
    /// multiple concurrent subscribers. Subscribing before permission is granted is fine: updates
    /// start as soon as it is. A new subscriber first gets the last known fix, if any — with
    /// `distanceFilter` set, a fix that landed before subscribing isn't repeated until the device
    /// moves.
    func locationUpdates() -> AsyncStream<CLLocation> {
        startUpdatingIfNeeded()
        let id = UUID()
        return AsyncStream { [weak self] continuation in
            self?.streamContinuations[id] = continuation
            if let currentLocation = self?.currentLocation {
                continuation.yield(currentLocation)
            }
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
            let wasGranted = hasPermission
            authorizationStatus = manager.authorizationStatus
            // Location permission can be revoked (or an "Allow Once" grant expire) while the app
            // keeps running; reset so a later grant starts updates again.
            if !hasPermission, isUpdating {
                isUpdating = false
                manager.stopUpdatingLocation()
            }
            guard hasPermission, !wasGranted else { return }
            if !streamContinuations.isEmpty {
                startUpdatingIfNeeded()
            }
            let pending = permissionContinuations.values
            permissionContinuations.removeAll()
            for continuation in pending {
                continuation.yield()
                continuation.finish()
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
