// ConnectionPathsView.swift
// PLCCommManager - PLC Communications Manager
// Connection path management — define, visualize, and manage comm paths to PLCs

import SwiftUI

struct ConnectionPathsView: View {
    @EnvironmentObject var commStore: CommManagerStore
    @State private var showAddPath = false
    @State private var selectedPathID: UUID?

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            pathToolbar
            Divider()

            HSplitView {
                // Path list
                pathListPanel
                    .frame(minWidth: 350)

                // Path detail / visualization
                pathDetailPanel
                    .frame(minWidth: 400)
            }
        }
        .sheet(isPresented: $showAddPath) {
            AddConnectionPathSheet()
        }
    }

    // MARK: - Toolbar

    private var pathToolbar: some View {
        HStack {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .foregroundColor(.secondary)
            Text("Connection Paths")
                .font(.headline)
            Spacer()
            Button(action: { showAddPath = true }) {
                Label("Add Path", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(commStore.drivers.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Path List

    private var pathListPanel: some View {
        Group {
            if commStore.connectionPaths.isEmpty {
                emptyState
            } else {
                List(selection: $selectedPathID) {
                    ForEach(commStore.connectionPaths) { path in
                        ConnectionPathRowView(path: path)
                            .tag(path.id)
                            .contextMenu {
                                Button("Set as Default") {
                                    commStore.setDefaultPath(id: path.id)
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    commStore.removeConnectionPath(id: path.id)
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Connection Paths")
                .font(.title3.weight(.semibold))
            Text("Connection paths define the route from your Mac to a PLC.\nThey combine a driver with routing information (IP, slot, backplane hops).")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if commStore.drivers.isEmpty {
                Text("Add a communication driver first.")
                    .font(.caption)
                    .foregroundColor(.orange)
            } else {
                Button("Add Connection Path") {
                    showAddPath = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Path Detail

    @ViewBuilder
    private var pathDetailPanel: some View {
        if let pathID = selectedPathID,
           let path = commStore.connectionPaths.first(where: { $0.id == pathID }) {
            ConnectionPathDetailView(path: path)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Select a path to view details")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Path Row

struct ConnectionPathRowView: View {
    let path: ConnectionPath

    var body: some View {
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(path.name)
                        .font(.system(size: 13, weight: .medium))
                    if path.isDefault {
                        Text("DEFAULT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }
                Text(path.pathString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(path.protocol_.rawValue)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch path.lastStatus {
        case .connected: return .green
        case .error: return .red
        default: return .gray
        }
    }
}

// MARK: - Path Detail View

struct ConnectionPathDetailView: View {
    let path: ConnectionPath

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(path.name)
                        .font(.title2.weight(.semibold))
                    if !path.description.isEmpty {
                        Text(path.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Divider()

                // Visual path diagram
                pathDiagram

                Divider()

                // Path properties
                VStack(alignment: .leading, spacing: 8) {
                    Text("Path Properties")
                        .font(.headline)

                    infoRow("Protocol", path.protocol_.rawValue)
                    infoRow("Target", path.targetDevice)
                    infoRow("Slot", "\(path.slot)")
                    infoRow("Path String", path.pathString)
                    infoRow("Default", path.isDefault ? "Yes" : "No")
                    if let lastUsed = path.lastUsed {
                        infoRow("Last Used", lastUsed.formatted(date: .abbreviated, time: .shortened))
                    }
                    infoRow("Status", path.lastStatus.rawValue)
                }
            }
            .padding(20)
        }
    }

    /// Visual representation of the communication path (Mac → Network → PLC)
    private var pathDiagram: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Communication Path")
                .font(.headline)

            HStack(spacing: 0) {
                pathNode(icon: "laptopcomputer", label: "This Mac", sublabel: "IDE")
                pathArrow(label: path.protocol_.rawValue)
                pathNode(icon: "network", label: "Network", sublabel: path.targetDevice)

                if !path.routingSegments.isEmpty {
                    ForEach(path.routingSegments) { segment in
                        pathArrow(label: segment.portType.rawValue)
                        pathNode(icon: "cpu", label: segment.portType.rawValue, sublabel: "Addr: \(segment.address)")
                    }
                } else {
                    pathArrow(label: "Backplane")
                    pathNode(icon: "cpu", label: "CPU", sublabel: "Slot \(path.slot)")
                }
            }
        }
    }

    private func pathNode(icon: String, label: String, sublabel: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(.accentColor)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
            Text(sublabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(width: 80, height: 70)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }

    private func pathArrow(label: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: "arrow.right")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text(label)
                .font(.system(size: 8))
                .foregroundColor(.secondary)
        }
        .frame(width: 70)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, weight: .medium))
        }
    }
}

// MARK: - Add Connection Path Sheet

struct AddConnectionPathSheet: View {
    @EnvironmentObject var commStore: CommManagerStore
    @Environment(\.dismiss) var dismiss

    @State private var pathName: String = "New Path"
    @State private var pathDescription: String = ""
    @State private var selectedDriverID: UUID?
    @State private var targetDevice: String = "192.168.1.1"
    @State private var slot: String = "0"
    @State private var isDefault: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Connection Path")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
            .padding()

            Divider()

            Form {
                LabeledContent("Path Name") {
                    TextField("My PLC Path", text: $pathName)
                        .frame(maxWidth: 250)
                }

                LabeledContent("Description") {
                    TextField("Optional description", text: $pathDescription)
                        .frame(maxWidth: 250)
                }

                LabeledContent("Driver") {
                    Picker("", selection: $selectedDriverID) {
                        Text("Select a driver...").tag(nil as UUID?)
                        ForEach(commStore.drivers) { driver in
                            Text("\(driver.name) (\(driver.protocol_.rawValue))").tag(driver.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                }

                LabeledContent("Target Address") {
                    TextField("192.168.1.1", text: $targetDevice)
                        .frame(maxWidth: 200)
                }

                LabeledContent("CPU Slot") {
                    TextField("0", text: $slot)
                        .frame(maxWidth: 80)
                }

                LabeledContent("Default Path") {
                    Toggle("Use as default connection path", isOn: $isDefault)
                        .toggleStyle(.checkbox)
                }
            }
            .padding()

            Divider()

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Path") { addPath() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedDriverID == nil || pathName.isEmpty)
            }
            .padding()
        }
        .frame(width: 550, height: 400)
    }

    private func addPath() {
        guard let driverID = selectedDriverID,
              let driver = commStore.drivers.first(where: { $0.id == driverID }) else { return }

        var path = ConnectionPath(name: pathName, driverID: driverID,
                                   targetDevice: targetDevice, protocol_: driver.protocol_)
        path.description = pathDescription
        path.slot = Int(slot) ?? 0
        path.isDefault = isDefault
        commStore.addConnectionPath(path)
        dismiss()
    }
}
