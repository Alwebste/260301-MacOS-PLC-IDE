import ActivityKit
import CoreLocation
import Foundation

/// Manages the lifecycle of trip Live Activities for both auto-detected
/// and manual trips.
///
/// Key responsibility: ensuring auto-detected trips get a Live Activity
/// started immediately when driving is detected, updated as location
/// streams in, and ended cleanly when the trip concludes.
///
/// Usage:
/// ```swift
/// let manager = TripLiveActivityManager.shared
///
/// // Auto-detection calls this:
/// let activity = try manager.startLiveActivity(
///     tripID: "trip-123",
///     origin: .autoDetected
/// )
///
/// // Location updates call this:
/// manager.updateLiveActivity(
///     distanceMiles: 3.2,
///     estimatedDeduction: 2.32,
///     durationSeconds: 420,
///     currentSpeedMPH: 35,
///     currentStreet: "W 7th St"
/// )
///
/// // Trip end:
/// manager.endLiveActivity(finalDistanceMiles: 8.1, finalDeduction: 5.87)
/// ```
public final class TripLiveActivityManager {

    public static let shared = TripLiveActivityManager()

    // MARK: - State

    /// The currently active Live Activity, if any.
    private(set) public var currentActivity: Activity<TripActivityAttributes>?

    /// Whether a Live Activity is currently running.
    public var isActive: Bool { currentActivity != nil }

    /// IRS standard mileage rate (2026). Update annually.
    public var irsRatePerMile: Double = 0.70

    private let geocoder = CLGeocoder()
    private var updateThrottleDate: Date = .distantPast
    private let minUpdateInterval: TimeInterval = 4.0 // iOS throttles to ~once per second, but we batch

    private init() {}

    // MARK: - Start Live Activity

    /// Starts a new trip Live Activity.
    ///
    /// - Parameters:
    ///   - tripID: Unique identifier for the trip
    ///   - origin: Whether auto-detected or manual
    ///   - startLocation: Optional starting location for reverse geocoding
    /// - Returns: The created Activity instance
    @discardableResult
    public func startLiveActivity(
        tripID: String,
        origin: TripActivityAttributes.TripOrigin,
        startLocation: CLLocation? = nil
    ) throws -> Activity<TripActivityAttributes> {

        // End any existing activity first
        if let existing = currentActivity {
            Task {
                await endExistingActivity(existing)
            }
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw LiveActivityError.activitiesNotEnabled
        }

        let attributes: TripActivityAttributes
        switch origin {
        case .autoDetected:
            attributes = .autoDetected(tripID: tripID)
        case .manual:
            attributes = .manual(tripID: tripID)
        }

        let initialState = TripActivityAttributes.ContentState.initial
        let content = ActivityContent(state: initialState, staleDate: nil)

        let activity = try Activity.request(
            attributes: attributes,
            content: content,
            pushType: nil // Local updates only, no push token needed
        )

        currentActivity = activity

        // Reverse geocode start address in background
        if let location = startLocation {
            Task {
                await resolveStartAddress(for: tripID, location: location)
            }
        }

        return activity
    }

    // MARK: - Update Live Activity

    /// Updates the Live Activity with current trip metrics.
    /// Throttled to avoid excessive updates.
    public func updateLiveActivity(
        distanceMiles: Double,
        estimatedDeduction: Double? = nil,
        durationSeconds: Int,
        isBusiness: Bool = false,
        currentSpeedMPH: Double = 0,
        currentStreet: String = "",
        signalQuality: TripActivityAttributes.SignalQuality = .good
    ) {
        guard let activity = currentActivity else { return }

        // Throttle updates
        let now = Date()
        guard now.timeIntervalSince(updateThrottleDate) >= minUpdateInterval else { return }
        updateThrottleDate = now

        let deduction = estimatedDeduction ?? (distanceMiles * irsRatePerMile)

        let state = TripActivityAttributes.ContentState(
            distanceMiles: distanceMiles,
            estimatedDeduction: deduction,
            durationSeconds: durationSeconds,
            isBusiness: isBusiness,
            currentSpeedMPH: currentSpeedMPH,
            currentStreet: currentStreet,
            signalQuality: signalQuality,
            isActivelyRecording: true
        )

        let content = ActivityContent(state: state, staleDate: nil)

        Task {
            await activity.update(content)
        }
    }

    /// Convenience: update from a CLLocation directly.
    public func updateFromLocation(
        _ location: CLLocation,
        totalDistanceMiles: Double,
        durationSeconds: Int,
        isBusiness: Bool = false
    ) {
        let speedMPH = max(0, location.speed * 2.23694) // m/s to mph
        let quality: TripActivityAttributes.SignalQuality
        if location.horizontalAccuracy < 0 || location.horizontalAccuracy > 100 {
            quality = .poor
        } else if location.horizontalAccuracy > 40 {
            quality = .fair
        } else {
            quality = .good
        }

        updateLiveActivity(
            distanceMiles: totalDistanceMiles,
            durationSeconds: durationSeconds,
            currentSpeedMPH: speedMPH,
            signalQuality: quality
        )
    }

    // MARK: - End Live Activity

    /// Ends the Live Activity with final trip summary.
    public func endLiveActivity(
        finalDistanceMiles: Double,
        finalDeduction: Double? = nil,
        finalDurationSeconds: Int = 0,
        isBusiness: Bool = false,
        dismissAfter: TimeInterval = 300 // 5 min on lock screen after trip ends
    ) {
        guard let activity = currentActivity else { return }

        let deduction = finalDeduction ?? (finalDistanceMiles * irsRatePerMile)

        let finalState = TripActivityAttributes.ContentState(
            distanceMiles: finalDistanceMiles,
            estimatedDeduction: deduction,
            durationSeconds: finalDurationSeconds,
            isBusiness: isBusiness,
            currentSpeedMPH: 0,
            currentStreet: "Trip Complete",
            signalQuality: .good,
            isActivelyRecording: false
        )

        let finalContent = ActivityContent(
            state: finalState,
            staleDate: Date().addingTimeInterval(dismissAfter)
        )

        let dismissPolicy: ActivityUIDismissalPolicy = .after(
            Date().addingTimeInterval(dismissAfter)
        )

        Task {
            await activity.end(finalContent, dismissalPolicy: dismissPolicy)
            await MainActor.run {
                self.currentActivity = nil
            }
        }
    }

    /// Immediately ends and removes the Live Activity (e.g., trip cancelled).
    public func cancelLiveActivity() {
        guard let activity = currentActivity else { return }

        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            await MainActor.run {
                self.currentActivity = nil
            }
        }
    }

    // MARK: - Private

    private func endExistingActivity(_ activity: Activity<TripActivityAttributes>) async {
        await activity.end(nil, dismissalPolicy: .immediate)
        await MainActor.run {
            self.currentActivity = nil
        }
    }

    private func resolveStartAddress(for tripID: String, location: CLLocation) async {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                let street = [placemark.subThoroughfare, placemark.thoroughfare]
                    .compactMap { $0 }
                    .joined(separator: " ")
                // Address resolved - could store in trip data, but attributes
                // are immutable after creation. This would need a data store update.
                _ = street
            }
        } catch {
            // Geocoding failure is non-critical
        }
    }

    // MARK: - Errors

    public enum LiveActivityError: LocalizedError {
        case activitiesNotEnabled
        case alreadyActive

        public var errorDescription: String? {
            switch self {
            case .activitiesNotEnabled:
                return "Live Activities are not enabled. Check Settings > Waypoint > Live Activities."
            case .alreadyActive:
                return "A trip Live Activity is already running."
            }
        }
    }
}
