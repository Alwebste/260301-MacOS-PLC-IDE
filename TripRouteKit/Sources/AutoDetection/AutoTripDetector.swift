import CoreLocation
import CoreMotion
import Foundation

/// Detects vehicle trips automatically using a combination of motion activity
/// recognition and significant location changes.
///
/// Detection strategy:
/// 1. **CMMotionActivityManager** detects automotive activity
/// 2. **CLLocationManager.significantLocationChangeMonitoring** provides
///    low-power wake-ups when the device moves significantly
/// 3. When both agree the user is driving, a trip is started
/// 4. Trip ends when automotive activity stops and location stabilizes
///
/// This runs in the background with minimal battery impact. The significant
/// location change API is the key enabler — it wakes the app even if terminated.
public final class AutoTripDetector: NSObject {

    // MARK: - Configuration

    public struct Configuration {
        /// Minimum automotive confidence duration before starting a trip (seconds).
        /// Prevents false starts from brief motion detection.
        /// Default: 10 seconds
        public var minDrivingDurationToStart: TimeInterval = 10.0

        /// How long automotive activity must be absent before ending a trip (seconds).
        /// Prevents premature end at stop lights, drive-throughs, etc.
        /// Default: 120 seconds (2 minutes)
        public var stopDelayDuration: TimeInterval = 120.0

        /// Minimum distance from trip start before we consider it a real trip (meters).
        /// Filters out parking lot shuffles and GPS noise.
        /// Default: 200m
        public var minTripDistance: CLLocationDistance = 200.0

        /// Minimum speed in m/s from CLLocation to confirm driving.
        /// Default: 4.5 m/s (~10 mph)
        public var minDrivingSpeed: CLLocationSpeed = 4.5

        /// Maximum horizontal accuracy to trust a location for trip decisions.
        /// Default: 50m
        public var maxAccuracyForDecision: CLLocationAccuracy = 50.0

        /// Whether to use motion activity manager (requires permission).
        /// Fall back to location-only detection if false.
        /// Default: true
        public var useMotionActivity: Bool = true

        public init() {}
    }

    // MARK: - Delegate

    public protocol Delegate: AnyObject {
        /// Called when a new trip is auto-detected. Start recording + Live Activity here.
        func autoTripDetector(_ detector: AutoTripDetector, didDetectTripStart startLocation: CLLocation)

        /// Called when the current trip appears to have ended. Stop recording + end Live Activity.
        func autoTripDetector(_ detector: AutoTripDetector, didDetectTripEnd endLocation: CLLocation)

        /// Called with each location update during an active trip.
        func autoTripDetector(_ detector: AutoTripDetector, didUpdateLocation location: CLLocation)

        /// Called when detection state changes (for debugging/logging).
        func autoTripDetector(_ detector: AutoTripDetector, didChangeState state: DetectionState)
    }

    // MARK: - State

    public enum DetectionState: String {
        /// Monitoring for trip start (low power)
        case monitoring

        /// Possible trip detected, confirming...
        case confirming

        /// Trip in progress, actively tracking
        case tracking

        /// Trip may be ending, waiting for stop delay
        case stopping

        /// Detector is not running
        case inactive
    }

    // MARK: - Properties

    public weak var delegate: Delegate?
    private(set) public var state: DetectionState = .inactive

    private let config: Configuration
    private let locationManager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()

    // Trip state
    private var tripStartLocation: CLLocation?
    private var lastLocation: CLLocation?
    private var lastAutomotiveActivity: Date?
    private var confirmationStartTime: Date?
    private var stopTimer: Timer?
    private var isAutomotive = false

    // Tracking mode location manager (higher accuracy during active trip)
    private let trackingLocationManager = CLLocationManager()

    public init(configuration: Configuration = Configuration()) {
        self.config = configuration
        super.init()

        setupLocationManagers()
    }

    // MARK: - Setup

    private func setupLocationManagers() {
        // Primary: significant location changes (background, low power)
        locationManager.delegate = self
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.showsBackgroundLocationIndicator = false // Don't show blue bar during monitoring
        locationManager.pausesLocationUpdatesAutomatically = false

        // Secondary: high-accuracy tracking during active trips
        trackingLocationManager.delegate = self
        trackingLocationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        trackingLocationManager.distanceFilter = 5.0
        trackingLocationManager.activityType = .automotiveNavigation
        trackingLocationManager.allowsBackgroundLocationUpdates = true
        trackingLocationManager.showsBackgroundLocationIndicator = true // Show during active trip
        trackingLocationManager.pausesLocationUpdatesAutomatically = false
    }

    // MARK: - Start/Stop Detection

    /// Begins monitoring for auto trips. Call once at app launch.
    /// Uses significant location changes (survives app termination).
    public func startMonitoring() {
        locationManager.requestAlwaysAuthorization()
        locationManager.startMonitoringSignificantLocationChanges()

        if config.useMotionActivity && CMMotionActivityManager.isActivityAvailable() {
            startMotionActivityUpdates()
        }

        transition(to: .monitoring)
    }

    /// Stops all monitoring.
    public func stopMonitoring() {
        locationManager.stopMonitoringSignificantLocationChanges()
        trackingLocationManager.stopUpdatingLocation()
        motionActivityManager.stopActivityUpdates()
        stopTimer?.invalidate()
        stopTimer = nil

        transition(to: .inactive)
    }

    /// Call this from `application(_:didFinishLaunchingWithOptions:)` when
    /// launched due to a significant location change.
    public func handleBackgroundLaunch(launchOptions: [String: Any]?) {
        if launchOptions?["UIApplicationLaunchOptionsLocationKey"] != nil {
            // Relaunched for significant location change
            startMonitoring()
        }
    }

    // MARK: - Motion Activity

    private func startMotionActivityUpdates() {
        motionActivityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity else { return }
            self.handleMotionActivity(activity)
        }
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        let wasAutomotive = isAutomotive
        isAutomotive = activity.automotive && activity.confidence != .low

        if isAutomotive {
            lastAutomotiveActivity = Date()
        }

        switch state {
        case .monitoring:
            if isAutomotive {
                // Potential trip start
                confirmationStartTime = Date()
                transition(to: .confirming)
            }

        case .confirming:
            if !isAutomotive && !activity.unknown {
                // Motion says not driving anymore, cancel confirmation
                confirmationStartTime = nil
                transition(to: .monitoring)
            }

        case .tracking:
            if !isAutomotive && wasAutomotive {
                // Driving stopped, start the stop delay timer
                beginStopDelay()
            }

        case .stopping:
            if isAutomotive {
                // Resumed driving, cancel stop
                cancelStopDelay()
                transition(to: .tracking)
            }

        case .inactive:
            break
        }
    }

    // MARK: - Trip Lifecycle

    private func confirmTripStart(location: CLLocation) {
        guard state == .confirming || state == .monitoring else { return }

        // Validate location quality
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= config.maxAccuracyForDecision else {
            return
        }

        tripStartLocation = location
        lastLocation = location

        // Switch to high-accuracy tracking
        trackingLocationManager.startUpdatingLocation()

        transition(to: .tracking)
        delegate?.autoTripDetector(self, didDetectTripStart: location)
    }

    private func confirmTripEnd() {
        guard let lastLoc = lastLocation else {
            resetToMonitoring()
            return
        }

        // Check if we actually traveled enough to count as a trip
        if let startLoc = tripStartLocation {
            let distance = lastLoc.distance(from: startLoc)
            if distance < config.minTripDistance {
                // Too short, discard as a non-trip (parking shuffle, etc.)
                resetToMonitoring()
                return
            }
        }

        // Real trip ended
        delegate?.autoTripDetector(self, didDetectTripEnd: lastLoc)
        resetToMonitoring()
    }

    private func resetToMonitoring() {
        trackingLocationManager.stopUpdatingLocation()
        tripStartLocation = nil
        lastLocation = nil
        confirmationStartTime = nil
        stopTimer?.invalidate()
        stopTimer = nil
        isAutomotive = false

        transition(to: .monitoring)
    }

    // MARK: - Stop Delay

    private func beginStopDelay() {
        guard state == .tracking else { return }

        transition(to: .stopping)

        stopTimer?.invalidate()
        stopTimer = Timer.scheduledTimer(
            withTimeInterval: config.stopDelayDuration,
            repeats: false
        ) { [weak self] _ in
            self?.confirmTripEnd()
        }
    }

    private func cancelStopDelay() {
        stopTimer?.invalidate()
        stopTimer = nil
    }

    // MARK: - State Transitions

    private func transition(to newState: DetectionState) {
        guard state != newState else { return }
        state = newState
        delegate?.autoTripDetector(self, didChangeState: newState)
    }
}

// MARK: - CLLocationManagerDelegate

extension AutoTripDetector: CLLocationManagerDelegate {

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        // Filter stale/inaccurate locations
        guard abs(location.timestamp.timeIntervalSinceNow) < 15.0 else { return }

        switch state {
        case .monitoring:
            // Significant location change received while monitoring.
            // If motion says automotive, or speed is high enough, start confirming.
            if isAutomotive || (location.speed >= config.minDrivingSpeed
                && location.horizontalAccuracy <= config.maxAccuracyForDecision) {
                confirmationStartTime = Date()
                transition(to: .confirming)
                // Immediately try to confirm if conditions are met
                evaluateConfirmation(location: location)
            }

        case .confirming:
            evaluateConfirmation(location: location)

        case .tracking:
            lastLocation = location
            delegate?.autoTripDetector(self, didUpdateLocation: location)

        case .stopping:
            lastLocation = location
            // If we're moving fast again, cancel the stop
            if location.speed >= config.minDrivingSpeed {
                cancelStopDelay()
                transition(to: .tracking)
            }
            delegate?.autoTripDetector(self, didUpdateLocation: location)

        case .inactive:
            break
        }
    }

    private func evaluateConfirmation(location: CLLocation) {
        guard state == .confirming, let startTime = confirmationStartTime else { return }

        let elapsed = Date().timeIntervalSince(startTime)

        // Need sustained driving signals for minDrivingDurationToStart
        let speedOK = location.speed >= config.minDrivingSpeed
        let motionOK = isAutomotive
        let accuracyOK = location.horizontalAccuracy >= 0
            && location.horizontalAccuracy <= config.maxAccuracyForDecision

        if (speedOK || motionOK) && accuracyOK && elapsed >= config.minDrivingDurationToStart {
            confirmTripStart(location: location)
        } else if elapsed > config.minDrivingDurationToStart * 3 && !speedOK && !motionOK {
            // Took too long without confirmation, back to monitoring
            confirmationStartTime = nil
            transition(to: .monitoring)
        }
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Location errors during monitoring are expected, just continue
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            if state == .inactive {
                startMonitoring()
            }
        case .authorizedWhenInUse:
            // Significant location changes require "Always" permission.
            // The app should prompt for upgrade.
            break
        default:
            break
        }
    }
}
