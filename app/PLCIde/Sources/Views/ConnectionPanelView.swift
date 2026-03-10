import SwiftUI

/// Connection configuration and status panel.
/// Provides IP address entry, connection controls, and diagnostics.
struct ConnectionPanelView: View {
    @EnvironmentObject var connectionManager: ConnectionManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                statusIndicator
                Text("PLC Connection")
                    .font(.headline)
                Spacer()
                Text(connectionManager.connectionState.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // Connection settings
                    GroupBox("Connection Settings") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("IP Address:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("192.168.1.1", text: $connectionManager.ipAddress)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 160)
                                    .disabled(connectionManager.connectionState.isConnected)
                            }

                            HStack {
                                Text("Slot:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("0", value: $connectionManager.slot, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .disabled(connectionManager.connectionState.isConnected)
                                Text("(0 for CompactLogix)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            HStack {
                                Text("Timeout:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("5000", value: $connectionManager.timeout, formatter: NumberFormatter())
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                    .disabled(connectionManager.connectionState.isConnected)
                                Text("ms")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(4)
                    }

                    // Connection controls
                    HStack(spacing: 8) {
                        if connectionManager.connectionState.isConnected {
                            Button("Disconnect") {
                                connectionManager.disconnect()
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("Connect") {
                                connectionManager.connect()
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(connectionManager.connectionState == .connecting)
                        }

                        Button("Test") {
                            connectionManager.testConnection()
                        }
                        .disabled(connectionManager.connectionState.isConnected)
                    }

                    // Diagnostics (only when connected)
                    if connectionManager.connectionState.isConnected {
                        GroupBox("Diagnostics") {
                            VStack(alignment: .leading, spacing: 4) {
                                diagRow("Packets Sent", "\(connectionManager.packetsSent)")
                                diagRow("Packets Received", "\(connectionManager.packetsReceived)")
                                diagRow("Last Response", String(format: "%.1f ms", connectionManager.lastResponseTimeMs))
                                diagRow("Uptime", formatUptime(connectionManager.connectionUptime))
                                diagRow("Poll Interval", "\(connectionManager.pollIntervalMs) ms")
                                diagRow("Watched Tags", "\(connectionManager.watchedTags.count)")
                            }
                            .padding(4)
                        }
                    }

                    // Force table
                    if !connectionManager.forcedTags.isEmpty {
                        GroupBox("Active Forces") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(connectionManager.forcedTags.keys.sorted()), id: \.self) { tag in
                                    HStack {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.red)
                                            .font(.caption2)
                                        Text(tag)
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Text(connectionManager.forcedTags[tag] ?? "")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.orange)
                                        Button {
                                            connectionManager.removeForce(name: tag)
                                        } label: {
                                            Image(systemName: "xmark.circle")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }

                                Button("Remove All Forces") {
                                    connectionManager.removeAllForces()
                                }
                                .font(.caption)
                                .padding(.top, 4)
                            }
                            .padding(4)
                        }
                    }
                }
                .padding(12)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var statusIndicator: some View {
        Circle()
            .fill(statusColor)
            .frame(width: 10, height: 10)
    }

    private var statusColor: Color {
        switch connectionManager.connectionState {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    private func diagRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
            Spacer()
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%dh %dm %ds", h, m, s)
        } else if m > 0 {
            return String(format: "%dm %ds", m, s)
        } else {
            return String(format: "%ds", s)
        }
    }
}
