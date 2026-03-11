// CommDriver.swift
// PLCCommManager - PLC Communications Manager
// Communication driver model — equivalent to RSLinx driver concepts

import Foundation

// MARK: - Communication Driver

/// A configured communication driver instance (similar to RSLinx driver)
/// Each driver represents one configured communication channel to PLC devices.
struct CommDriver: Identifiable, Codable {
    let id: UUID
    var name: String
    var protocol_: CommProtocol
    var isEnabled: Bool
    var autoStart: Bool
    var createdAt: Date
    var lastModified: Date

    // Protocol-specific configuration
    var ethernetIPConfig: EthernetIPConfig?
    var modbusTCPConfig: ModbusTCPConfig?
    var opcUAConfig: OPCUAConfig?
    var serialDF1Config: SerialDF1Config?

    // Runtime state (not persisted)
    var state: ConnectionState = .disconnected
    var connectedDeviceCount: Int = 0
    var lastError: String?
    var uptimeSeconds: TimeInterval = 0

    init(name: String, protocol_: CommProtocol) {
        self.id = UUID()
        self.name = name
        self.protocol_ = protocol_
        self.isEnabled = true
        self.autoStart = false
        self.createdAt = Date()
        self.lastModified = Date()

        // Initialize default config for the selected protocol
        switch protocol_ {
        case .ethernetIP, .cip:
            self.ethernetIPConfig = EthernetIPConfig()
        case .modbusTCP:
            self.modbusTCPConfig = ModbusTCPConfig()
        case .opcUA:
            self.opcUAConfig = OPCUAConfig()
        case .serialDF1:
            self.serialDF1Config = SerialDF1Config()
        }
    }
}

// MARK: - EtherNet/IP Configuration

struct EthernetIPConfig: Codable {
    var ipAddress: String = "192.168.1.1"
    var port: UInt16 = 44818
    var slot: Int = 0
    var connectionTimeout: TimeInterval = 5.0
    var requestTimeout: TimeInterval = 3.0
    var connectionSize: Int = 508
    var plcFamily: PLCFamily = .controlLogix
    var useDHCP: Bool = false

    // CIP routing path
    var routingPath: [CIPRoutingSegment] = []

    // Advanced
    var enableKeepAlive: Bool = true
    var keepAliveInterval: TimeInterval = 30.0
    var maxRetries: Int = 3
    var retryDelay: TimeInterval = 1.0
    var enableForwardOpen: Bool = true
    var rpi: UInt32 = 100_000 // Requested Packet Interval in microseconds (100ms)

    // Subnet scanning
    var subnetMask: String = "255.255.255.0"
    var enableBroadcastDiscovery: Bool = true
}

/// CIP routing segment for multi-hop routing through chassis backplanes
struct CIPRoutingSegment: Identifiable, Codable {
    let id: UUID
    var portType: CIPPortType
    var address: String // slot number or IP address

    init(portType: CIPPortType = .backplane, address: String = "0") {
        self.id = UUID()
        self.portType = portType
        self.address = address
    }
}

enum CIPPortType: String, CaseIterable, Identifiable, Codable {
    case backplane = "Backplane"
    case ethernetPort = "Ethernet Port"
    case serialPort = "Serial Port"

    var id: String { rawValue }
}

// MARK: - Modbus TCP Configuration

struct ModbusTCPConfig: Codable {
    var ipAddress: String = "192.168.1.1"
    var port: UInt16 = 502
    var unitID: UInt8 = 1
    var connectionTimeout: TimeInterval = 5.0
    var responseTimeout: TimeInterval = 3.0
    var maxRetries: Int = 3

    // Polling
    var defaultPollRate: TimeInterval = 1.0
    var maxRegistersPerRequest: UInt16 = 125
    var maxCoilsPerRequest: UInt16 = 2000

    // Register map
    var byteOrder: ModbusByteOrder = .bigEndian
    var wordOrder: ModbusWordOrder = .highFirst
    var zeroBasedAddressing: Bool = true
}

enum ModbusByteOrder: String, CaseIterable, Identifiable, Codable {
    case bigEndian = "Big Endian (AB)"
    case littleEndian = "Little Endian (BA)"
    var id: String { rawValue }
}

enum ModbusWordOrder: String, CaseIterable, Identifiable, Codable {
    case highFirst = "High Word First (AB CD)"
    case lowFirst = "Low Word First (CD AB)"
    var id: String { rawValue }
}

// MARK: - OPC UA Configuration

struct OPCUAConfig: Codable {
    var endpointURL: String = "opc.tcp://192.168.1.1:4840"
    var securityMode: OPCSecurityMode = .none
    var authMode: OPCAuthMode = .anonymous
    var username: String = ""
    var password: String = ""
    var certificatePath: String = ""
    var privateKeyPath: String = ""
    var connectionTimeout: TimeInterval = 10.0
    var sessionTimeout: TimeInterval = 60.0
    var publishingInterval: TimeInterval = 1.0
    var maxSubscriptions: Int = 10
    var maxMonitoredItems: Int = 1000
}

// MARK: - Serial DF1 Configuration

struct SerialDF1Config: Codable {
    var portName: String = "/dev/tty.usbserial"
    var baudRate: BaudRate = .b19200
    var dataBits: DataBits = .eight
    var parity: SerialParity = .none
    var stopBits: StopBits = .one
    var stationAddress: UInt8 = 0
    var responseTimeout: TimeInterval = 3.0
    var maxRetries: Int = 3

    // DF1 specific
    var enableChecksum: Bool = true
    var enableBCC: Bool = false // Block Check Character vs CRC
    var enableDuplicateDetection: Bool = true
}
