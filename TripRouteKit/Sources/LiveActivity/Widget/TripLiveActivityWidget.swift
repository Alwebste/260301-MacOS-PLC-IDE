import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity widget that renders the trip UI on the Lock Screen
/// and in the Dynamic Island.
///
/// Add this to your Widget Extension target. The same widget handles
/// both auto-detected and manual trips — the only difference is the
/// attributes.tripOrigin which you can use to show/hide an "Auto" badge.
@available(iOS 16.2, *)
public struct TripLiveActivityWidget: Widget {
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            // MARK: - Lock Screen / Banner View
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: - Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatDistance(context.state.distanceMiles))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundColor(.green)
                        Text("miles")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatCurrency(context.state.estimatedDeduction))
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundColor(.green)
                        Text("deduction")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 12) {
                        if context.state.isActivelyRecording {
                            recordingIndicator
                        }
                        Text(formatDuration(context.state.durationSeconds))
                            .font(.system(.body, design: .monospaced, weight: .medium))
                            .foregroundColor(.white)

                        if context.state.signalQuality == .poor {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .foregroundColor(.orange)
                                .font(.caption)
                        }
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if !context.state.currentStreet.isEmpty {
                            Image(systemName: "road.lanes")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(context.state.currentStreet)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if context.attributes.tripOrigin == .autoDetected {
                            Text("AUTO")
                                .font(.system(.caption2, design: .rounded, weight: .bold))
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.white.opacity(0.15)))
                        }
                    }
                }
            } compactLeading: {
                // MARK: - Compact Leading (left pill)
                HStack(spacing: 4) {
                    if context.state.isActivelyRecording {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                    }
                    Text(formatDistance(context.state.distanceMiles))
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundColor(.green)
                    Text("mi")
                        .font(.system(.caption2))
                        .foregroundColor(.secondary)
                }
            } compactTrailing: {
                // MARK: - Compact Trailing (right pill)
                Text(formatCurrency(context.state.estimatedDeduction))
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundColor(.green)
            } minimal: {
                // MARK: - Minimal (single dot, when other island content active)
                ZStack {
                    Circle()
                        .fill(.green.opacity(0.3))
                    Text(formatDistanceShort(context.state.distanceMiles))
                        .font(.system(.caption2, design: .rounded, weight: .bold))
                        .foregroundColor(.green)
                }
            }
        }
    }

    public init() {}

    // MARK: - Lock Screen View

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<TripActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            // Left: distance + recording indicator
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if context.state.isActivelyRecording {
                        recordingIndicator
                    }
                    Text("Recording trip...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("\(formatDistance(context.state.distanceMiles)) mi")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundColor(.green)

                if !context.state.currentStreet.isEmpty {
                    Text(context.state.currentStreet)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Right: deduction + duration
            VStack(alignment: .trailing, spacing: 4) {
                Text(formatCurrency(context.state.estimatedDeduction))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundColor(.green)

                Text("Est. deduction")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(formatDuration(context.state.durationSeconds))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black)
    }

    // MARK: - Shared Components

    private var recordingIndicator: some View {
        Circle()
            .fill(.green)
            .frame(width: 8, height: 8)
    }

    // MARK: - Formatting

    private func formatDistance(_ miles: Double) -> String {
        if miles < 10 {
            return String(format: "%.1f", miles)
        }
        return String(format: "%.0f", miles)
    }

    private func formatDistanceShort(_ miles: Double) -> String {
        if miles < 1 {
            return String(format: "%.1f", miles)
        }
        return String(format: "%.0f", miles)
    }

    private func formatCurrency(_ amount: Double) -> String {
        return String(format: "$%.2f", amount)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60

        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
