import MapKit
import UIKit

/// Custom map overlay renderer that draws trip routes with style variations
/// based on segment confidence and type (solid for road-snapped, dashed for
/// uncertain, faded for poor signal areas).
///
/// Usage with MKMapView:
/// ```swift
/// func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
///     if let styledPolyline = overlay as? StyledPolyline {
///         return TripRouteOverlayRenderer(styledPolyline: styledPolyline)
///     }
///     return MKOverlayRenderer(overlay: overlay)
/// }
/// ```
public final class TripRouteOverlayRenderer: MKPolylineRenderer {

    private let segmentStyle: TripRouteProcessor.SegmentStyle
    private let confidence: Double

    public init(styledPolyline: StyledPolyline) {
        self.segmentStyle = styledPolyline.style
        self.confidence = styledPolyline.confidence
        super.init(polyline: styledPolyline)

        configureAppearance()
    }

    private func configureAppearance() {
        lineWidth = 4.0

        switch segmentStyle {
        case .solid:
            strokeColor = UIColor.systemGreen.withAlphaComponent(0.9)
            lineDashPattern = nil

        case .dashed:
            strokeColor = UIColor.systemYellow.withAlphaComponent(0.7)
            lineDashPattern = [10, 6]

        case .dotted:
            strokeColor = UIColor.systemOrange.withAlphaComponent(0.6)
            lineDashPattern = [3, 5]

        case .faded:
            strokeColor = UIColor.systemGray.withAlphaComponent(0.3)
            lineDashPattern = nil
        }

        // Adjust opacity based on confidence
        if confidence < 0.5 {
            alpha = CGFloat(max(0.3, confidence))
        }

        lineJoin = .round
        lineCap = .round
    }
}

// MARK: - Styled Polyline

/// An MKPolyline subclass that carries styling metadata for the renderer.
public final class StyledPolyline: MKPolyline {

    private var _style: TripRouteProcessor.SegmentStyle = .solid
    private var _confidence: Double = 1.0

    public var style: TripRouteProcessor.SegmentStyle { _style }
    public var confidence: Double { _confidence }

    /// Creates a styled polyline from a route segment.
    public static func from(segment: TripRouteProcessor.RouteSegment) -> StyledPolyline {
        var coords = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: segment.polyline.pointCount
        )
        segment.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: segment.polyline.pointCount))

        let polyline = StyledPolyline(coordinates: coords, count: coords.count)
        polyline._style = segment.style
        polyline._confidence = segment.confidence
        return polyline
    }
}

// MARK: - Poor Signal Zone Circle Renderer

/// Renders a circular overlay for poor signal zones (parking garages, etc.)
public final class PoorSignalZoneRenderer: MKCircleRenderer {

    public override init(circle: MKCircle) {
        super.init(circle: circle)

        fillColor = UIColor.systemYellow.withAlphaComponent(0.15)
        strokeColor = UIColor.systemYellow.withAlphaComponent(0.5)
        lineWidth = 1.5
        lineDashPattern = [4, 4]
    }
}

// MARK: - Map View Integration Helper

/// Helper class that manages adding processed routes to an MKMapView
/// and provides the correct renderers for each overlay type.
public final class TripRouteMapManager: NSObject {

    private weak var mapView: MKMapView?
    private var currentOverlays: [MKOverlay] = []
    private var currentAnnotations: [MKAnnotation] = []

    public init(mapView: MKMapView) {
        self.mapView = mapView
        super.init()
    }

    /// Displays a processed route on the map, replacing any previous route.
    public func displayRoute(_ route: TripRouteProcessor.ProcessedRoute) {
        guard let mapView = mapView else { return }

        // Remove previous overlays
        clearRoute()

        // Add road segments as styled polylines
        for segment in route.roadSegments {
            let styledPolyline = StyledPolyline.from(segment: segment)
            mapView.addOverlay(styledPolyline, level: .aboveRoads)
            currentOverlays.append(styledPolyline)
        }

        // Add poor signal zone overlays
        for zoneInfo in route.poorSignalZones {
            if let overlay = zoneInfo.overlay {
                mapView.addOverlay(overlay, level: .aboveRoads)
                currentOverlays.append(overlay)
            }
            if let annotation = zoneInfo.annotation {
                mapView.addAnnotation(annotation)
                currentAnnotations.append(annotation)
            }
        }

        // Zoom to fit the route
        mapView.setRegion(route.boundingRegion, animated: true)
    }

    /// Removes the current route from the map.
    public func clearRoute() {
        guard let mapView = mapView else { return }

        mapView.removeOverlays(currentOverlays)
        mapView.removeAnnotations(currentAnnotations)
        currentOverlays.removeAll()
        currentAnnotations.removeAll()
    }

    /// Returns the correct renderer for a given overlay.
    /// Call this from your MKMapViewDelegate's `mapView(_:rendererFor:)` method.
    public func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        if let styledPolyline = overlay as? StyledPolyline {
            return TripRouteOverlayRenderer(styledPolyline: styledPolyline)
        }

        if let circle = overlay as? MKCircle {
            return PoorSignalZoneRenderer(circle: circle)
        }

        // For plain MKPolyline from poor signal zones (dashed connections)
        if let polyline = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.strokeColor = UIColor.systemYellow.withAlphaComponent(0.5)
            renderer.lineWidth = 3.0
            renderer.lineDashPattern = [8, 6]
            renderer.lineJoin = .round
            renderer.lineCap = .round
            return renderer
        }

        return nil
    }
}

// MARK: - SwiftUI Integration

#if canImport(SwiftUI)
import SwiftUI

/// SwiftUI wrapper for displaying a processed trip route on a map.
///
/// Usage:
/// ```swift
/// TripRouteMapView(rawLocations: trip.locations)
///     .frame(height: 300)
/// ```
@available(iOS 17.0, *)
public struct TripRouteMapView: UIViewRepresentable {

    private let rawLocations: [CLLocation]
    private let filterConfig: GPSLocationFilter.Configuration
    private let snapConfig: RoadSnappingService.Configuration
    private let signalConfig: PoorSignalDetector.Configuration

    public init(
        rawLocations: [CLLocation],
        filterConfig: GPSLocationFilter.Configuration = .init(),
        snapConfig: RoadSnappingService.Configuration = .init(),
        signalConfig: PoorSignalDetector.Configuration = .init()
    ) {
        self.rawLocations = rawLocations
        self.filterConfig = filterConfig
        self.snapConfig = snapConfig
        self.signalConfig = signalConfig
    }

    public func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.overrideUserInterfaceStyle = .dark
        mapView.mapType = .standard
        mapView.isZoomEnabled = true
        mapView.isScrollEnabled = true
        return mapView
    }

    public func updateUIView(_ mapView: MKMapView, context: Context) {
        let manager = TripRouteMapManager(mapView: mapView)
        context.coordinator.routeManager = manager

        Task {
            let processor = TripRouteProcessor(
                filterConfig: filterConfig,
                snapConfig: snapConfig,
                signalConfig: signalConfig
            )

            do {
                let route = try await processor.processTrip(rawLocations: rawLocations)
                await MainActor.run {
                    manager.displayRoute(route)
                }
            } catch {
                // Fallback: display filtered points without road snapping
                let filter = GPSLocationFilter(configuration: filterConfig)
                let filtered = filter.filterFlat(locations: rawLocations)
                let coords = filtered.map { $0.coordinate }
                if coords.count >= 2 {
                    let polyline = MKPolyline(coordinates: coords, count: coords.count)
                    await MainActor.run {
                        mapView.addOverlay(polyline, level: .aboveRoads)
                        let region = MKCoordinateRegion(polyline.boundingMapRect)
                        mapView.setRegion(region, animated: true)
                    }
                }
            }
        }
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject, MKMapViewDelegate {
        var routeManager: TripRouteMapManager?

        public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let renderer = routeManager?.renderer(for: overlay) {
                return renderer
            }

            // Default polyline renderer
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemGreen
                renderer.lineWidth = 3.0
                return renderer
            }

            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
#endif
