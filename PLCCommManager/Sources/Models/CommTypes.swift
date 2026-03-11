// CommTypes.swift
// PLCCommManager - PLC Communications Manager
// Core types for PLC communication protocols, drivers, and connections

import Foundation

// MARK: - Communication Protocols

/// Supported industrial communication protocols
enum CommProtocol: String, CaseIterable, Identifiable, Codable {
    case ethernetIP = "EtherNet/IP"
    case modbusTCP = "Modbus TCP"
    case opcUA = "OPC UA"
    case serialDF1 = "Serial DF1"
    case cip = "CIP (Generic)"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .ethernetIP: return "network"
        case .modbusTCP: return "cable.connector.horizontal"
        case .opcUA: return "server.rack"
        case .serialDF1: return "cable.connector"
        case .cip: return "cpu"
        }
    }

    var defaultPort: UInt16 {
        switch self {
        case .ethernetIP: return 44818
        case .modbusTCP: return 502
        case .opcUA: return 4840
        case .serialDF1: return 0 // serial, no TCP port
        case .cip: return 44818
        }
    }

    var description: String {
        switch self {
        case .ethernetIP:
            return "Allen-Bradley EtherNet/IP (CIP over Ethernet). Primary protocol for ControlLogix and CompactLogix."
        case .modbusTCP:
            return "Modbus TCP/IP. Universal protocol for PLCs, VFDs, sensors, and third-party devices."
        case .opcUA:
            return "OPC Unified Architecture. Secure, platform-independent industrial data exchange."
        case .serialDF1:
            return "Allen-Bradley DF1 over RS-232/RS-485. Legacy serial protocol for SLC/MicroLogix."
        case .cip:
            return "Common Industrial Protocol. Generic CIP messaging for ODVA-compliant devices."
        }
    }
}

// MARK: - Connection State

/// Current state of a communication link
enum ConnectionState: String, Codable {
    case disconnected = "Disconnected"
    case connecting = "Connecting"
    case connected = "Connected"
    case error = "Error"
    case timeout = "Timeout"
    case discovering = "Discovering"

    var color: String {
        switch self {
        case .disconnected: return "gray"
        case .connecting: return "orange"
        case .connected: return "green"
        case .error: return "red"
        case .timeout: return "yellow"
        case .discovering: return "blue"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return "circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .timeout: return "clock.badge.exclamationmark"
        case .discovering: return "magnifyingglass"
        }
    }
}

// MARK: - PLC Family

/// Supported PLC hardware families
enum PLCFamily: String, CaseIterable, Identifiable, Codable {
    case controlLogix = "ControlLogix (1756)"
    case compactLogix = "CompactLogix (1769)"
    case microLogix = "MicroLogix (1100/1400)"
    case slc500 = "SLC 500"
    case micro800 = "Micro800"
    case generic = "Generic Device"

    var id: String { rawValue }

    var supportedProtocols: [CommProtocol] {
        switch self {
        case .controlLogix: return [.ethernetIP, .cip]
        case .compactLogix: return [.ethernetIP, .cip]
        case .microLogix: return [.ethernetIP, .serialDF1]
        case .slc500: return [.serialDF1, .ethernetIP]
        case .micro800: return [.ethernetIP, .modbusTCP]
        case .generic: return CommProtocol.allCases
        }
    }
}

// MARK: - Baud Rate (Serial)

enum BaudRate: Int, CaseIterable, Identifiable, Codable {
    case b9600 = 9600
    case b19200 = 19200
    case b38400 = 38400
    case b57600 = 57600
    case b115200 = 115200

    var id: Int { rawValue }
    var display: String { "\(rawValue)" }
}

// MARK: - Parity

enum SerialParity: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case even = "Even"
    case odd = "Odd"

    var id: String { rawValue }
}

// MARK: - Data Bits

enum DataBits: Int, CaseIterable, Identifiable, Codable {
    case seven = 7
    case eight = 8

    var id: Int { rawValue }
    var display: String { "\(rawValue)" }
}

// MARK: - Stop Bits

enum StopBits: Int, CaseIterable, Identifiable, Codable {
    case one = 1
    case two = 2

    var id: Int { rawValue }
    var display: String { "\(rawValue)" }
}

// MARK: - OPC UA Security Mode

enum OPCSecurityMode: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case sign = "Sign"
    case signAndEncrypt = "Sign & Encrypt"

    var id: String { rawValue }
}

// MARK: - OPC UA Authentication

enum OPCAuthMode: String, CaseIterable, Identifiable, Codable {
    case anonymous = "Anonymous"
    case usernamePassword = "Username/Password"
    case certificate = "Certificate"

    var id: String { rawValue }
}

// MARK: - Diagnostic Severity

enum DiagnosticSeverity: String, Codable {
    case info = "Info"
    case warning = "Warning"
    case error = "Error"
    case critical = "Critical"

    var icon: String {
        switch self {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        case .critical: return "exclamationmark.octagon"
        }
    }

    var color: String {
        switch self {
        case .info: return "blue"
        case .warning: return "orange"
        case .error: return "red"
        case .critical: return "red"
        }
    }
}
