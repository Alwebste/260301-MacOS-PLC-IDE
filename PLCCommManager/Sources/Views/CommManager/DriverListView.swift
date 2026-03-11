// DriverListView.swift
// PLCCommManager - PLC Communications Manager
// Driver list and management — configure, start, stop, and monitor comm drivers

import SwiftUI

struct DriverListView: View {
    @EnvironmentObject var commStore: CommManagerStore
    @State private var showingAddDriver = false
    @State private var showingEditDriver = false
    @State private var editingDriver: CommDriver?
    @State private var driverToDelete: CommDriver?
    @State private var showDeleteConfirmation = false
    @State private var testResult: (Bool, String)?
    @State private var showTestResult = false

    var body: some View {
        HSplitView {
            // Left: Driver list
            driverListPanel
                .frame(minWidth: 320, idealWidth: 400)

            // Right: Selected driver detail
            driverDetailPanel
                .frame(minWidth: 400)
        }
    }

    // MARK: - Driver List Panel

    private var driverListPanel: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("Communication Drivers")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddDriver = true }) {
                    Label("Add Driver", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            if commStore.drivers.isEmpty {
                emptyDriverState
            } else {
                List(selection: $commStore.selectedDriverID) {
                    ForEach(commStore.drivers) { driver in
                        DriverRowView(driver: driver)
                            .tag(driver.id)
                            .contextMenu {
                                driverContextMenu(driver)
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .sheet(isPresented: $showingAddDriver) {
            AddDriverSheet()
        }
        .sheet(isPresented: $showingEditDriver) {
            if let driver = editingDriver {
                EditDriverSheet(driver: driver)
            }
        }
        .alert("Delete Driver", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let driver = driverToDelete {
                    commStore.removeDriver(id: driver.id)
                }
            }
        } message: {
            Text("Are you sure you want to delete '\(driverToDelete?.name ?? "")'? This cannot be undone.")
        }
        .alert(testResult?.0 == true ? "Success" : "Failed", isPresented: $showTestResult) {
            Button("OK") {}
        } message: {
            Text(testResult?.1 ?? "")
        }
    }

    private var emptyDriverState: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Drivers Configured")
                .font(.title3.weight(.semibold))
            Text("Add a communication driver to connect to PLCs.\nSupports EtherNet/IP, Modbus TCP, OPC UA, and Serial DF1.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Add First Driver") {
                showingAddDriver = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    @ViewBuilder
    private func driverContextMenu(_ driver: CommDriver) -> some View {
        if driver.state == .connected {
            Button("Disconnect") { commStore.disconnectDriver(id: driver.id) }
        } else {
            Button("Connect") { commStore.connectDriver(id: driver.id) }
        }
        Divider()
        Button("Test Connection") {
            commStore.testConnection(id: driver.id) { success, message in
                testResult = (success, message)
                showTestResult = true
            }
        }
        Button("Edit...") {
            editingDriver = driver
            showingEditDriver = true
        }
        Button("Duplicate") { commStore.duplicateDriver(id: driver.id) }
        Divider()
        Button("Delete", role: .destructive) {
            driverToDelete = driver
            showDeleteConfirmation = true
        }
    }

    // MARK: - Driver Detail Panel

    @ViewBuilder
    private var driverDetailPanel: some View {
        if let driverID = commStore.selectedDriverID,
           let driver = commStore.drivers.first(where: { $0.id == driverID }) {
            DriverDetailView(driver: driver)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Select a driver to view details")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Driver Row

struct DriverRowView: View {
    let driver: CommDriver

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(stateColor)
                .frame(width: 10, height: 10)

            // Protocol icon
            Image(systemName: driver.protocol_.icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)

            // Driver info
            VStack(alignment: .leading, spacing: 2) {
                Text(driver.name)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 4) {
                    Text(driver.protocol_.rawValue)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if let config = driver.ethernetIPConfig {
                        Text("• \(config.ipAddress)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else if let config = driver.modbusTCPConfig {
                        Text("• \(config.ipAddress)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else if let config = driver.serialDF1Config {
                        Text("• \(config.portName)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // State badge
            Text(driver.state.rawValue)
                .font(.system(size: 10, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(stateColor.opacity(0.15))
                .foregroundColor(stateColor)
                .cornerRadius(4)
        }
        .padding(.vertical, 4)
    }

    private var stateColor: Color {
        switch driver.state {
        case .connected: return .green
        case .connecting: return .orange
        case .error: return .red
        case .timeout: return .yellow
        case .disconnected: return .gray
        case .discovering: return .blue
        }
    }
}

// MARK: - Driver Detail View

struct DriverDetailView: View {
    @EnvironmentObject var commStore: CommManagerStore
    let driver: CommDriver

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                driverHeader

                Divider()

                // Configuration summary
                configurationSummary

                Divider()

                // Statistics
                statisticsSection

                Divider()

                // Quick actions
                actionsSection
            }
            .padding(20)
        }
    }

    private var driverHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: driver.protocol_.icon)
                        .font(.title2)
                    Text(driver.name)
                        .font(.title2.weight(.semibold))
                }
                Text(driver.protocol_.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()

            // Connect/Disconnect button
            if driver.state == .connected {
                Button("Disconnect") {
                    commStore.disconnectDriver(id: driver.id)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            } else {
                Button("Connect") {
                    commStore.connectDriver(id: driver.id)
                }
                .buttonStyle(.borderedProminent)
                .disabled(driver.state == .connecting)
            }
        }
    }

    private var configurationSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], spacing: 8) {
                configRow("Protocol", driver.protocol_.rawValue)
                configRow("Status", driver.state.rawValue)
                configRow("Auto-Start", driver.autoStart ? "Yes" : "No")
                configRow("Created", driver.createdAt.formatted(date: .abbreviated, time: .shortened))

                if let config = driver.ethernetIPConfig {
                    configRow("IP Address", config.ipAddress)
                    configRow("Port", "\(config.port)")
                    configRow("Slot", "\(config.slot)")
                    configRow("Timeout", "\(config.connectionTimeout)s")
                    configRow("PLC Family", config.plcFamily.rawValue)
                    configRow("Keep Alive", config.enableKeepAlive ? "\(Int(config.keepAliveInterval))s" : "Off")
                } else if let config = driver.modbusTCPConfig {
                    configRow("IP Address", config.ipAddress)
                    configRow("Port", "\(config.port)")
                    configRow("Unit ID", "\(config.unitID)")
                    configRow("Timeout", "\(config.responseTimeout)s")
                    configRow("Byte Order", config.byteOrder.rawValue)
                    configRow("Poll Rate", "\(config.defaultPollRate)s")
                } else if let config = driver.opcUAConfig {
                    configRow("Endpoint", config.endpointURL)
                    configRow("Security", config.securityMode.rawValue)
                    configRow("Auth", config.authMode.rawValue)
                    configRow("Session Timeout", "\(Int(config.sessionTimeout))s")
                } else if let config = driver.serialDF1Config {
                    configRow("Port", config.portName)
                    configRow("Baud Rate", config.baudRate.display)
                    configRow("Data Bits", config.dataBits.display)
                    configRow("Parity", config.parity.rawValue)
                    configRow("Station", "\(config.stationAddress)")
                }
            }
        }
    }

    private func configRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Statistics")
                .font(.headline)

            let stats = commStore.statistics[driver.id] ?? CommStatistics()

            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], spacing: 8) {
                statCard("Packets Sent", "\(stats.packetsSent)")
                statCard("Packets Received", "\(stats.packetsReceived)")
                statCard("Errors", "\(stats.packetsError)")
                statCard("Avg Response", String(format: "%.1f ms", stats.averageResponseMs))
                statCard("Success Rate", String(format: "%.1f%%", stats.successRate))
                statCard("Reconnects", "\(stats.reconnectCount)")
            }
        }
    }

    private func statCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(6)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 12) {
                Button(action: {
                    commStore.testConnection(id: driver.id) { _, _ in }
                }) {
                    Label("Test Connection", systemImage: "bolt.horizontal")
                }

                Button(action: {
                    commStore.clearDiagnostics(for: driver.id)
                }) {
                    Label("Clear Logs", systemImage: "trash")
                }

                Button(action: {
                    // Reset statistics
                    commStore.statistics[driver.id] = CommStatistics()
                }) {
                    Label("Reset Stats", systemImage: "arrow.counterclockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
