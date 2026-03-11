// DiscoveredDevice.swift
// PLCCommManager - PLC Communications Manager
// Model for devices found via network scanning and browsing

import Foundation

// MARK: - Discovered Device

/// A PLC or industrial device discovered on the network
struct DiscoveredDevice: Identifiable, Codable {
    let id: UUID
    var ipAddress: String
    var macAddress: String
    var hostName: String
    var vendorName: String
    var productName: String
    var productType: String
    var serialNumber: String
    var firmwareRevision: String
    var family: PLCFamily
    var protocol_: CommProtocol
    var slot: Int
    var state: ConnectionState
    var discoveredAt: Date
    var lastSeen: Date
    var responseTimeMs: Double

    // Module information (for chassis-based systems)
    var modules: [ChassisModule]

    init(
        ipAddress: String,
        vendorName: String = "Unknown",
        productName: String = "Unknown",
        family: PLCFamily = .generic,
        protocol_: CommProtocol = .ethernetIP
    ) {
        self.id = UUID()
        self.ipAddress = ipAddress
        self.macAddress = ""
        self.hostName = ""
        self.vendorName = vendorName
        self.productName = productName
        self.productType = ""
        self.serialNumber = ""
        self.firmwareRevision = ""
        self.family = family
        self.protocol_ = protocol_
        self.slot = 0
        self.state = .disconnected
        self.discoveredAt = Date()
        self.lastSeen = Date()
        self.responseTimeMs = 0.0
        self.modules = []
    }
}

// MARK: - Chassis Module

/// A module in a ControlLogix/CompactLogix chassis slot
struct ChassisModule: Identifiable, Codable {
    let id: UUID
    var slot: Int
    var catalogNumber: String
    var vendor: String
    var productType: String
    var firmwareRevision: String
    var status: ModuleStatus
    var description: String

    init(slot: Int, catalogNumber: String, description: String = "") {
        self.id = UUID()
        self.slot = slot
        self.catalogNumber = catalogNumber
        self.vendor = "Allen-Bradley"
        self.productType = ""
        self.firmwareRevision = ""
        self.status = .running
        self.description = description
    }
}

enum ModuleStatus: String, Codable {
    case running = "Running"
    case faulted = "Faulted"
    case programming = "Programming"
    case standby = "Standby"
    case unknown = "Unknown"

    var icon: String {
        switch self {
        case .running: return "checkmark.circle.fill"
        case .faulted: return "exclamationmark.triangle.fill"
        case .programming: return "arrow.down.circle.fill"
        case .standby: return "pause.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Connection Path

/// A saved communication path to a PLC (similar to RSLinx comm path)
struct ConnectionPath: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var driverID: UUID
    var targetDevice: String // IP address or serial port
    var protocol_: CommProtocol
    var slot: Int
    var routingSegments: [CIPRoutingSegment]
    var isDefault: Bool
    var lastUsed: Date?
    var lastStatus: ConnectionState

    // Display-friendly path string
    var pathString: String {
        var parts: [String] = []
        switch protocol_ {
        case .ethernetIP, .cip:
            parts.append(targetDevice)
            if !routingSegments.isEmpty {
                for seg in routingSegments {
                    parts.append("\(seg.portType.rawValue):\(seg.address)")
                }
            } else {
                parts.append("Backplane, Slot \(slot)")
            }
        case .modbusTCP:
            parts.append("\(targetDevice):502")
        case .opcUA:
            parts.append(targetDevice)
        case .serialDF1:
            parts.append(targetDevice)
        }
        return parts.joined(separator: " → ")
    }

    init(name: String, driverID: UUID, targetDevice: String, protocol_: CommProtocol) {
        self.id = UUID()
        self.name = name
        self.description = ""
        self.driverID = driverID
        self.targetDevice = targetDevice
        self.protocol_ = protocol_
        self.slot = 0
        self.routingSegments = []
        self.isDefault = false
        self.lastUsed = nil
        self.lastStatus = .disconnected
    }
}

// MARK: - Diagnostic Event

/// A diagnostic log entry from the communications system
struct DiagnosticEvent: Identifiable, Codable {
    let id: UUID
    var timestamp: Date
    var severity: DiagnosticSeverity
    var source: String // driver name or system component
    var message: String
    var details: String
    var driverID: UUID?

    init(severity: DiagnosticSeverity, source: String, message: String, details: String = "", driverID: UUID? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.severity = severity
        self.source = source
        self.message = message
        self.details = details
        self.driverID = driverID
    }
}

// MARK: - Communication Statistics

/// Runtime statistics for a communication channel
struct CommStatistics: Codable {
    var packetsSent: UInt64 = 0
    var packetsReceived: UInt64 = 0
    var packetsError: UInt64 = 0
    var bytesTransferred: UInt64 = 0
    var averageResponseMs: Double = 0.0
    var minResponseMs: Double = Double.infinity
    var maxResponseMs: Double = 0.0
    var connectionUptime: TimeInterval = 0
    var reconnectCount: Int = 0
    var lastPacketTime: Date?

    var errorRate: Double {
        let total = packetsSent + packetsReceived
        guard total > 0 else { return 0 }
        return Double(packetsError) / Double(total) * 100.0
    }

    var successRate: Double {
        return 100.0 - errorRate
    }
}
