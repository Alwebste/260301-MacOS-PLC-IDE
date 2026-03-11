// NetworkBrowserView.swift
// PLCCommManager - PLC Communications Manager
// Network browser for discovering PLCs and industrial devices on the network

import SwiftUI

struct NetworkBrowserView: View {
    @EnvironmentObject var commStore: CommManagerStore
    @State private var scanSubnet: String = "192.168.1"
    @State private var scanProtocol: CommProtocol = .ethernetIP
    @State private var selectedDeviceID: UUID?
    @State private var showCreateDriverFromDevice = false

    var body: some View {
        VStack(spacing: 0) {
            // Scan toolbar
            scanToolbar
            Divider()

            HSplitView {
                // Device list
                deviceListPanel
                    .frame(minWidth: 400)

                // Device detail
                deviceDetailPanel
                    .frame(minWidth: 350)
            }
        }
    }

    // MARK: - Scan Toolbar

    private var scanToolbar: some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(.secondary)

            Text("Subnet:")
                .font(.system(size: 12))
            TextField("192.168.1", text: $scanSubnet)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
            Text(".0/24")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Picker("Protocol:", selection: $scanProtocol) {
                ForEach(CommProtocol.allCases) { proto in
                    Text(proto.rawValue).tag(proto)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 180)

            if commStore.isScanning {
                Button("Stop Scan") {
                    commStore.stopNetworkScan()
                }
                .buttonStyle(.bordered)
                .tint(.red)

                ProgressView()
                    .controlSize(.small)
            } else {
                Button(action: {
                    commStore.startNetworkScan(subnet: scanSubnet, protocol_: scanProtocol)
                }) {
                    Label("Scan Network", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()

            Text("\(commStore.discoveredDevices.count) device(s)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Device List

    private var deviceListPanel: some View {
        VStack(spacing: 0) {
            if commStore.discoveredDevices.isEmpty && !commStore.isScanning {
                emptyState
            } else {
                List(selection: $selectedDeviceID) {
                    ForEach(commStore.discoveredDevices) { device in
                        DeviceRowView(device: device)
                            .tag(device.id)
                            .contextMenu {
                                Button("Create Driver from Device...") {
                                    selectedDeviceID = device.id
                                    showCreateDriverFromDevice = true
                                }
                                Button("Copy IP Address") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(device.ipAddress, forType: .string)
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
            Image(systemName: "network.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No Devices Discovered")
                .font(.title3.weight(.semibold))
            Text("Enter a subnet and click 'Scan Network' to discover\nPLCs and industrial devices using EtherNet/IP ListIdentity broadcasts.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Device Detail

    @ViewBuilder
    private var deviceDetailPanel: some View {
        if let deviceID = selectedDeviceID,
           let device = commStore.discoveredDevices.first(where: { $0.id == deviceID }) {
            DeviceDetailView(device: device)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text("Select a device to view details")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Device Row

struct DeviceRowView: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 10) {
            // Family icon
            Image(systemName: familyIcon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.productName)
                    .font(.system(size: 13, weight: .medium))
                HStack(spacing: 8) {
                    Text(device.ipAddress)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(device.vendorName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    if !device.firmwareRevision.isEmpty {
                        Text("v\(device.firmwareRevision)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            // Response time
            Text(String(format: "%.1f ms", device.responseTimeMs))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var familyIcon: String {
        switch device.family {
        case .controlLogix: return "cpu"
        case .compactLogix: return "square.stack.3d.up"
        case .microLogix: return "memorychip"
        case .slc500: return "server.rack"
        case .micro800: return "square.stack"
        case .generic: return "desktopcomputer"
        }
    }
}

// MARK: - Device Detail View

struct DeviceDetailView: View {
    @EnvironmentObject var commStore: CommManagerStore
    let device: DiscoveredDevice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Device header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.productName)
                            .font(.title2.weight(.semibold))
                        Text("\(device.vendorName) • \(device.family.rawValue)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Create Driver") {
                        createDriverFromDevice()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Divider()

                // Device info grid
                VStack(alignment: .leading, spacing: 8) {
                    Text("Device Information")
                        .font(.headline)

                    infoRow("IP Address", device.ipAddress)
                    infoRow("MAC Address", device.macAddress.isEmpty ? "—" : device.macAddress)
                    infoRow("Firmware", device.firmwareRevision.isEmpty ? "—" : "v\(device.firmwareRevision)")
                    infoRow("Serial Number", device.serialNumber.isEmpty ? "—" : device.serialNumber)
                    infoRow("Protocol", device.protocol_.rawValue)
                    infoRow("Response Time", String(format: "%.1f ms", device.responseTimeMs))
                    infoRow("Discovered", device.discoveredAt.formatted(date: .abbreviated, time: .shortened))
                }

                Divider()

                // Chassis modules
                if !device.modules.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chassis Modules")
                            .font(.headline)

                        ForEach(device.modules) { module in
                            HStack(spacing: 12) {
                                Text("Slot \(module.slot)")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .frame(width: 50, alignment: .trailing)
                                    .foregroundColor(.secondary)

                                Image(systemName: module.status.icon)
                                    .foregroundColor(module.status == .running ? .green : .orange)
                                    .font(.system(size: 12))

                                VStack(alignment: .leading) {
                                    Text(module.catalogNumber)
                                        .font(.system(size: 12, weight: .medium))
                                    if !module.description.isEmpty {
                                        Text(module.description)
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }

    private func createDriverFromDevice() {
        var driver = CommDriver(name: device.productName, protocol_: device.protocol_)
        var config = EthernetIPConfig()
        config.ipAddress = device.ipAddress
        config.plcFamily = device.family
        driver.ethernetIPConfig = config
        commStore.addDriver(driver)
    }
}
