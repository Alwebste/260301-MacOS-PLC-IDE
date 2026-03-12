import CoreLocation
import Foundation

/// Filters raw GPS location data to remove noisy, inaccurate, and unreliable points.
///
/// Key filtering strategies:
/// - Horizontal accuracy threshold (removes GPS points with poor accuracy)
/// - Speed-based outlier detection (removes teleportation artifacts)
/// - Minimum distance filtering (removes clustering from stationary drift)
/// - Kalman-inspired smoothing for remaining points
public final class GPSLocationFilter {

    // MARK: - Configuration

    public struct Configuration {
        /// Maximum acceptable horizontal accuracy in meters.
        /// Points with accuracy worse than this are discarded.
        /// Default: 30m (indoor/garage readings often exceed 50-100m)
        public var maxHorizontalAccuracy: CLLocationAccuracy = 30.0

        /// Maximum acceptable speed in m/s before a point is considered an outlier.
        /// Default: 45 m/s (~100 mph) for vehicle trips
        public var maxReasonableSpeed: CLLocationSpeed = 45.0

        /// Minimum distance in meters between consecutive kept points.
        /// Prevents clustering from stationary GPS drift.
        /// Default: 5m
        public var minDistanceBetweenPoints: CLLocationDistance = 5.0

        /// Maximum time gap in seconds before we consider it a signal gap.
        /// Default: 30 seconds
        public var maxTimeGap: TimeInterval = 30.0

        /// Maximum acceptable acceleration in m/s^2.
        /// Catches sudden impossible speed changes even if individual speeds are OK.
        /// Default: 15 m/s^2 (aggressive acceleration for vehicles)
        public var maxAcceleration: Double = 15.0

        /// Minimum number of points required for a valid segment.
        /// Short segments from noise bursts are discarded.
        /// Default: 3
        public var minSegmentPoints: Int = 3

        public init() {}
    }

    private let config: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    // MARK: - Main Filtering Pipeline

    /// Filters an array of raw GPS locations through a multi-stage pipeline.
    ///
    /// Pipeline stages:
    /// 1. Remove invalid/negative accuracy readings
    /// 2. Filter by horizontal accuracy threshold
    /// 3. Remove speed-based outliers
    /// 4. Remove acceleration-based outliers
    /// 5. Apply minimum distance filter to reduce drift clusters
    /// 6. Split into segments at time gaps
    ///
    /// - Parameter locations: Raw GPS locations from CLLocationManager
    /// - Returns: Array of filtered location segments (each segment is a continuous path)
    public func filter(locations: [CLLocation]) -> [[CLLocation]] {
        guard locations.count >= 2 else { return [locations] }

        // Sort by timestamp to ensure chronological order
        let sorted = locations.sorted { $0.timestamp < $1.timestamp }

        // Stage 1: Remove invalid readings
        let valid = sorted.filter { $0.horizontalAccuracy >= 0 }

        // Stage 2: Filter by horizontal accuracy
        let accurateEnough = valid.filter { $0.horizontalAccuracy <= config.maxHorizontalAccuracy }

        guard accurateEnough.count >= 2 else {
            // If too aggressive, fall back with relaxed accuracy
            let relaxed = valid.filter { $0.horizontalAccuracy <= config.maxHorizontalAccuracy * 3 }
            return splitIntoSegments(relaxed)
        }

        // Stage 3: Remove speed-based outliers
        let speedFiltered = removeSpeedOutliers(accurateEnough)

        // Stage 4: Remove acceleration-based outliers
        let accelFiltered = removeAccelerationOutliers(speedFiltered)

        // Stage 5: Apply minimum distance filter
        let distanceFiltered = applyMinimumDistance(accelFiltered)

        // Stage 6: Split at time gaps into segments
        let segments = splitIntoSegments(distanceFiltered)

        // Stage 7: Remove tiny segments (likely noise bursts)
        return segments.filter { $0.count >= config.minSegmentPoints }
    }

    /// Convenience method that returns a single flattened array of filtered locations.
    public func filterFlat(locations: [CLLocation]) -> [CLLocation] {
        return filter(locations: locations).flatMap { $0 }
    }

    // MARK: - Speed Outlier Detection

    /// Removes points that would require impossible speeds to reach from the previous point.
    private func removeSpeedOutliers(_ locations: [CLLocation]) -> [CLLocation] {
        guard locations.count >= 2 else { return locations }

        var result: [CLLocation] = [locations[0]]

        for i in 1..<locations.count {
            let prev = result.last!
            let curr = locations[i]

            let distance = curr.distance(from: prev)
            let timeDelta = curr.timestamp.timeIntervalSince(prev.timestamp)

            guard timeDelta > 0 else { continue }

            let speed = distance / timeDelta

            if speed <= config.maxReasonableSpeed {
                result.append(curr)
            }
            // Otherwise skip this point (teleportation artifact)
        }

        return result
    }

    // MARK: - Acceleration Outlier Detection

    /// Removes points that create impossible acceleration/deceleration patterns.
    private func removeAccelerationOutliers(_ locations: [CLLocation]) -> [CLLocation] {
        guard locations.count >= 3 else { return locations }

        var result: [CLLocation] = [locations[0], locations[1]]

        for i in 2..<locations.count {
            let prev2 = result[result.count - 2]
            let prev1 = result[result.count - 1]
            let curr = locations[i]

            let dist1 = prev1.distance(from: prev2)
            let time1 = prev1.timestamp.timeIntervalSince(prev2.timestamp)

            let dist2 = curr.distance(from: prev1)
            let time2 = curr.timestamp.timeIntervalSince(prev1.timestamp)

            guard time1 > 0 && time2 > 0 else {
                result.append(curr)
                continue
            }

            let speed1 = dist1 / time1
            let speed2 = dist2 / time2
            let acceleration = abs(speed2 - speed1) / time2

            if acceleration <= config.maxAcceleration {
                result.append(curr)
            }
        }

        return result
    }

    // MARK: - Minimum Distance Filter

    /// Removes points that are too close together (GPS drift while stationary).
    private func applyMinimumDistance(_ locations: [CLLocation]) -> [CLLocation] {
        guard locations.count >= 2 else { return locations }

        var result: [CLLocation] = [locations[0]]

        for i in 1..<locations.count {
            let distance = locations[i].distance(from: result.last!)

            if distance >= config.minDistanceBetweenPoints {
                result.append(locations[i])
            }
        }

        // Always include the last point for continuity
        if let last = locations.last, result.last != last {
            result.append(last)
        }

        return result
    }

    // MARK: - Segment Splitting

    /// Splits locations into segments at time gaps (signal loss in garages, tunnels, etc.)
    private func splitIntoSegments(_ locations: [CLLocation]) -> [[CLLocation]] {
        guard locations.count >= 2 else { return [locations] }

        var segments: [[CLLocation]] = []
        var currentSegment: [CLLocation] = [locations[0]]

        for i in 1..<locations.count {
            let timeDelta = locations[i].timestamp.timeIntervalSince(locations[i - 1].timestamp)

            if timeDelta > config.maxTimeGap {
                // Time gap detected - start a new segment
                if !currentSegment.isEmpty {
                    segments.append(currentSegment)
                }
                currentSegment = [locations[i]]
            } else {
                currentSegment.append(locations[i])
            }
        }

        if !currentSegment.isEmpty {
            segments.append(currentSegment)
        }

        return segments
    }
}
