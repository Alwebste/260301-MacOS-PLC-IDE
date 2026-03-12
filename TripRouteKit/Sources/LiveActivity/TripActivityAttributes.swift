import ActivityKit
import CoreLocation
import Foundation

/// ActivityKit attributes for trip tracking Live Activities.
/// Works for both auto-detected and manually started trips.
public struct TripActivityAttributes: ActivityAttributes {

    // MARK: - Static Content (set at Live Activity creation)

    /// How the trip was initiated
    public enum TripOrigin: String, Codable {
        case autoDetected
        case manual
    }

    /// The origin type of this trip
    public var tripOrigin: TripOrigin

    /// Trip ID for correlation with the trip data store
    public var tripID: String

    /// Start time of the trip
    public var startTime: Date

    /// Starting address (resolved asynchronously, may be empty initially)
    public var startAddress: String

    // MARK: - Dynamic Content (updated throughout the trip)

    public struct ContentState: Codable, Hashable {
        /// Current distance traveled in miles
        public var distanceMiles: Double

        /// Estimated deduction amount (IRS rate * miles)
        public var estimatedDeduction: Double

        /// Current trip duration in seconds
        public var durationSeconds: Int

        /// Whether the trip is classified as business
        public var isBusiness: Bool

        /// Current speed in mph (for compact display)
        public var currentSpeedMPH: Double

        /// Brief destination hint (street name or landmark)
        public var currentStreet: String

        /// Signal quality indicator for user awareness
        public var signalQuality: SignalQuality

        /// Whether the trip is actively recording vs paused/ending
        public var isActivelyRecording: Bool
    }

    public enum SignalQuality: String, Codable, Hashable {
        case good
        case fair
        case poor
    }
}

// MARK: - Convenience Initializers

extension TripActivityAttributes {
    /// Creates attributes for an auto-detected trip.
    public static func autoDetected(tripID: String, startAddress: String = "") -> TripActivityAttributes {
        TripActivityAttributes(
            tripOrigin: .autoDetected,
            tripID: tripID,
            startTime: Date(),
            startAddress: startAddress
        )
    }

    /// Creates attributes for a manually started trip.
    public static func manual(tripID: String, startAddress: String = "") -> TripActivityAttributes {
        TripActivityAttributes(
            tripOrigin: .manual,
            tripID: tripID,
            startTime: Date(),
            startAddress: startAddress
        )
    }
}

extension TripActivityAttributes.ContentState {
    /// Initial state when a trip first starts.
    public static var initial: TripActivityAttributes.ContentState {
        TripActivityAttributes.ContentState(
            distanceMiles: 0.0,
            estimatedDeduction: 0.0,
            durationSeconds: 0,
            isBusiness: false,
            currentSpeedMPH: 0.0,
            currentStreet: "",
            signalQuality: .good,
            isActivelyRecording: true
        )
    }
}
