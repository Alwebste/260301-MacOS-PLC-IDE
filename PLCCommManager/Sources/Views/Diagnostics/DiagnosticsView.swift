// DiagnosticsView.swift
// PLCCommManager - PLC Communications Manager
// Communication diagnostics — event log, health monitoring, statistics dashboard

import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var commStore: CommManagerStore
    @State private var selectedSeverityFilter: DiagnosticSeverity?
    @State private var selectedDriverFilter: UUID?
    @State private var searchText: String = ""
    @State private var showStatsDashboard: Bool = true

    var filteredEvents: [DiagnosticEvent] {
        commStore.diagnosticEvents.filter { event in
            if let severity = selectedSeverityFilter, event.severity != severity {
                return false
            }
            if let driverID = selectedDriverFilter, event.driverID != driverID {
                return false
            }
            if !searchText.isEmpty {
                let text = searchText.lowercased()
                return event.message.lowercased().contains(text) ||
                       event.source.lowercased().contains(text) ||
                       event.details.lowercased().contains(text)
            }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            diagnosticToolbar
            Divider()

            if showStatsDashboard {
                // Statistics dashboard
                statisticsDashboard
                Divider()
            }

            // Event log
            eventLogPanel
        }
    }

    // MARK: - Toolbar

    private var diagnosticToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .foregroundColor(.secondary)
            Text("Diagnostics")
                .font(.headline)

            Spacer()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search events...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }

            // Severity filter
            Picker("Severity:", selection: $selectedSeverityFilter) {
                Text("All").tag(nil as DiagnosticSeverity?)
                ForEach([DiagnosticSeverity.info, .warning, .error, .critical], id: \.rawValue) { severity in
                    Label(severity.rawValue, systemImage: severity.icon).tag(severity as DiagnosticSeverity?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)

            // Driver filter
            Picker("Driver:", selection: $selectedDriverFilter) {
                Text("All Drivers").tag(nil as UUID?)
                ForEach(commStore.drivers) { driver in
                    Text(driver.name).tag(driver.id as UUID?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 160)

            Toggle(isOn: $showStatsDashboard) {
                Image(systemName: "chart.bar")
            }
            .toggleStyle(.button)
            .help("Show/hide statistics dashboard")

            Button(action: { commStore.clearDiagnostics() }) {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Statistics Dashboard

    private var statisticsDashboard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                // Summary cards
                summaryCard("Drivers", value: "\(commStore.drivers.count)",
                            subtitle: "\(commStore.activeConnectionCount) active", color: .blue)
                summaryCard("Connected", value: "\(commStore.activeConnectionCount)",
                            subtitle: "of \(commStore.enabledDrivers.count) enabled", color: .green)
                summaryCard("Errors", value: "\(errorCount)",
                            subtitle: "in current session", color: errorCount > 0 ? .red : .gray)
                summaryCard("Devices", value: "\(commStore.discoveredDevices.count)",
                            subtitle: "discovered", color: .purple)

                Spacer()

                // Per-driver mini stats
                VStack(alignment: .leading, spacing: 4) {
                    Text("Driver Health")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)

                    ForEach(commStore.drivers.prefix(4)) { driver in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(driver.state == .connected ? Color.green : Color.gray)
                                .frame(width: 6, height: 6)
                            Text(driver.name)
                                .font(.system(size: 10))
                                .lineLimit(1)

                            Spacer()

                            let stats = commStore.statistics[driver.id] ?? CommStatistics()
                            Text(String(format: "%.0f%%", stats.successRate))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(stats.successRate >= 99 ? .green : .orange)
                        }
                    }
                }
                .frame(width: 200)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func summaryCard(_ title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(width: 110, height: 70)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }

    private var errorCount: Int {
        commStore.diagnosticEvents.filter { $0.severity == .error || $0.severity == .critical }.count
    }

    // MARK: - Event Log

    private var eventLogPanel: some View {
        VStack(spacing: 0) {
            // Column headers
            HStack(spacing: 0) {
                Text("Time")
                    .frame(width: 140, alignment: .leading)
                Text("Severity")
                    .frame(width: 80, alignment: .leading)
                Text("Source")
                    .frame(width: 150, alignment: .leading)
                Text("Message")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            if filteredEvents.isEmpty {
                VStack(spacing: 8) {
                    Text("No events to display")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredEvents) { event in
                        DiagnosticEventRow(event: event)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

// MARK: - Diagnostic Event Row

struct DiagnosticEventRow: View {
    let event: DiagnosticEvent

    var body: some View {
        HStack(spacing: 0) {
            // Timestamp
            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 140, alignment: .leading)

            // Severity badge
            HStack(spacing: 3) {
                Image(systemName: event.severity.icon)
                    .font(.system(size: 9))
                Text(event.severity.rawValue)
                    .font(.system(size: 10))
            }
            .foregroundColor(severityColor)
            .frame(width: 80, alignment: .leading)

            // Source
            Text(event.source)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)

            // Message
            VStack(alignment: .leading, spacing: 1) {
                Text(event.message)
                    .font(.system(size: 11))
                    .lineLimit(2)
                if !event.details.isEmpty {
                    Text(event.details)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var severityColor: Color {
        switch event.severity {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .critical: return .red
        }
    }
}
