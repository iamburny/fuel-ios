import SwiftUI
import GoogleMaps

/// Mirrors fuel-android's `FuelMapView.kt`. Requires `AppConfig.googleMapsAPIKey`.
struct MapMarkerItem: Identifiable {
    let id = UUID()
    let stationId: Int?
    let lat: Double
    let lng: Double
    let title: String
    let snippet: String?
    let color: UIColor?
}

/// Google Maps SDK wrapper.
///
/// - `recenterKey`: bump this whenever the caller wants a one-off camera jump to
///   `centerLat`/`centerLng` — left `nil` (the default), the camera is never forced to move, so it
///   doesn't fight the user dragging the map.
/// - `onCameraIdle`: fires once a drag ends, with the map's new visible bounds. Gated on
///   `GMSMapViewDelegate`'s `willMove(gesture:)` telling us the in-progress move was a genuine
///   user gesture — this is a deliberate, simpler replacement for Android's `suppressNextIdle`
///   dance: Jetpack Compose's Maps wrapper doesn't expose gesture-vs-programmatic to the caller,
///   so Android has to guess via a hasStartedMoving/suppressNextIdle token; iOS's delegate tells
///   us directly, so a recenter's own move-then-idle cycle is ignored for free.
/// - `showMyLocation`: enables the live "my location" blue dot (requires location permission —
///   caller's responsibility). The SDK's own recenter button is hidden; callers that want one
///   (Nearby) provide their own FAB.
struct FuelMapView: UIViewRepresentable {
    var centerLat: Double = 51.5074
    var centerLng: Double = -0.1278
    var zoomLevel: Float = 12
    var markers: [MapMarkerItem] = []
    var onMarkerClick: ((Int) -> Void)?
    var recenterKey: Int?
    var onCameraIdle: ((GMSCoordinateBounds) -> Void)?
    var showMyLocation = false

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: centerLat, longitude: centerLng, zoom: zoomLevel)
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = showMyLocation
        mapView.settings.myLocationButton = false
        context.coordinator.lastRecenterKey = recenterKey
        context.coordinator.onMarkerClick = onMarkerClick
        context.coordinator.onCameraIdle = onCameraIdle
        context.coordinator.applyMarkers(markers, to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.onMarkerClick = onMarkerClick
        context.coordinator.onCameraIdle = onCameraIdle
        context.coordinator.applyMarkers(markers, to: mapView)
        if mapView.isMyLocationEnabled != showMyLocation {
            mapView.isMyLocationEnabled = showMyLocation
        }

        if recenterKey != context.coordinator.lastRecenterKey {
            context.coordinator.lastRecenterKey = recenterKey
            // Non-animated, matches Android's plain `position =` assignment.
            mapView.camera = GMSCameraPosition.camera(withLatitude: centerLat, longitude: centerLng, zoom: zoomLevel)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onMarkerClick: ((Int) -> Void)?
        var onCameraIdle: ((GMSCoordinateBounds) -> Void)?
        var lastRecenterKey: Int?
        private var isDragInProgress = false
        // Keyed by station (falling back to a lat/lng key for the Detail screen's single
        // stationId-less marker) rather than a flat array — lets applyMarkers below update an
        // existing pin in place instead of removing and recreating every marker on every call.
        private var markersByKey: [String: GMSMarker] = [:]

        private func key(for item: MapMarkerItem) -> String {
            if let stationId = item.stationId { return "s\(stationId)" }
            return "\(item.lat)_\(item.lng)"
        }

        func applyMarkers(_ items: [MapMarkerItem], to mapView: GMSMapView) {
            // Diff against the existing markers rather than a full clear + reinsert: this view's
            // `markers` param gets recomputed (a fresh array of new MapMarkerItem values) on every
            // SwiftUI re-render that touches any @Observable property this screen reads — not just
            // when the underlying station data actually changes (e.g. NearbyViewModel toggling
            // isLoadingViewport around a viewport fetch) — so a naive clear + reinsert visibly
            // flickered pins that hadn't actually changed. Only markers whose price/position
            // genuinely changed get updated; only markers no longer present get removed.
            var seenKeys = Set<String>()
            for item in items {
                let itemKey = key(for: item)
                seenKeys.insert(itemKey)
                if let existing = markersByKey[itemKey] {
                    if existing.position.latitude != item.lat || existing.position.longitude != item.lng {
                        existing.position = CLLocationCoordinate2D(latitude: item.lat, longitude: item.lng)
                    }
                    if existing.snippet != item.snippet {
                        existing.snippet = item.snippet
                        // No snippet (the Detail screen's single station-location marker, with no
                        // price to show) falls back to Google Maps' own default pin rather than a
                        // price chip with a placeholder "?" — that read as a data error, not "no
                        // price to show here".
                        existing.iconView = item.snippet.map { PriceChipView(text: $0, color: item.color ?? .systemBlue) }
                    }
                    existing.title = item.title
                } else {
                    let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: item.lat, longitude: item.lng))
                    marker.title = item.title
                    marker.snippet = item.snippet
                    marker.iconView = item.snippet.map { PriceChipView(text: $0, color: item.color ?? .systemBlue) }
                    marker.userData = item.stationId as Any
                    marker.map = mapView
                    markersByKey[itemKey] = marker
                }
            }
            for (itemKey, marker) in markersByKey where !seenKeys.contains(itemKey) {
                marker.map = nil
                markersByKey.removeValue(forKey: itemKey)
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            guard let onMarkerClick, let stationId = marker.userData as? Int else { return false }
            onMarkerClick(stationId)
            return true
        }

        func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            isDragInProgress = gesture
        }

        func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            guard isDragInProgress else { return }
            isDragInProgress = false
            onCameraIdle?(GMSCoordinateBounds(region: mapView.projection.visibleRegion()))
        }
    }
}

/// Rendered as a small price chip instead of a default pin, so the price is visible directly on
/// the map without needing to tap through to an info window — mirrors `MarkerComposable`'s custom
/// content in the Android source.
private final class PriceChipView: UIView {
    init(text: String, color: UIColor) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 11)
        label.sizeToFit()
        let width = label.bounds.width + 12
        let height = label.bounds.height + 6
        super.init(frame: CGRect(x: 0, y: 0, width: width, height: height))
        label.frame = CGRect(x: 6, y: 3, width: label.bounds.width, height: label.bounds.height)
        backgroundColor = color
        layer.cornerRadius = 6
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(label)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
