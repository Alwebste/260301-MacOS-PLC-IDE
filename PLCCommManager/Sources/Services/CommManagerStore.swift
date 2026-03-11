// CommManagerStore.swift
// PLCCommManager - PLC Communications Manager
// Central state management for all communications — drivers, connections, diagnostics

import Foundation
import Combine

/// Central store for all PLC communication state
/// Acts as the single source of truth for drivers, discovered devices, paths, and diagnostics.
class CommManagerStore: ObservableObject {

    // MARK: - Published State

    /// All configured communication drivers
    @Published var drivers: [CommDriver] = []

    /// Devices discovered via network scanning
    @Published var discoveredDevices: [DiscoveredDevice] = []

    /// Saved connection paths
    @Published var connectionPaths: [ConnectionPath] = []

    /// Diagnostic event log
    @Published var diagnosticEvents: [DiagnosticEvent] = []

    /// Per-driver communication statistics
    @Published var statistics: [UUID: CommStatistics] = [:]

    /// Is a network scan currently in progress?
    @Published var isScanning: Bool = false

    /// Currently selected driver in the UI
    @Published var selectedDriverID: UUID?

    // MARK: - Computed Properties

    var activeConnectionCount: Int {
        drivers.filter { $0.state == .connected }.count
    }

    var hasAnyConnection: Bool {
        activeConnectionCount > 0
    }

    var enabledDrivers: [CommDriver] {
        drivers.filter { $0.isEnabled }
    }

    var selectedDriver: CommDriver? {
        guard let id = selectedDriverID else { return nil }
        return drivers.first { $0.id == id }
    }

    // MARK: - Initialization

    init() {
        loadSavedConfiguration()
    }

    // MARK: - Driver Management

    func addDriver(_ driver: CommDriver) {
        drivers.append(driver)
        statistics[driver.id] = CommStatistics()
        logEvent(.info, source: "CommManager", message: "Driver '\(driver.name)' added (\(driver.protocol_.rawValue))")
        saveConfiguration()
    }

    func removeDriver(id: UUID) {
        guard let driver = drivers.first(where: { $0.id == id }) else { return }
        if driver.state == .connected {
            disconnectDriver(id: id)
        }
        drivers.removeAll { $0.id == id }
        statistics.removeValue(forKey: id)
        connectionPaths.removeAll { $0.driverID == id }
        logEvent(.info, source: "CommManager", message: "Driver '\(driver.name)' removed")
        saveConfiguration()
    }

    func updateDriver(_ driver: CommDriver) {
        guard let index = drivers.firstIndex(where: { $0.id == driver.id }) else { return }
        var updated = driver
        updated.lastModified = Date()
        drivers[index] = updated
        saveConfiguration()
    }

    func duplicateDriver(id: UUID) {
        guard let original = drivers.first(where: { $0.id == id }) else { return }
        var copy = original
        copy.id // keep the ID from init
        let newDriver = CommDriver(name: "\(original.name) (Copy)", protocol_: original.protocol_)
        // Copy config from original
        var dupe = newDriver
        dupe.ethernetIPConfig = original.ethernetIPConfig
        dupe.modbusTCPConfig = original.modbusTCPConfig
        dupe.opcUAConfig = original.opcUAConfig
        dupe.serialDF1Config = original.serialDF1Config
        dupe.autoStart = original.autoStart
        addDriver(dupe)
    }

    // MARK: - Connection Operations

    func connectDriver(id: UUID) {
        guard let index = drivers.firstIndex(where: { $0.id == id }) else { return }
        drivers[index].state = .connecting
        logEvent(.info, source: drivers[index].name, message: "Connecting...", driverID: id)

        // Simulate connection (in real implementation, this calls the EtherNet/IP stack)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self,
                  let idx = self.drivers.firstIndex(where: { $0.id == id }) else { return }
            self.drivers[idx].state = .connected
            self.drivers[idx].connectedDeviceCount = 1
            self.logEvent(.info, source: self.drivers[idx].name,
                         message: "Connected successfully", driverID: id)
        }
    }

    func disconnectDriver(id: UUID) {
        guard let index = drivers.firstIndex(where: { $0.id == id }) else { return }
        drivers[index].state = .disconnected
        drivers[index].connectedDeviceCount = 0
        logEvent(.info, source: drivers[index].name, message: "Disconnected", driverID: id)
    }

    func testConnection(id: UUID, completion: @escaping (Bool, String) -> Void) {
        guard let driver = drivers.first(where: { $0.id == id }) else {
            completion(false, "Driver not found")
            return
        }
        logEvent(.info, source: driver.name, message: "Testing connection...", driverID: id)

        // Simulate connection test
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            let success = true // In real implementation, attempt actual connection
            let message = success ? "Connection test passed" : "Connection test failed"
            self?.logEvent(success ? .info : .error, source: driver.name,
                          message: message, driverID: id)
            completion(success, message)
        }
    }

    // MARK: - Network Discovery

    func startNetworkScan(subnet: String = "192.168.1", protocol_: CommProtocol = .ethernetIP) {
        isScanning = true
        discoveredDevices.removeAll()
        logEvent(.info, source: "Network Scanner", message: "Scanning \(subnet).0/24 for \(protocol_.rawValue) devices...")

        // Simulate device discovery (real implementation uses EtherNet/IP ListIdentity broadcast)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self else { return }

            // Example discovered devices for demonstration
            let sampleDevices: [DiscoveredDevice] = [
                self.makeSampleDevice(ip: "\(subnet).10", name: "1756-L83E/B",
                                      vendor: "Allen-Bradley", family: .controlLogix,
                                      firmware: "32.011", responseMs: 2.4),
                self.makeSampleDevice(ip: "\(subnet).20", name: "1769-L33ER",
                                      vendor: "Allen-Bradley", family: .compactLogix,
                                      firmware: "35.011", responseMs: 3.1),
                self.makeSampleDevice(ip: "\(subnet).30", name: "1769-L24ER-QB1B",
                                      vendor: "Allen-Bradley", family: .compactLogix,
                                      firmware: "34.014", responseMs: 4.7),
            ]

            self.discoveredDevices = sampleDevices
            self.isScanning = false
            self.logEvent(.info, source: "Network Scanner",
                         message: "Scan complete. Found \(sampleDevices.count) devices.")
        }
    }

    func stopNetworkScan() {
        isScanning = false
        logEvent(.info, source: "Network Scanner", message: "Scan cancelled by user")
    }

    private func makeSampleDevice(ip: String, name: String, vendor: String,
                                   family: PLCFamily, firmware: String, responseMs: Double) -> DiscoveredDevice {
        var device = DiscoveredDevice(ipAddress: ip, vendorName: vendor, productName: name, family: family)
        device.firmwareRevision = firmware
        device.responseTimeMs = responseMs
        device.state = .disconnected
        device.modules = [
            ChassisModule(slot: 0, catalogNumber: name, description: "CPU Module"),
            ChassisModule(slot: 1, catalogNumber: "1756-IB16", description: "16-Point Digital Input"),
            ChassisModule(slot: 2, catalogNumber: "1756-OB16E", description: "16-Point Digital Output"),
            ChassisModule(slot: 3, catalogNumber: "1756-IF8", description: "8-Channel Analog Input"),
        ]
        return device
    }

    // MARK: - Connection Paths

    func addConnectionPath(_ path: ConnectionPath) {
        connectionPaths.append(path)
        logEvent(.info, source: "CommManager", message: "Connection path '\(path.name)' added")
        saveConfiguration()
    }

    func removeConnectionPath(id: UUID) {
        connectionPaths.removeAll { $0.id == id }
        saveConfiguration()
    }

    func setDefaultPath(id: UUID) {
        for i in connectionPaths.indices {
            connectionPaths[i].isDefault = (connectionPaths[i].id == id)
        }
        saveConfiguration()
    }

    // MARK: - Diagnostics

    func logEvent(_ severity: DiagnosticSeverity, source: String, message: String,
                  details: String = "", driverID: UUID? = nil) {
        let event = DiagnosticEvent(severity: severity, source: source, message: message,
                                    details: details, driverID: driverID)
        diagnosticEvents.insert(event, at: 0)

        // Keep log bounded
        if diagnosticEvents.count > 5000 {
            diagnosticEvents = Array(diagnosticEvents.prefix(5000))
        }
    }

    func clearDiagnostics() {
        diagnosticEvents.removeAll()
    }

    func clearDiagnostics(for driverID: UUID) {
        diagnosticEvents.removeAll { $0.driverID == driverID }
    }

    // MARK: - Persistence

    private func saveConfiguration() {
        // In production, serialize drivers and paths to UserDefaults or a .plccomm file
        // For now, state is held in memory
    }

    private func loadSavedConfiguration() {
        // In production, deserialize from UserDefaults or file
        // Seed with a welcome diagnostic event
        logEvent(.info, source: "CommManager",
                 message: "PLC Communications Manager initialized. Configure drivers to connect to PLCs.")
    }
}
