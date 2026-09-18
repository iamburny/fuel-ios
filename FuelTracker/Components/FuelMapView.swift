import SwiftUI
import CoreLocation
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
    /// Whether this station is in the user's favourites — rendered as a gold ring + star badge on
    /// the price chip, layered on top of (not replacing) the fuel-type fill color, so it never
    /// collides with the existing color coding. `var` (not `let`) so the synthesized memberwise
    /// init can still take it as an overridable parameter — a `let` with a default value is
    /// excluded from that init entirely, always locking it to `false`.
    var isFavourite: Bool = false
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
    /// Camera rotation, degrees clockwise from north. Defaults to 0 (north-up), preserving
    /// `DetailView`'s existing static-map call site untouched.
    var bearing: CLLocationDirection = 0
    var markers: [MapMarkerItem] = []
    var onMarkerClick: ((Int) -> Void)?
    var recenterKey: Int?
    var onCameraIdle: ((GMSCoordinateBounds) -> Void)?
    var showMyLocation = false

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: centerLat, longitude: centerLng, zoom: zoomLevel, bearing: bearing, viewingAngle: 0)
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = showMyLocation
        mapView.settings.myLocationButton = false
        // Native reorient-to-north control: shown only while the camera's bearing != 0, tapping it
        // animates bearing back to 0 (leaving center/zoom untouched), then it fades out again —
        // exactly matches the "compass" story's acceptance criteria with no custom overlay needed.
        mapView.settings.compassButton = true
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
            mapView.camera = GMSCameraPosition.camera(withLatitude: centerLat, longitude: centerLng, zoom: zoomLevel, bearing: bearing, viewingAngle: 0)
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
        // Tracks the last-applied item per key so a pure favourite-toggle (snippet/price unchanged)
        // still triggers an icon update — `existing.snippet != item.snippet` alone wouldn't notice
        // an isFavourite flip when the price hasn't also changed.
        private var lastItemByKey: [String: MapMarkerItem] = [:]

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
                    let last = lastItemByKey[itemKey]
                    if last?.snippet != item.snippet || last?.isFavourite != item.isFavourite {
                        existing.snippet = item.snippet
                        // No snippet (the Detail screen's single station-location marker, with no
                        // price to show) falls back to Google Maps' own default pin rather than a
                        // price chip with a placeholder "?" — that read as a data error, not "no
                        // price to show here".
                        existing.iconView = item.snippet.map { PriceChipView(text: $0, color: item.color ?? .systemBlue, isFavourite: item.isFavourite) }
                    }
                    existing.title = item.title
                    existing.zIndex = item.isFavourite ? 1 : 0
                    lastItemByKey[itemKey] = item
                } else {
                    let marker = GMSMarker(position: CLLocationCoordinate2D(latitude: item.lat, longitude: item.lng))
                    marker.title = item.title
                    marker.snippet = item.snippet
                    marker.iconView = item.snippet.map { PriceChipView(text: $0, color: item.color ?? .systemBlue, isFavourite: item.isFavourite) }
                    marker.userData = item.stationId as Any
                    marker.zIndex = item.isFavourite ? 1 : 0
                    marker.map = mapView
                    markersByKey[itemKey] = marker
                    lastItemByKey[itemKey] = item
                }
            }
            for (itemKey, marker) in markersByKey where !seenKeys.contains(itemKey) {
                marker.map = nil
                markersByKey.removeValue(forKey: itemKey)
                lastItemByKey.removeValue(forKey: itemKey)
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
    init(text: String, color: UIColor, isFavourite: Bool = false) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .boldSystemFont(ofSize: 11)
        label.sizeToFit()
        let width = label.bounds.width + 12
        let height = label.bounds.height + 6
        // Extra margin for the favourite badge, which overhangs the top-right corner — keeps it
        // from being clipped by the chip's own bounds.
        let badgeMargin: CGFloat = isFavourite ? 5 : 0
        super.init(frame: CGRect(x: 0, y: 0, width: width + badgeMargin, height: height + badgeMargin))
        label.frame = CGRect(x: 6, y: 3, width: label.bounds.width, height: label.bounds.height)
        backgroundColor = color
        layer.cornerRadius = 6
        // The chip's fill color still encodes fuel type (see NearbyView.mapLayer) — favourite
        // status is layered on top as a gold ring + star badge, never a color change, so the two
        // signals never collide.
        layer.borderWidth = isFavourite ? 2.5 : 1
        layer.borderColor = (isFavourite ? UIColor.systemYellow : UIColor.white).cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.3
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: 1)
        addSubview(label)

        if isFavourite {
            let star = UIImageView(image: UIImage(systemName: "star.fill"))
            star.tintColor = .systemYellow
            star.frame = CGRect(x: bounds.width - 12, y: -4, width: 12, height: 12)
            addSubview(star)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
