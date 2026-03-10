import Foundation
import Combine

/// Connection state for the PLC communication link.
enum PlcConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(ip: String, slot: UInt8)
    case error(message: String)

    var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected(let ip, let slot): return "Connected (\(ip) slot \(slot))"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var statusColor: String {
        switch self {
        case .disconnected: return "secondary"
        case .connecting: return "orange"
        case .connected: return "green"
        case .error: return "red"
        }
    }
}

/// A tag value read from the PLC.
struct LiveTagValue: Identifiable {
    var id: String { name }
    let name: String
    let value: String
    let dataType: String
    let timestamp: Date
    let quality: TagQuality
    var forced: Bool = false

    enum TagQuality {
        case good
        case uncertain
        case bad
    }
}

/// Manages the connection to a physical Allen-Bradley PLC.
///
/// In a full build, this would use the Rust plc-comms crate via UniFFI.
/// For now it provides a simulation/mock mode for UI development.
class ConnectionManager: ObservableObject {
    @Published var connectionState: PlcConnectionState = .disconnected
    @Published var ipAddress: String = "192.168.1.1"
    @Published var slot: UInt8 = 0
    @Published var timeout: UInt32 = 5000

    // Watch window
    @Published var watchedTags: [String] = []
    @Published var liveTagValues: [LiveTagValue] = []
    @Published var pollIntervalMs: Int = 500
    @Published var isPolling: Bool = false

    // Force table
    @Published var forcedTags: [String: String] = [:]

    // Diagnostics
    @Published var packetsSent: UInt64 = 0
    @Published var packetsReceived: UInt64 = 0
    @Published var lastResponseTimeMs: Double = 0
    @Published var connectionUptime: TimeInterval = 0

    private var pollTimer: Timer?
    private var uptimeTimer: Timer?
    private var connectTime: Date?
    private var outputHandler: ((String) -> Void)?

    func setOutputHandler(_ handler: @escaping (String) -> Void) {
        outputHandler = handler
    }

    // MARK: - Connection

    func connect() {
        guard !connectionState.isConnected else { return }
        connectionState = .connecting
        outputHandler?("[Comms] Connecting to \(ipAddress) slot \(slot)...")

        // In production, this calls plc-comms via UniFFI:
        //   Task { let result = await PlcComms.connect(ip: ipAddress, slot: slot, timeout: timeout) }
        //
        // For now, simulate a connection attempt:
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }

            // Validate IP format
            let parts = self.ipAddress.split(separator: ".")
            if parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) {
                self.connectionState = .connected(ip: self.ipAddress, slot: self.slot)
                self.connectTime = Date()
                self.startUptimeTimer()
                self.outputHandler?("[Comms] Connected to \(self.ipAddress) slot \(self.slot)")
                self.outputHandler?("[Comms] Session registered, ready for tag operations")
            } else {
                self.connectionState = .error(message: "Invalid IP address")
                self.outputHandler?("[Comms] Connection failed: Invalid IP address format")
            }
        }
    }

    func disconnect() {
        stopPolling()
        stopUptimeTimer()
        connectionState = .disconnected
        liveTagValues = []
        connectTime = nil
        connectionUptime = 0
        outputHandler?("[Comms] Disconnected")
    }

    func testConnection() {
        outputHandler?("[Comms] Testing connection to \(ipAddress)...")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            let parts = self.ipAddress.split(separator: ".")
            if parts.count == 4, parts.allSatisfy({ UInt8($0) != nil }) {
                self.outputHandler?("[Comms] Ping OK — \(self.ipAddress) is reachable")
                self.outputHandler?("[Comms] EtherNet/IP session registration: OK")
            } else {
                self.outputHandler?("[Comms] Test failed — invalid IP address")
            }
        }
    }

    // MARK: - Tag Watch

    func addWatchTag(_ tagName: String) {
        guard !tagName.isEmpty, !watchedTags.contains(tagName) else { return }
        watchedTags.append(tagName)
        outputHandler?("[Watch] Added tag: \(tagName)")
    }

    func removeWatchTag(_ tagName: String) {
        watchedTags.removeAll { $0 == tagName }
        liveTagValues.removeAll { $0.name == tagName }
        forcedTags.removeValue(forKey: tagName)
    }

    func addProjectTags(from project: PlcProject?) {
        guard let project = project else { return }
        for tag in project.tagDatabase.tags {
            if case .controller = tag.scope {
                addWatchTag(tag.name)
            }
        }
    }

    func startPolling() {
        guard connectionState.isConnected else { return }
        isPolling = true
        pollTags()
        pollTimer = Timer.scheduledTimer(withTimeInterval: Double(pollIntervalMs) / 1000.0, repeats: true) { [weak self] _ in
            self?.pollTags()
        }
        outputHandler?("[Watch] Polling started (\(pollIntervalMs)ms interval, \(watchedTags.count) tags)")
    }

    func stopPolling() {
        isPolling = false
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func pollTags() {
        guard connectionState.isConnected else { return }

        // In production: batch read via plc-comms Multiple Service Packet
        //   Task { let values = await PlcComms.readTags(names: watchedTags) }
        //
        // For now, generate simulated values for UI testing:
        packetsSent += 1
        let startTime = Date()

        var newValues: [LiveTagValue] = []
        for tagName in watchedTags {
            if let forcedValue = forcedTags[tagName] {
                newValues.append(LiveTagValue(
                    name: tagName,
                    value: forcedValue,
                    dataType: inferDataType(tagName),
                    timestamp: Date(),
                    quality: .good,
                    forced: true
                ))
            } else {
                newValues.append(LiveTagValue(
                    name: tagName,
                    value: simulatedValue(for: tagName),
                    dataType: inferDataType(tagName),
                    timestamp: Date(),
                    quality: .good
                ))
            }
        }

        packetsReceived += 1
        lastResponseTimeMs = Date().timeIntervalSince(startTime) * 1000

        liveTagValues = newValues
    }

    // MARK: - Force Table

    func forceTag(name: String, value: String) {
        forcedTags[name] = value
        outputHandler?("[Force] \(name) = \(value)")
    }

    func removeForce(name: String) {
        forcedTags.removeValue(forKey: name)
        outputHandler?("[Force] Removed force on \(name)")
    }

    func removeAllForces() {
        forcedTags.removeAll()
        outputHandler?("[Force] All forces removed")
    }

    // MARK: - Write Tag

    func writeTag(name: String, value: String) {
        guard connectionState.isConnected else {
            outputHandler?("[Comms] Cannot write: not connected")
            return
        }
        // In production: PlcComms.writeTag(name: name, value: value)
        outputHandler?("[Write] \(name) = \(value)")
        packetsSent += 1
        packetsReceived += 1
    }

    // MARK: - Helpers

    private func startUptimeTimer() {
        uptimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let ct = self.connectTime else { return }
            self.connectionUptime = Date().timeIntervalSince(ct)
        }
    }

    private func stopUptimeTimer() {
        uptimeTimer?.invalidate()
        uptimeTimer = nil
    }

    private func simulatedValue(for tagName: String) -> String {
        // Generate plausible values based on tag naming conventions
        let lower = tagName.lowercased()
        if lower.hasSuffix(".dn") || lower.hasSuffix(".en") || lower.hasSuffix(".tt") ||
           lower.contains("start") || lower.contains("stop") || lower.contains("run") ||
           lower.contains("fault") || lower.contains("enable") {
            return Bool.random() ? "1" : "0"
        } else if lower.hasSuffix(".acc") || lower.hasSuffix(".pre") {
            return "\(Int.random(in: 0...5000))"
        } else if lower.contains("temp") || lower.contains("speed") || lower.contains("pressure") {
            return String(format: "%.1f", Double.random(in: 0...100))
        } else {
            return "\(Int.random(in: 0...1000))"
        }
    }

    private func inferDataType(_ tagName: String) -> String {
        let lower = tagName.lowercased()
        if lower.hasSuffix(".dn") || lower.hasSuffix(".en") || lower.hasSuffix(".tt") ||
           lower.contains("start") || lower.contains("stop") || lower.contains("run") {
            return "BOOL"
        } else if lower.contains("temp") || lower.contains("speed") || lower.contains("pressure") {
            return "REAL"
        } else {
            return "DINT"
        }
    }
}
