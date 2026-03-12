import CoreLocation
import Foundation

/// Coordinates auto trip detection, location tracking, and Live Activity
/// lifecycle into a single entry point.
///
/// This is the main integration class. Initialize once at app launch:
/// ```swift
/// // In AppDelegate or App init:
/// let coordinator = AutoTripCoordinator.shared
/// coordinator.startMonitoring()
///
/// // If launched from background:
/// coordinator.handleBackgroundLaunch(launchOptions: launchOptions)
/// ```
///
/// The coordinator automatically:
/// 1. Monitors for driving via AutoTripDetector
/// 2. Starts a Live Activity when a trip is detected
/// 3. Updates the Live Activity with distance/deduction as locations arrive
/// 4. Ends the Live Activity when the trip ends
/// 5. Feeds locations to TripLocationTracker for recording
public final class AutoTripCoordinator: NSObject {

    public static let shared = AutoTripCoordinator()

    // MARK: - Components

    private let detector: AutoTripDetector
    private let tracker: TripLocationTracker
    private let liveActivityManager: TripLiveActivityManager

    // MARK: - Trip State

    private var currentTripID: String?
    private var tripStartTime: Date?
    private var totalDistanceMeters: CLLocationDistance = 0
    private var previousLocation: CLLocation?

    /// Callback when a trip starts (for UI updates outside Live Activity).
    public var onTripStarted: ((String) -> Void)?

    /// Callback when a trip ends, with final distance in miles.
    public var onTripEnded: ((String, Double) -> Void)?

    // MARK: - Init

    private override init() {
        let detectorConfig = AutoTripDetector.Configuration()
        self.detector = AutoTripDetector(configuration: detectorConfig)

        let trackerConfig = TripLocationTracker.Configuration()
        self.tracker = TripLocationTracker(configuration: trackerConfig)

        self.liveActivityManager = TripLiveActivityManager.shared

        super.init()

        detector.delegate = self
    }

    // MARK: - Public API

    /// Start monitoring for auto trips. Call at app launch.
    public func startMonitoring() {
        detector.startMonitoring()
    }

    /// Stop all monitoring and end any active trip.
    public func stopMonitoring() {
        if currentTripID != nil {
            endCurrentTrip(at: previousLocation)
        }
        detector.stopMonitoring()
    }

    /// Handle background launch from significant location change.
    public func handleBackgroundLaunch(launchOptions: [String: Any]?) {
        detector.handleBackgroundLaunch(launchOptions: launchOptions)
    }

    /// Whether a trip is currently being tracked.
    public var isTracking: Bool {
        return currentTripID != nil
    }

    // MARK: - Trip Management

    private func startNewTrip(at location: CLLocation) {
        let tripID = "auto-\(UUID().uuidString.prefix(8))-\(Int(Date().timeIntervalSince1970))"
        currentTripID = tripID
        tripStartTime = Date()
        totalDistanceMeters = 0
        previousLocation = location

        // Start recording GPS
        tracker.startTrip()

        // Start Live Activity
        do {
            try liveActivityManager.startLiveActivity(
                tripID: tripID,
                origin: .autoDetected,
                startLocation: location
            )
        } catch {
            // Live Activity failed to start - trip still records, just no UI
            print("[AutoTripCoordinator] Failed to start Live Activity: \(error)")
        }

        onTripStarted?(tripID)
    }

    private func endCurrentTrip(at location: CLLocation?) {
        guard let tripID = currentTripID else { return }

        let locations = tracker.stopTrip()
        let finalDistanceMiles = totalDistanceMeters / 1609.344
        let durationSeconds = Int(Date().timeIntervalSince(tripStartTime ?? Date()))

        // End Live Activity with final stats
        liveActivityManager.endLiveActivity(
            finalDistanceMiles: finalDistanceMiles,
            finalDurationSeconds: durationSeconds
        )

        onTripEnded?(tripID, finalDistanceMiles)

        // Reset state
        currentTripID = nil
        tripStartTime = nil
        totalDistanceMeters = 0
        previousLocation = nil

        // Post-process route in background (road snapping, etc.)
        Task {
            await postProcessTrip(tripID: tripID, locations: locations)
        }
    }

    private func updateTrip(with location: CLLocation) {
        // Accumulate distance
        if let prev = previousLocation {
            let segmentDistance = location.distance(from: prev)
            // Sanity check: ignore jumps > 1km in a single update (GPS glitch)
            if segmentDistance < 1000 {
                totalDistanceMeters += segmentDistance
            }
        }
        previousLocation = location

        let distanceMiles = totalDistanceMeters / 1609.344
        let durationSeconds = Int(Date().timeIntervalSince(tripStartTime ?? Date()))

        // Update Live Activity
        let quality: TripActivityAttributes.SignalQuality
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 100 {
            quality = .poor
        } else if location.horizontalAccuracy > 40 {
            quality = .fair
        } else {
            quality = .good
        }

        liveActivityManager.updateLiveActivity(
            distanceMiles: distanceMiles,
            durationSeconds: durationSeconds,
            currentSpeedMPH: max(0, location.speed * 2.23694),
            signalQuality: quality
        )
    }

    // MARK: - Post Processing

    private func postProcessTrip(tripID: String, locations: [CLLocation]) async {
        // Process the route for clean map display
        let processor = TripRouteProcessor()
        do {
            let route = try await processor.processTrip(rawLocations: locations)
            // Store processed route for later display
            // (Integration point: save to your data store here)
            _ = route
        } catch {
            print("[AutoTripCoordinator] Route post-processing failed: \(error)")
        }
    }
}

// MARK: - AutoTripDetector.Delegate

extension AutoTripCoordinator: AutoTripDetector.Delegate {

    public func autoTripDetector(_ detector: AutoTripDetector, didDetectTripStart startLocation: CLLocation) {
        startNewTrip(at: startLocation)
    }

    public func autoTripDetector(_ detector: AutoTripDetector, didDetectTripEnd endLocation: CLLocation) {
        endCurrentTrip(at: endLocation)
    }

    public func autoTripDetector(_ detector: AutoTripDetector, didUpdateLocation location: CLLocation) {
        guard currentTripID != nil else { return }
        updateTrip(with: location)
    }

    public func autoTripDetector(_ detector: AutoTripDetector, didChangeState state: AutoTripDetector.DetectionState) {
        // Logging / analytics hook
    }
}
