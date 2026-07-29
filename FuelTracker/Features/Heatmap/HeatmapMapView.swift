import SwiftUI
import GoogleMaps

/// Circle-overlay map for the price heat map — a separate, lighter-weight wrapper from
/// `FuelMapView` (which is marker/recenter-oriented for Nearby/Detail) rather than forcing this
/// screen's very different needs (static camera, tappable `GMSCircle` overlays, no markers, no
/// recenter/drag handling) through that API.
struct HeatmapMapView: UIViewRepresentable {
    var cells: [HeatmapCell]
    var maxAbs: Double
    var onCellTap: (HeatmapCell) -> Void

    func makeUIView(context: Context) -> GMSMapView {
        let camera = GMSCameraPosition.camera(withLatitude: 54.5, longitude: -2.5, zoom: 5.2)
        let options = GMSMapViewOptions()
        options.camera = camera
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = false
        mapView.settings.myLocationButton = false
        context.coordinator.onCellTap = onCellTap
        context.coordinator.applyCircles(cells, maxAbs: maxAbs, to: mapView)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        context.coordinator.onCellTap = onCellTap
        context.coordinator.applyCircles(cells, maxAbs: maxAbs, to: mapView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onCellTap: ((HeatmapCell) -> Void)?
        private var circleObjects: [GMSCircle] = []
        private var cellsByCircle: [ObjectIdentifier: HeatmapCell] = [:]

        func applyCircles(_ cells: [HeatmapCell], maxAbs: Double, to mapView: GMSMapView) {
            for circle in circleObjects { circle.map = nil }
            circleObjects.removeAll()
            cellsByCircle.removeAll()
            for cell in cells {
                let color = HeatColor.uiColor(delta: cell.deltaPence, maxAbs: maxAbs)
                let circle = GMSCircle(
                    position: CLLocationCoordinate2D(latitude: cell.latitude, longitude: cell.longitude),
                    radius: Self.radiusMetres(cell.stationCount)
                )
                circle.fillColor = color.withAlphaComponent(0.5)
                circle.strokeColor = color.withAlphaComponent(0.85)
                circle.strokeWidth = 1.5
                circle.isTappable = true
                circle.map = mapView
                circleObjects.append(circle)
                cellsByCircle[ObjectIdentifier(circle)] = cell
            }
        }

        func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
            guard let circle = overlay as? GMSCircle, let cell = cellsByCircle[ObjectIdentifier(circle)] else { return }
            onCellTap?(cell)
        }

        /// Circle radius in metres scales with the cell's station count so busier areas read as larger.
        static func radiusMetres(_ count: Int) -> CLLocationDistance {
            min(max(sqrt(Double(count)) * 3000, 6000), 45000)
        }
    }
}
