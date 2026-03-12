import CoreLocation
import MapKit
import Foundation

/// Orchestrates the full pipeline for converting raw GPS trip data
/// into clean, road-adherent map overlays.
///
/// Pipeline:
/// 1. Filter raw GPS points (remove noise, outliers, drift)
/// 2. Detect poor signal zones (garages, apartments, tunnels)
/// 3. Snap good segments to roads via MapKit Directions
/// 4. Build map overlays with appropriate styling per segment type
public final class TripRouteProcessor {

    // MARK: - Types

    /// A processed route ready for map display.
    public struct ProcessedRoute {
        /// Road-snapped polyline segments for the main route
        public let roadSegments: [RouteSegment]

        /// Poor signal zones with display recommendations
        public let poorSignalZones: [PoorSignalDisplayInfo]

        /// The overall bounding region for the route
        public let boundingRegion: MKCoordinateRegion

        /// Processing metadata
        public let metadata: ProcessingMetadata
    }

    /// A single displayable route segment.
    public struct RouteSegment {
        /// The polyline to render on the map
        public let polyline: MKPolyline

        /// How this segment should be styled
        public let style: SegmentStyle

        /// Confidence level in this segment's accuracy (0.0 to 1.0)
        public let confidence: Double
    }

    /// Styling information for a route segment.
    public enum SegmentStyle {
        /// Solid line - high confidence, road-snapped
        case solid

        /// Dashed line - moderate confidence, interpolated/uncertain
        case dashed

        /// Dotted line - low confidence, raw GPS fallback
        case dotted

        /// Faded/transparent - very low confidence area
        case faded
    }

    /// Display information for a poor signal zone.
    public struct PoorSignalDisplayInfo {
        public let zone: PoorSignalDetector.PoorSignalZone
        public let strategy: PoorSignalDetector.DisplayStrategy
        public let overlay: MKOverlay?
        public let annotation: MKAnnotation?
    }

    /// Metadata about the processing pipeline.
    public struct ProcessingMetadata {
        public let rawPointCount: Int
        public let filteredPointCount: Int
        public let segmentCount: Int
        public let poorSignalZoneCount: Int
        public let roadSnappedSegments: Int
        public let fallbackSegments: Int
        public let processingTime: TimeInterval
    }

    // MARK: - Properties

    private let locationFilter: GPSLocationFilter
    private let roadSnapper: RoadSnappingService
    private let signalDetector: PoorSignalDetector

    // MARK: - Initialization

    public init(
        filterConfig: GPSLocationFilter.Configuration = .init(),
        snapConfig: RoadSnappingService.Configuration = .init(),
        signalConfig: PoorSignalDetector.Configuration = .init()
    ) {
        self.locationFilter = GPSLocationFilter(configuration: filterConfig)
        self.roadSnapper = RoadSnappingService(configuration: snapConfig)
        self.signalDetector = PoorSignalDetector(configuration: signalConfig)
    }

    // MARK: - Processing

    /// Processes raw trip GPS data into a display-ready route.
    ///
    /// - Parameter rawLocations: Raw CLLocation array from trip recording
    /// - Returns: A ProcessedRoute ready for map display
    public func processTrip(rawLocations: [CLLocation]) async throws -> ProcessedRoute {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Step 1: Detect poor signal zones on raw data
        let poorSignalZones = signalDetector.detectPoorSignalZones(locations: rawLocations)

        // Step 2: Filter GPS noise
        let filteredSegments = locationFilter.filter(locations: rawLocations)
        let filteredCount = filteredSegments.flatMap { $0 }.count

        // Step 3: Snap to roads
        var roadSegments: [RouteSegment] = []
        var snappedCount = 0
        var fallbackCount = 0

        for segment in filteredSegments {
            guard segment.count >= 2 else { continue }

            do {
                let snappedCoords = try await roadSnapper.snapToRoads(locations: segment)
                if snappedCoords.count >= 2 {
                    let polyline = MKPolyline(
                        coordinates: snappedCoords,
                        count: snappedCoords.count
                    )
                    roadSegments.append(RouteSegment(
                        polyline: polyline,
                        style: .solid,
                        confidence: 0.95
                    ))
                    snappedCount += 1
                }
            } catch {
                // Fallback: use filtered points directly
                let coords = segment.map { $0.coordinate }
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                roadSegments.append(RouteSegment(
                    polyline: polyline,
                    style: .dotted,
                    confidence: 0.5
                ))
                fallbackCount += 1
            }
        }

        // Step 4: Build poor signal zone overlays
        let poorSignalDisplayInfos = buildPoorSignalOverlays(zones: poorSignalZones)

        // Step 5: Calculate bounding region
        let allCoords = roadSegments.flatMap { segment -> [CLLocationCoordinate2D] in
            var coords = [CLLocationCoordinate2D](
                repeating: CLLocationCoordinate2D(),
                count: segment.polyline.pointCount
            )
            segment.polyline.getCoordinates(&coords, range: NSRange(location: 0, length: segment.polyline.pointCount))
            return coords
        }
        let boundingRegion = computeBoundingRegion(for: allCoords)

        // Step 6: Connect segments with appropriate transition overlays
        let connectors = buildSegmentConnectors(segments: filteredSegments)
        roadSegments.append(contentsOf: connectors)

        let processingTime = CFAbsoluteTimeGetCurrent() - startTime

        return ProcessedRoute(
            roadSegments: roadSegments,
            poorSignalZones: poorSignalDisplayInfos,
            boundingRegion: boundingRegion,
            metadata: ProcessingMetadata(
                rawPointCount: rawLocations.count,
                filteredPointCount: filteredCount,
                segmentCount: roadSegments.count,
                poorSignalZoneCount: poorSignalZones.count,
                roadSnappedSegments: snappedCount,
                fallbackSegments: fallbackCount,
                processingTime: processingTime
            )
        )
    }

    // MARK: - Poor Signal Overlays

    private func buildPoorSignalOverlays(zones: [PoorSignalDetector.PoorSignalZone]) -> [PoorSignalDisplayInfo] {
        return zones.map { zone in
            let strategy = signalDetector.recommendDisplayStrategy(for: zone)

            var overlay: MKOverlay?
            var annotation: MKAnnotation?

            switch strategy {
            case .snapToRoadDirect, .dashedConnection:
                if let exit = zone.exitLocation {
                    let coords = [zone.entryLocation.coordinate, exit.coordinate]
                    overlay = MKPolyline(coordinates: coords, count: 2)
                }

            case .regionMarker:
                let center = zone.entryLocation.coordinate
                overlay = MKCircle(center: center, radius: 30)
                let pin = MKPointAnnotation()
                pin.coordinate = center
                pin.title = zone.estimatedContext == .parkingStructure ? "Parking" : "Signal Lost"
                annotation = pin

            case .reducedOpacity:
                let coords = zone.rawLocations.map { $0.coordinate }
                if coords.count >= 2 {
                    overlay = MKPolyline(coordinates: coords, count: coords.count)
                }

            case .omit:
                break
            }

            return PoorSignalDisplayInfo(
                zone: zone,
                strategy: strategy,
                overlay: overlay,
                annotation: annotation
            )
        }
    }

    // MARK: - Segment Connectors

    /// Builds dashed connectors between separate segments (bridging gaps from signal loss).
    private func buildSegmentConnectors(segments: [[CLLocation]]) -> [RouteSegment] {
        guard segments.count >= 2 else { return [] }

        var connectors: [RouteSegment] = []

        for i in 0..<(segments.count - 1) {
            guard let end = segments[i].last, let start = segments[i + 1].first else { continue }

            let coords = [end.coordinate, start.coordinate]
            let polyline = MKPolyline(coordinates: coords, count: 2)

            connectors.append(RouteSegment(
                polyline: polyline,
                style: .dashed,
                confidence: 0.3
            ))
        }

        return connectors
    }

    // MARK: - Bounding Region

    private func computeBoundingRegion(for coordinates: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        guard !coordinates.isEmpty else {
            return MKCoordinateRegion()
        }

        var minLat = coordinates[0].latitude
        var maxLat = coordinates[0].latitude
        var minLon = coordinates[0].longitude
        var maxLon = coordinates[0].longitude

        for coord in coordinates {
            minLat = min(minLat, coord.latitude)
            maxLat = max(maxLat, coord.latitude)
            minLon = min(minLon, coord.longitude)
            maxLon = max(maxLon, coord.longitude)
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.3,
            longitudeDelta: (maxLon - minLon) * 1.3
        )

        return MKCoordinateRegion(center: center, span: span)
    }
}
