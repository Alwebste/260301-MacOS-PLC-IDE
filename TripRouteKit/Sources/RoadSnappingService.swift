import CoreLocation
import MapKit
import Foundation

/// Snaps GPS coordinates to actual road geometry using MapKit's directions API.
///
/// Instead of drawing straight lines between GPS points (which cut through
/// buildings and off-road areas), this service requests actual driving routes
/// between points so the displayed path follows real roads.
///
/// Strategies:
/// 1. **Chunk-based snapping**: Groups GPS points into chunks and requests
///    driving directions between chunk endpoints, producing road-following polylines.
/// 2. **Waypoint insertion**: For longer segments, inserts intermediate waypoints
///    to keep the route adherent to the actual path taken.
/// 3. **Caching**: Caches snapped segments to avoid redundant API calls.
public final class RoadSnappingService {

    // MARK: - Configuration

    public struct Configuration {
        /// Maximum number of waypoints per MKDirections request.
        /// Apple limits this; we chunk accordingly.
        /// Default: 5 waypoints per request
        public var maxWaypointsPerRequest: Int = 5

        /// Maximum distance in meters between consecutive points before
        /// we insert intermediate waypoints for better road adherence.
        /// Default: 200m
        public var maxSegmentDistance: CLLocationDistance = 200.0

        /// Minimum distance between points to bother snapping.
        /// Very short segments don't benefit from road snapping.
        /// Default: 20m
        public var minSnapDistance: CLLocationDistance = 20.0

        /// Whether to fall back to filtered GPS points when road snapping fails.
        /// Default: true
        public var fallbackToRawOnFailure: Bool = true

        /// Transport type for directions requests.
        /// Default: .automobile
        public var transportType: MKDirectionsTransportType = .automobile

        /// Maximum concurrent directions requests.
        /// Default: 3
        public var maxConcurrentRequests: Int = 3

        public init() {}
    }

    private let config: Configuration
    private let cache = NSCache<NSString, CachedRoute>()

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    // MARK: - Public API

    /// Snaps an array of filtered GPS locations to roads.
    ///
    /// - Parameter locations: Pre-filtered GPS locations (run through GPSLocationFilter first)
    /// - Returns: Array of road-snapped coordinates forming a continuous path
    public func snapToRoads(locations: [CLLocation]) async throws -> [CLLocationCoordinate2D] {
        guard locations.count >= 2 else {
            return locations.map { $0.coordinate }
        }

        // Select key waypoints that represent the route skeleton
        let waypoints = selectKeyWaypoints(from: locations)

        // Chunk waypoints into groups for directions requests
        let chunks = chunkWaypoints(waypoints)

        // Request directions for each chunk, combining results
        var allCoordinates: [CLLocationCoordinate2D] = []

        for chunk in chunks {
            do {
                let routeCoords = try await requestRoute(for: chunk)
                // Avoid duplicating the connection point between chunks
                if !allCoordinates.isEmpty && !routeCoords.isEmpty {
                    allCoordinates.append(contentsOf: routeCoords.dropFirst())
                } else {
                    allCoordinates.append(contentsOf: routeCoords)
                }
            } catch {
                if config.fallbackToRawOnFailure {
                    // Fall back to straight lines for this chunk
                    let fallback = chunk.map { $0.coordinate }
                    if !allCoordinates.isEmpty && !fallback.isEmpty {
                        allCoordinates.append(contentsOf: fallback.dropFirst())
                    } else {
                        allCoordinates.append(contentsOf: fallback)
                    }
                } else {
                    throw error
                }
            }
        }

        return allCoordinates
    }

    /// Snaps multiple segments (from GPSLocationFilter) to roads independently.
    public func snapSegments(_ segments: [[CLLocation]]) async throws -> [[CLLocationCoordinate2D]] {
        // Process segments concurrently with limited parallelism
        return try await withThrowingTaskGroup(of: (Int, [CLLocationCoordinate2D]).self) { group in
            var results: [(Int, [CLLocationCoordinate2D])] = []

            for (index, segment) in segments.enumerated() {
                group.addTask {
                    let coords = try await self.snapToRoads(locations: segment)
                    return (index, coords)
                }
            }

            for try await result in group {
                results.append(result)
            }

            return results.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - Waypoint Selection

    /// Selects key waypoints from the location array that capture the route shape
    /// without overwhelming the directions API.
    ///
    /// Uses Douglas-Peucker-like simplification combined with distance-based sampling
    /// to pick the most important points.
    private func selectKeyWaypoints(from locations: [CLLocation]) -> [CLLocation] {
        guard locations.count > config.maxWaypointsPerRequest else {
            return locations
        }

        var waypoints: [CLLocation] = [locations[0]]
        var accumulatedDistance: CLLocationDistance = 0

        for i in 1..<locations.count {
            let distance = locations[i].distance(from: locations[i - 1])
            accumulatedDistance += distance

            // Include point if we've traveled enough distance
            if accumulatedDistance >= config.maxSegmentDistance {
                waypoints.append(locations[i])
                accumulatedDistance = 0
            }
        }

        // Always include the last point
        if let last = locations.last, waypoints.last != last {
            waypoints.append(last)
        }

        // Also include significant direction changes
        let withTurns = insertTurnPoints(locations: locations, existingWaypoints: waypoints)

        return withTurns
    }

    /// Inserts points where the bearing changes significantly (turns, curves).
    /// These are critical for road snapping accuracy.
    private func insertTurnPoints(locations: [CLLocation], existingWaypoints: [CLLocation]) -> [CLLocation] {
        let minBearingChange: Double = 30.0 // degrees
        var combined = Set(existingWaypoints.map { ObjectIdentifier($0) })
        var result = existingWaypoints

        for i in 1..<(locations.count - 1) {
            let bearing1 = bearing(from: locations[i - 1].coordinate, to: locations[i].coordinate)
            let bearing2 = bearing(from: locations[i].coordinate, to: locations[i + 1].coordinate)
            let change = abs(normalizeBearing(bearing2 - bearing1))

            if change >= minBearingChange && !combined.contains(ObjectIdentifier(locations[i])) {
                result.append(locations[i])
                combined.insert(ObjectIdentifier(locations[i]))
            }
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Route Chunking

    /// Splits waypoints into chunks that fit within the MKDirections waypoint limit.
    private func chunkWaypoints(_ waypoints: [CLLocation]) -> [[CLLocation]] {
        let chunkSize = config.maxWaypointsPerRequest
        guard waypoints.count > chunkSize else {
            return [waypoints]
        }

        var chunks: [[CLLocation]] = []
        var startIndex = 0

        while startIndex < waypoints.count - 1 {
            let endIndex = min(startIndex + chunkSize, waypoints.count)
            let chunk = Array(waypoints[startIndex..<endIndex])
            chunks.append(chunk)
            // Overlap by 1 point to maintain continuity
            startIndex = endIndex - 1
        }

        return chunks
    }

    // MARK: - Directions Request

    /// Requests driving directions between waypoints and returns the route coordinates.
    private func requestRoute(for waypoints: [CLLocation]) async throws -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else {
            return waypoints.map { $0.coordinate }
        }

        // Check cache
        let cacheKey = cacheKeyFor(waypoints)
        if let cached = cache.object(forKey: cacheKey as NSString) {
            return cached.coordinates
        }

        let source = MKMapItem(placemark: MKPlacemark(coordinate: waypoints.first!.coordinate))
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: waypoints.last!.coordinate))

        let request = MKDirections.Request()
        request.source = source
        request.destination = destination
        request.transportType = config.transportType
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let route = response.routes.first else {
            // No route found, return raw coordinates
            return waypoints.map { $0.coordinate }
        }

        // Extract coordinates from the route polyline
        let coordinates = extractCoordinates(from: route.polyline)

        // Cache the result
        let cached = CachedRoute(coordinates: coordinates)
        cache.setObject(cached, forKey: cacheKey as NSString)

        return coordinates
    }

    /// Extracts CLLocationCoordinate2D array from an MKPolyline.
    private func extractCoordinates(from polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        let count = polyline.pointCount
        var coords = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: count)
        polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
        return coords
    }

    // MARK: - Bearing Calculation

    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let lat1 = start.latitude.degreesToRadians
        let lat2 = end.latitude.degreesToRadians
        let dLon = (end.longitude - start.longitude).degreesToRadians

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x).radiansToDegrees

        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    private func normalizeBearing(_ bearing: Double) -> Double {
        var b = bearing.truncatingRemainder(dividingBy: 360)
        if b > 180 { b -= 360 }
        if b < -180 { b += 360 }
        return b
    }

    // MARK: - Caching

    private func cacheKeyFor(_ waypoints: [CLLocation]) -> String {
        waypoints.map { "\($0.coordinate.latitude),\($0.coordinate.longitude)" }.joined(separator: "|")
    }
}

// MARK: - Cache Object

private final class CachedRoute: NSObject {
    let coordinates: [CLLocationCoordinate2D]

    init(coordinates: [CLLocationCoordinate2D]) {
        self.coordinates = coordinates
    }
}

// MARK: - Helpers

private extension Double {
    var degreesToRadians: Double { self * .pi / 180.0 }
    var radiansToDegrees: Double { self * 180.0 / .pi }
}
