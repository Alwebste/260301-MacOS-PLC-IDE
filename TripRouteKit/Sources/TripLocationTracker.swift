import CoreLocation
import Foundation

/// Enhanced location tracker that applies real-time filtering during trip recording.
///
/// Key improvements over raw CLLocationManager recording:
/// - Configures CLLocationManager with optimal settings for vehicle tracking
/// - Applies real-time quality checks on incoming locations
/// - Detects and flags poor signal conditions as they happen
/// - Maintains a rolling buffer for smoothing
///
/// Usage:
/// ```swift
/// let tracker = TripLocationTracker()
/// tracker.startTrip()
/// // ... driving ...
/// let locations = tracker.stopTrip()
/// let processor = TripRouteProcessor()
/// let route = try await processor.processTrip(rawLocations: locations)
/// ```
public final class TripLocationTracker: NSObject, CLLocationManagerDelegate {

    // MARK: - Configuration

    public struct Configuration {
        /// Desired accuracy for location tracking.
        /// Default: kCLLocationAccuracyBestForNavigation
        public var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBestForNavigation

        /// Minimum distance change to receive an update (meters).
        /// Default: 5m (balances battery vs precision)
        public var distanceFilter: CLLocationDistance = 5.0

        /// Activity type hint for the location manager.
        /// Default: .automotiveNavigation
        public var activityType: CLActivityType = .automotiveNavigation

        /// Whether to allow background location updates.
        /// Default: true
        public var allowsBackgroundUpdates: Bool = true

        /// Whether to pause updates automatically in poor conditions.
        /// Default: false (we handle poor signal ourselves)
        public var pausesAutomatically: Bool = false

        /// Real-time accuracy threshold - locations worse than this are flagged
        /// but still recorded for post-processing.
        /// Default: 50m
        public var realtimeAccuracyThreshold: CLLocationAccuracy = 50.0

        /// Maximum age of a location before it's considered stale (seconds).
        /// Default: 10 seconds
        public var maxLocationAge: TimeInterval = 10.0

        public init() {}
    }

    // MARK: - State

    public enum TrackingState {
        case idle
        case tracking
        case poorSignal
        case backgrounded
    }

    // MARK: - Properties

    private let locationManager = CLLocationManager()
    private let config: Configuration

    /// All recorded locations for the current trip (raw, unfiltered).
    private(set) public var recordedLocations: [CLLocation] = []

    /// Current tracking state.
    private(set) public var state: TrackingState = .idle

    /// Callback for real-time location updates (for live map display).
    public var onLocationUpdate: ((CLLocation, TrackingState) -> Void)?

    /// Callback when poor signal is detected in real time.
    public var onPoorSignalDetected: ((CLLocationAccuracy) -> Void)?

    /// Callback when signal quality recovers.
    public var onSignalRecovered: (() -> Void)?

    // Rolling buffer for real-time smoothing
    private var recentLocations: [CLLocation] = []
    private let bufferSize = 5
    private var poorSignalStartTime: Date?

    // MARK: - Initialization

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        super.init()

        locationManager.delegate = self
        locationManager.desiredAccuracy = config.desiredAccuracy
        locationManager.distanceFilter = config.distanceFilter
        locationManager.activityType = config.activityType
        locationManager.allowsBackgroundLocationUpdates = config.allowsBackgroundUpdates
        locationManager.pausesLocationUpdatesAutomatically = config.pausesAutomatically

        // Show blue indicator dot to user
        locationManager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Trip Lifecycle

    /// Starts recording a new trip.
    public func startTrip() {
        recordedLocations.removeAll()
        recentLocations.removeAll()
        poorSignalStartTime = nil
        state = .tracking

        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }

    /// Stops recording and returns all captured locations.
    @discardableResult
    public func stopTrip() -> [CLLocation] {
        locationManager.stopUpdatingLocation()
        state = .idle

        let locations = recordedLocations
        return locations
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations {
            // Skip stale locations (from system cache)
            let age = abs(location.timestamp.timeIntervalSinceNow)
            guard age <= config.maxLocationAge else { continue }

            // Always record the raw location for post-processing
            recordedLocations.append(location)

            // Update rolling buffer
            recentLocations.append(location)
            if recentLocations.count > bufferSize {
                recentLocations.removeFirst()
            }

            // Real-time signal quality check
            updateSignalState(for: location)

            // Notify listener
            onLocationUpdate?(location, state)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                state = .idle
                locationManager.stopUpdatingLocation()
            case .network:
                // Network issue - keep recording, signal may recover
                state = .poorSignal
            default:
                break
            }
        }
    }

    // MARK: - Real-time Signal Analysis

    private func updateSignalState(for location: CLLocation) {
        if location.horizontalAccuracy > config.realtimeAccuracyThreshold
            || location.horizontalAccuracy < 0 {
            // Poor signal
            if state != .poorSignal {
                state = .poorSignal
                poorSignalStartTime = Date()
                onPoorSignalDetected?(location.horizontalAccuracy)
            }
        } else {
            // Good signal
            if state == .poorSignal {
                state = .tracking
                poorSignalStartTime = nil
                onSignalRecovered?()
            }
        }
    }
}
