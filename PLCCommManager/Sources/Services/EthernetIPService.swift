// EthernetIPService.swift
// PLCCommManager - PLC Communications Manager
// EtherNet/IP protocol implementation — CIP explicit messaging for Allen-Bradley PLCs

import Foundation

// MARK: - EtherNet/IP Protocol Constants

/// EtherNet/IP encapsulation commands (per ODVA specification)
enum EIPCommand: UInt16 {
    case nop                = 0x0000
    case listServices       = 0x0004
    case listIdentity       = 0x0063
    case listInterfaces     = 0x0064
    case registerSession    = 0x0065
    case unregisterSession  = 0x0066
    case sendRRData         = 0x006F  // Send Request/Reply Data (explicit messaging)
    case sendUnitData       = 0x0070  // Send Unit Data (connected messaging)
}

/// CIP service codes
enum CIPService: UInt8 {
    case getAttributeAll    = 0x01
    case getAttributeSingle = 0x0E
    case setAttributeSingle = 0x10
    case forwardOpen        = 0x54
    case forwardClose       = 0x4E
    case readTag            = 0x4C
    case writeTag           = 0x4D
    case readTagFragmented  = 0x52
    case writeTagFragmented = 0x53
    case readModifyWriteTag = 0x4E
    case multipleService    = 0x0A
}

/// CIP data types used by Logix controllers
enum CIPDataType: UInt16 {
    case bool   = 0x00C1
    case sint   = 0x00C2
    case int    = 0x00C3
    case dint   = 0x00C4
    case lint   = 0x00C5
    case real   = 0x00CA
    case lreal  = 0x00CB
    case string = 0x00DA
}

// MARK: - EtherNet/IP Encapsulation Header

/// 24-byte encapsulation header for EtherNet/IP packets
struct EIPHeader {
    var command: UInt16
    var length: UInt16
    var sessionHandle: UInt32
    var status: UInt32
    var senderContext: UInt64
    var options: UInt32

    static let size = 24

    func toData() -> Data {
        var data = Data(capacity: EIPHeader.size)
        withUnsafeBytes(of: command.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: length.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: sessionHandle.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: status.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: senderContext.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: options.littleEndian) { data.append(contentsOf: $0) }
        return data
    }

    static func fromData(_ data: Data) -> EIPHeader? {
        guard data.count >= EIPHeader.size else { return nil }
        return EIPHeader(
            command: data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian },
            length: data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian },
            sessionHandle: data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian },
            status: data.subdata(in: 8..<12).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian },
            senderContext: data.subdata(in: 12..<20).withUnsafeBytes { $0.load(as: UInt64.self).littleEndian },
            options: data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        )
    }
}

// MARK: - EtherNet/IP Service

/// Handles EtherNet/IP communication with Allen-Bradley PLCs
/// Implements CIP explicit messaging over TCP/44818
class EthernetIPService {
    private var sessionHandle: UInt32 = 0
    private var connectionID: UInt32 = 0
    private var sequenceNumber: UInt16 = 0
    private var isConnected: Bool = false

    let config: EthernetIPConfig

    init(config: EthernetIPConfig) {
        self.config = config
    }

    // MARK: - Session Management

    /// Build a RegisterSession packet to establish an EtherNet/IP session
    func buildRegisterSessionPacket() -> Data {
        // Protocol version 1, option flags 0
        var payload = Data()
        withUnsafeBytes(of: UInt16(1).littleEndian) { payload.append(contentsOf: $0) } // protocol version
        withUnsafeBytes(of: UInt16(0).littleEndian) { payload.append(contentsOf: $0) } // option flags

        let header = EIPHeader(
            command: EIPCommand.registerSession.rawValue,
            length: UInt16(payload.count),
            sessionHandle: 0,
            status: 0,
            senderContext: 0,
            options: 0
        )

        return header.toData() + payload
    }

    /// Build an UnregisterSession packet to close the session
    func buildUnregisterSessionPacket() -> Data {
        let header = EIPHeader(
            command: EIPCommand.unregisterSession.rawValue,
            length: 0,
            sessionHandle: sessionHandle,
            status: 0,
            senderContext: 0,
            options: 0
        )
        return header.toData()
    }

    // MARK: - Device Discovery

    /// Build a ListIdentity broadcast packet for device discovery
    func buildListIdentityPacket() -> Data {
        let header = EIPHeader(
            command: EIPCommand.listIdentity.rawValue,
            length: 0,
            sessionHandle: 0,
            status: 0,
            senderContext: 0,
            options: 0
        )
        return header.toData()
    }

    // MARK: - CIP Routing Path

    /// Build a CIP routing path for the configured slot
    /// Format: port segment (backplane port 1) + link address (slot number)
    func buildRoutingPath() -> Data {
        var path = Data()

        if config.routingPath.isEmpty {
            // Default: backplane port 1, slot from config
            path.append(0x01) // Port segment: backplane
            path.append(UInt8(config.slot)) // Link address: slot number
        } else {
            for segment in config.routingPath {
                switch segment.portType {
                case .backplane:
                    path.append(0x01)
                    path.append(UInt8(segment.address) ?? 0)
                case .ethernetPort:
                    // Extended port segment for IP routing
                    let addrBytes = segment.address.utf8
                    path.append(0x12) // Port 2 (Ethernet) with extended link
                    path.append(UInt8(addrBytes.count))
                    path.append(contentsOf: addrBytes)
                    if addrBytes.count % 2 != 0 { path.append(0x00) } // pad
                case .serialPort:
                    path.append(0x03)
                    path.append(UInt8(segment.address) ?? 0)
                }
            }
        }

        return path
    }

    // MARK: - Tag Read/Write

    /// Build a CIP Read Tag request
    /// - Parameters:
    ///   - tagName: The symbolic tag name (e.g., "MyTag", "Program:MainProgram.LocalTag")
    ///   - elementCount: Number of elements to read (for arrays)
    func buildReadTagRequest(tagName: String, elementCount: UInt16 = 1) -> Data {
        var cipPayload = Data()

        // Service code: Read Tag
        cipPayload.append(CIPService.readTag.rawValue)

        // Path to tag (symbolic segment)
        let tagPath = buildSymbolicSegment(tagName: tagName)
        cipPayload.append(UInt8(tagPath.count / 2)) // path size in words
        cipPayload.append(tagPath)

        // Number of elements to read
        withUnsafeBytes(of: elementCount.littleEndian) { cipPayload.append(contentsOf: $0) }

        return wrapInSendRRData(cipPayload: cipPayload)
    }

    /// Build a CIP Write Tag request
    func buildWriteTagRequest(tagName: String, dataType: CIPDataType, value: Data) -> Data {
        var cipPayload = Data()

        // Service code: Write Tag
        cipPayload.append(CIPService.writeTag.rawValue)

        // Path to tag
        let tagPath = buildSymbolicSegment(tagName: tagName)
        cipPayload.append(UInt8(tagPath.count / 2))
        cipPayload.append(tagPath)

        // Data type
        withUnsafeBytes(of: dataType.rawValue.littleEndian) { cipPayload.append(contentsOf: $0) }

        // Element count
        withUnsafeBytes(of: UInt16(1).littleEndian) { cipPayload.append(contentsOf: $0) }

        // Value data
        cipPayload.append(value)

        return wrapInSendRRData(cipPayload: cipPayload)
    }

    /// Build a CIP ForwardOpen request for connected messaging
    func buildForwardOpenRequest() -> Data {
        var cipPayload = Data()

        // Service code
        cipPayload.append(CIPService.forwardOpen.rawValue)

        // Path size + path to Connection Manager (class 0x06, instance 1)
        cipPayload.append(0x02) // path size: 2 words
        cipPayload.append(0x20) // class segment
        cipPayload.append(0x06) // Connection Manager class
        cipPayload.append(0x24) // instance segment
        cipPayload.append(0x01) // instance 1

        // Timeout ticks
        cipPayload.append(0x0A) // priority/tick time
        cipPayload.append(0x0E) // timeout ticks

        // O→T connection ID
        withUnsafeBytes(of: UInt32(0).littleEndian) { cipPayload.append(contentsOf: $0) }

        // T→O connection ID
        withUnsafeBytes(of: UInt32(0).littleEndian) { cipPayload.append(contentsOf: $0) }

        // Connection serial number
        withUnsafeBytes(of: UInt16(arc4random_uniform(65535)).littleEndian) { cipPayload.append(contentsOf: $0) }

        // Vendor ID
        withUnsafeBytes(of: UInt16(0xFFFF).littleEndian) { cipPayload.append(contentsOf: $0) }

        // Originator serial number
        withUnsafeBytes(of: UInt32(12345).littleEndian) { cipPayload.append(contentsOf: $0) }

        // Connection timeout multiplier
        cipPayload.append(0x03)
        cipPayload.append(contentsOf: [0x00, 0x00, 0x00]) // reserved

        // O→T RPI (microseconds)
        withUnsafeBytes(of: config.rpi.littleEndian) { cipPayload.append(contentsOf: $0) }

        // O→T connection parameters
        withUnsafeBytes(of: UInt16(config.connectionSize).littleEndian) { cipPayload.append(contentsOf: $0) }

        // T→O RPI
        withUnsafeBytes(of: config.rpi.littleEndian) { cipPayload.append(contentsOf: $0) }

        // T→O connection parameters
        withUnsafeBytes(of: UInt16(config.connectionSize).littleEndian) { cipPayload.append(contentsOf: $0) }

        // Transport type/trigger
        cipPayload.append(0xA3) // direction: server, trigger: application object

        // Connection path
        let routePath = buildRoutingPath()
        cipPayload.append(UInt8(routePath.count / 2))
        cipPayload.append(routePath)

        return wrapInSendRRData(cipPayload: cipPayload)
    }

    // MARK: - Helpers

    /// Build a symbolic segment from a tag name
    private func buildSymbolicSegment(tagName: String) -> Data {
        var segment = Data()
        let nameBytes = Array(tagName.utf8)

        segment.append(0x91) // symbolic segment identifier
        segment.append(UInt8(nameBytes.count))
        segment.append(contentsOf: nameBytes)

        // Pad to even length
        if nameBytes.count % 2 != 0 {
            segment.append(0x00)
        }

        return segment
    }

    /// Wrap a CIP payload in SendRRData encapsulation
    private func wrapInSendRRData(cipPayload: Data) -> Data {
        var sendRRPayload = Data()

        // Interface handle (CIP)
        withUnsafeBytes(of: UInt32(0).littleEndian) { sendRRPayload.append(contentsOf: $0) }

        // Timeout
        withUnsafeBytes(of: UInt16(10).littleEndian) { sendRRPayload.append(contentsOf: $0) }

        // Item count: 2 (null address + unconnected data)
        withUnsafeBytes(of: UInt16(2).littleEndian) { sendRRPayload.append(contentsOf: $0) }

        // Address item (null)
        withUnsafeBytes(of: UInt16(0x0000).littleEndian) { sendRRPayload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0).littleEndian) { sendRRPayload.append(contentsOf: $0) }

        // Data item (unconnected message)
        withUnsafeBytes(of: UInt16(0x00B2).littleEndian) { sendRRPayload.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(cipPayload.count).littleEndian) { sendRRPayload.append(contentsOf: $0) }
        sendRRPayload.append(cipPayload)

        let header = EIPHeader(
            command: EIPCommand.sendRRData.rawValue,
            length: UInt16(sendRRPayload.count),
            sessionHandle: sessionHandle,
            status: 0,
            senderContext: 0,
            options: 0
        )

        return header.toData() + sendRRPayload
    }

    // MARK: - Response Parsing

    /// Parse a RegisterSession response and extract the session handle
    func parseRegisterSessionResponse(_ data: Data) -> UInt32? {
        guard let header = EIPHeader.fromData(data) else { return nil }
        guard header.status == 0 else { return nil }
        sessionHandle = header.sessionHandle
        return sessionHandle
    }

    /// Parse a ListIdentity response to extract discovered device information
    func parseListIdentityResponse(_ data: Data) -> DiscoveredDevice? {
        guard let header = EIPHeader.fromData(data) else { return nil }
        guard header.command == EIPCommand.listIdentity.rawValue else { return nil }
        guard data.count > EIPHeader.size + 2 else { return nil }

        // Item count at offset 24
        let offset = EIPHeader.size
        let itemCount = data.subdata(in: offset..<offset+2)
            .withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        guard itemCount >= 1 else { return nil }

        // Parse identity item (simplified — full parsing handles all fields)
        var device = DiscoveredDevice(ipAddress: config.ipAddress)
        device.vendorName = "Allen-Bradley"
        device.protocol_ = .ethernetIP
        return device
    }

    /// Parse a Read Tag response and return the raw value data
    func parseReadTagResponse(_ data: Data) -> (dataType: CIPDataType, value: Data)? {
        guard let header = EIPHeader.fromData(data) else { return nil }
        guard header.status == 0 else { return nil }

        // Navigate past encapsulation to CIP response
        // Offset: header(24) + interface(4) + timeout(2) + itemCount(2) + addrItem(4) + dataItemHeader(4)
        let cipOffset = EIPHeader.size + 16
        guard data.count > cipOffset + 4 else { return nil }

        let serviceReply = data[cipOffset]
        guard serviceReply == (CIPService.readTag.rawValue | 0x80) else { return nil } // reply flag

        let generalStatus = data[cipOffset + 2]
        guard generalStatus == 0 else { return nil }

        // Data type at cipOffset + 4
        let dataTypeRaw = data.subdata(in: (cipOffset+4)..<(cipOffset+6))
            .withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let valueData = data.subdata(in: (cipOffset+6)..<data.count)

        guard let dataType = CIPDataType(rawValue: dataTypeRaw) else { return nil }
        return (dataType, valueData)
    }
}
