import CoreLocation
import Foundation

/// Detects and handles areas of poor GPS signal such as parking garages,
/// underground structures, apartment buildings, and urban canyons.
///
/// Poor GPS signal manifests as:
/// - High horizontal accuracy values (>50m)
/// - Rapid oscillation of position (GPS "wandering")
/// - Sudden jumps in position that don't match vehicle dynamics
/// - Signal loss gaps (no readings for extended periods)
///
/// This detector identifies these zones and provides strategies for
/// handling them in route display.
public final class PoorSignalDetector {

    // MARK: - Types

    /// Represents a detected zone of poor GPS signal.
    public struct PoorSignalZone {
        /// The entry point (last reliable location before signal degradation)
        public let entryLocation: CLLocation

        /// The exit point (first reliable location after signal recovery)
        public let exitLocation: CLLocation?

        /// All raw locations within this poor signal zone
        public let rawLocations: [CLLocation]

        /// The type of signal degradation detected
        public let type: DegradationType

        /// Estimated actual path type (for display hints)
        public let estimatedContext: LocationContext

        /// Duration of the poor signal zone
        public var duration: TimeInterval {
            guard let exit = exitLocation else {
                return rawLocations.last?.timestamp.timeIntervalSince(entryLocation.timestamp) ?? 0
            }
            return exit.timestamp.timeIntervalSince(entryLocation.timestamp)
        }
    }

    /// Type of GPS signal degradation.
    public enum DegradationType: String {
        /// GPS accuracy is poor but readings still coming in (garage, urban canyon)
        case degradedAccuracy

        /// Position is oscillating/wandering while likely stationary
        case stationaryDrift

        /// Complete signal loss (no readings for extended period)
        case signalLoss

        /// Mix of degraded readings and gaps
        case intermittent
    }

    /// Contextual hint about what's likely happening at this location.
    public enum LocationContext {
        /// Likely in a parking structure
        case parkingStructure

        /// Likely inside a building
        case indoorBuilding

        /// Likely in an urban canyon (tall buildings blocking signal)
        case urbanCanyon

        /// Likely in a tunnel or underpass
        case tunnel

        /// Unknown indoor/covered location
        case unknownIndoor

        /// Trip start/end (vehicle parked, walking to/from car)
        case tripEndpoint
    }

    /// Strategy recommendation for how to display this zone on the map.
    public enum DisplayStrategy {
        /// Snap entry and exit to nearest road, draw direct route between them
        case snapToRoadDirect

        /// Show a dashed/dotted line between entry and exit (signal uncertain)
        case dashedConnection

        /// Show a small circle/region marker at entry/exit instead of a line
        case regionMarker

        /// Omit this section entirely (too noisy to display)
        case omit

        /// Use the raw points but with reduced opacity (mildly degraded signal)
        case reducedOpacity
    }

    // MARK: - Configuration

    public struct Configuration {
        /// Horizontal accuracy threshold above which signal is considered "poor"
        /// Default: 40m
        public var poorAccuracyThreshold: CLLocationAccuracy = 40.0

        /// Horizontal accuracy threshold above which signal is considered "very poor"
        /// Default: 100m
        public var veryPoorAccuracyThreshold: CLLocationAccuracy = 100.0

        /// Time gap threshold for detecting signal loss
        /// Default: 15 seconds
        public var signalLossTimeThreshold: TimeInterval = 15.0

        /// Maximum wandering radius in meters to detect stationary drift.
        /// If all points in a window are within this radius, likely stationary drift.
        /// Default: 30m
        public var stationaryDriftRadius: CLLocationDistance = 30.0

        /// Minimum duration of poor signal to flag as a zone
        /// Default: 5 seconds
        public var minZoneDuration: TimeInterval = 5.0

        /// Whether to flag the first/last N seconds of a trip as potential
        /// parking/apartment zones. Default: 60 seconds
        public var tripEndpointDuration: TimeInterval = 60.0

        public init() {}
    }

    private let config: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
    }

    // MARK: - Detection

    /// Analyzes locations and identifies zones of poor GPS signal.
    public func detectPoorSignalZones(locations: [CLLocation]) -> [PoorSignalZone] {
        guard locations.count >= 2 else { return [] }

        let sorted = locations.sorted { $0.timestamp < $1.timestamp }
        var zones: [PoorSignalZone] = []

        // Detect trip start/end zones
        zones.append(contentsOf: detectTripEndpointZones(sorted))

        // Detect accuracy-based poor signal zones
        zones.append(contentsOf: detectAccuracyZones(sorted))

        // Detect signal loss gaps
        zones.append(contentsOf: detectSignalLossGaps(sorted))

        // Detect stationary drift
        zones.append(contentsOf: detectStationaryDrift(sorted))

        return zones
    }

    /// Recommends a display strategy for a given poor signal zone.
    public func recommendDisplayStrategy(for zone: PoorSignalZone) -> DisplayStrategy {
        switch zone.type {
        case .signalLoss:
            // Complete gap - connect with dashed line or snap to road
            if zone.duration < 60 {
                return .snapToRoadDirect
            } else {
                return .dashedConnection
            }

        case .stationaryDrift:
            // Parked/stationary - just show a marker
            if zone.estimatedContext == .parkingStructure || zone.estimatedContext == .tripEndpoint {
                return .regionMarker
            }
            return .omit

        case .degradedAccuracy:
            // Mildly degraded - reduce opacity to hint at uncertainty
            if zone.rawLocations.allSatisfy({ $0.horizontalAccuracy < config.veryPoorAccuracyThreshold }) {
                return .reducedOpacity
            }
            return .dashedConnection

        case .intermittent:
            return .dashedConnection
        }
    }

    // MARK: - Trip Endpoint Detection

    /// Detects the start and end of trips which are often in garages/apartments.
    private func detectTripEndpointZones(_ locations: [CLLocation]) -> [PoorSignalZone] {
        var zones: [PoorSignalZone] = []
        let tripStart = locations.first!.timestamp
        let tripEnd = locations.last!.timestamp

        // Check trip start
        let startLocations = locations.filter {
            $0.timestamp.timeIntervalSince(tripStart) <= config.tripEndpointDuration
        }
        if hasPoorSignalCharacteristics(startLocations) {
            let lastStartLoc = startLocations.last
            let exitLocation = locations.first {
                $0.timestamp.timeIntervalSince(tripStart) > config.tripEndpointDuration
                    && $0.horizontalAccuracy <= config.poorAccuracyThreshold
            }
            zones.append(PoorSignalZone(
                entryLocation: startLocations.first!,
                exitLocation: exitLocation ?? lastStartLoc,
                rawLocations: startLocations,
                type: classifyDegradation(startLocations),
                estimatedContext: .tripEndpoint
            ))
        }

        // Check trip end
        let endLocations = locations.filter {
            tripEnd.timeIntervalSince($0.timestamp) <= config.tripEndpointDuration
        }
        if hasPoorSignalCharacteristics(endLocations) {
            let entryLocation = locations.last {
                tripEnd.timeIntervalSince($0.timestamp) > config.tripEndpointDuration
                    && $0.horizontalAccuracy <= config.poorAccuracyThreshold
            }
            zones.append(PoorSignalZone(
                entryLocation: entryLocation ?? endLocations.first!,
                exitLocation: endLocations.last,
                rawLocations: endLocations,
                type: classifyDegradation(endLocations),
                estimatedContext: .tripEndpoint
            ))
        }

        return zones
    }

    // MARK: - Accuracy-Based Detection

    /// Finds continuous stretches where GPS accuracy is poor.
    private func detectAccuracyZones(_ locations: [CLLocation]) -> [PoorSignalZone] {
        var zones: [PoorSignalZone] = []
        var currentPoorStretch: [CLLocation] = []
        var lastGoodLocation: CLLocation?

        for location in locations {
            if location.horizontalAccuracy > config.poorAccuracyThreshold {
                if currentPoorStretch.isEmpty {
                    lastGoodLocation = locations.last { $0.timestamp < location.timestamp && $0.horizontalAccuracy <= config.poorAccuracyThreshold }
                }
                currentPoorStretch.append(location)
            } else {
                if !currentPoorStretch.isEmpty {
                    let entry = lastGoodLocation ?? currentPoorStretch.first!
                    let duration = (currentPoorStretch.last?.timestamp.timeIntervalSince(entry.timestamp)) ?? 0
                    if duration >= config.minZoneDuration {
                        zones.append(PoorSignalZone(
                            entryLocation: entry,
                            exitLocation: location,
                            rawLocations: currentPoorStretch,
                            type: .degradedAccuracy,
                            estimatedContext: estimateContext(for: currentPoorStretch)
                        ))
                    }
                    currentPoorStretch = []
                }
            }
        }

        // Handle trailing poor accuracy
        if !currentPoorStretch.isEmpty {
            let entry = lastGoodLocation ?? currentPoorStretch.first!
            zones.append(PoorSignalZone(
                entryLocation: entry,
                exitLocation: nil,
                rawLocations: currentPoorStretch,
                type: .degradedAccuracy,
                estimatedContext: estimateContext(for: currentPoorStretch)
            ))
        }

        return zones
    }

    // MARK: - Signal Loss Detection

    /// Detects gaps where no GPS readings were received.
    private func detectSignalLossGaps(_ locations: [CLLocation]) -> [PoorSignalZone] {
        var zones: [PoorSignalZone] = []

        for i in 1..<locations.count {
            let gap = locations[i].timestamp.timeIntervalSince(locations[i - 1].timestamp)
            if gap >= config.signalLossTimeThreshold {
                zones.append(PoorSignalZone(
                    entryLocation: locations[i - 1],
                    exitLocation: locations[i],
                    rawLocations: [],
                    type: .signalLoss,
                    estimatedContext: estimateContextFromGap(
                        entry: locations[i - 1],
                        exit: locations[i],
                        gapDuration: gap
                    )
                ))
            }
        }

        return zones
    }

    // MARK: - Stationary Drift Detection

    /// Detects clusters of points that wander within a small radius (GPS drift while parked).
    private func detectStationaryDrift(_ locations: [CLLocation]) -> [PoorSignalZone] {
        guard locations.count >= 5 else { return [] }

        var zones: [PoorSignalZone] = []
        let windowSize = 5
        var i = 0

        while i <= locations.count - windowSize {
            let window = Array(locations[i..<(i + windowSize)])
            let center = centroid(of: window)

            let maxDistance = window.map { $0.distance(from: center) }.max() ?? 0

            if maxDistance <= config.stationaryDriftRadius {
                // Found a drift cluster - extend it as far as possible
                var endIdx = i + windowSize
                while endIdx < locations.count {
                    let dist = locations[endIdx].distance(from: center)
                    if dist > config.stationaryDriftRadius { break }
                    endIdx += 1
                }

                let driftLocations = Array(locations[i..<endIdx])
                let duration = driftLocations.last!.timestamp.timeIntervalSince(driftLocations.first!.timestamp)

                if duration >= config.minZoneDuration {
                    let entryLoc = i > 0 ? locations[i - 1] : locations[i]
                    let exitLoc = endIdx < locations.count ? locations[endIdx] : nil

                    zones.append(PoorSignalZone(
                        entryLocation: entryLoc,
                        exitLocation: exitLoc,
                        rawLocations: driftLocations,
                        type: .stationaryDrift,
                        estimatedContext: .parkingStructure
                    ))
                }

                i = endIdx
            } else {
                i += 1
            }
        }

        return zones
    }

    // MARK: - Helpers

    private func hasPoorSignalCharacteristics(_ locations: [CLLocation]) -> Bool {
        guard locations.count >= 2 else { return false }

        let poorCount = locations.filter { $0.horizontalAccuracy > config.poorAccuracyThreshold }.count
        let poorRatio = Double(poorCount) / Double(locations.count)

        // If >40% of points have poor accuracy, consider it a poor signal zone
        return poorRatio > 0.4
    }

    private func classifyDegradation(_ locations: [CLLocation]) -> DegradationType {
        let poorAccuracyCount = locations.filter { $0.horizontalAccuracy > config.poorAccuracyThreshold }.count

        if poorAccuracyCount == locations.count {
            return .degradedAccuracy
        }

        // Check for gaps
        for i in 1..<locations.count {
            let gap = locations[i].timestamp.timeIntervalSince(locations[i - 1].timestamp)
            if gap >= config.signalLossTimeThreshold {
                return .intermittent
            }
        }

        return .degradedAccuracy
    }

    private func estimateContext(for locations: [CLLocation]) -> LocationContext {
        guard locations.count >= 2 else { return .unknownIndoor }

        let avgAccuracy = locations.map { $0.horizontalAccuracy }.reduce(0, +) / Double(locations.count)

        // Very poor accuracy + low speed suggests indoor/parking
        let avgSpeed = locations.compactMap { $0.speed >= 0 ? $0.speed : nil }
            .reduce(0, +) / max(Double(locations.filter { $0.speed >= 0 }.count), 1)

        if avgAccuracy > config.veryPoorAccuracyThreshold && avgSpeed < 2.0 {
            return .parkingStructure
        } else if avgAccuracy > config.veryPoorAccuracyThreshold {
            return .urbanCanyon
        } else {
            return .unknownIndoor
        }
    }

    private func estimateContextFromGap(entry: CLLocation, exit: CLLocation, gapDuration: TimeInterval) -> LocationContext {
        let distance = exit.distance(from: entry)

        if gapDuration > 120 && distance < 200 {
            // Long gap, short distance - likely parking/building
            return .parkingStructure
        } else if gapDuration < 30 && distance > 100 {
            // Short gap, medium distance - likely tunnel
            return .tunnel
        } else {
            return .unknownIndoor
        }
    }

    private func centroid(of locations: [CLLocation]) -> CLLocation {
        let lat = locations.map { $0.coordinate.latitude }.reduce(0, +) / Double(locations.count)
        let lon = locations.map { $0.coordinate.longitude }.reduce(0, +) / Double(locations.count)
        return CLLocation(latitude: lat, longitude: lon)
    }
}
