// ModbusTCPService.swift
// PLCCommManager - PLC Communications Manager
// Modbus TCP protocol implementation for generic industrial device communication

import Foundation

// MARK: - Modbus Function Codes

enum ModbusFunctionCode: UInt8 {
    case readCoils              = 0x01
    case readDiscreteInputs     = 0x02
    case readHoldingRegisters   = 0x03
    case readInputRegisters     = 0x04
    case writeSingleCoil        = 0x05
    case writeSingleRegister    = 0x06
    case writeMultipleCoils     = 0x0F
    case writeMultipleRegisters = 0x10
    case readWriteRegisters     = 0x17

    var description: String {
        switch self {
        case .readCoils: return "Read Coils (FC01)"
        case .readDiscreteInputs: return "Read Discrete Inputs (FC02)"
        case .readHoldingRegisters: return "Read Holding Registers (FC03)"
        case .readInputRegisters: return "Read Input Registers (FC04)"
        case .writeSingleCoil: return "Write Single Coil (FC05)"
        case .writeSingleRegister: return "Write Single Register (FC06)"
        case .writeMultipleCoils: return "Write Multiple Coils (FC15)"
        case .writeMultipleRegisters: return "Write Multiple Registers (FC16)"
        case .readWriteRegisters: return "Read/Write Registers (FC23)"
        }
    }
}

// MARK: - Modbus TCP MBAP Header

/// Modbus Application Protocol header (7 bytes)
struct MBAPHeader {
    var transactionID: UInt16
    var protocolID: UInt16 = 0 // always 0 for Modbus
    var length: UInt16
    var unitID: UInt8

    static let size = 7

    func toData() -> Data {
        var data = Data(capacity: MBAPHeader.size)
        withUnsafeBytes(of: transactionID.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: protocolID.bigEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: length.bigEndian) { data.append(contentsOf: $0) }
        data.append(unitID)
        return data
    }

    static func fromData(_ data: Data) -> MBAPHeader? {
        guard data.count >= MBAPHeader.size else { return nil }
        return MBAPHeader(
            transactionID: data.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian },
            protocolID: data.subdata(in: 2..<4).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian },
            length: data.subdata(in: 4..<6).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian },
            unitID: data[6]
        )
    }
}

// MARK: - Modbus TCP Service

/// Handles Modbus TCP communication for generic industrial devices
class ModbusTCPService {
    let config: ModbusTCPConfig
    private var transactionCounter: UInt16 = 0

    init(config: ModbusTCPConfig) {
        self.config = config
    }

    private func nextTransactionID() -> UInt16 {
        transactionCounter &+= 1
        return transactionCounter
    }

    // MARK: - Read Operations

    /// Build Read Holding Registers request (FC03)
    func buildReadHoldingRegisters(startAddress: UInt16, quantity: UInt16) -> Data {
        var pdu = Data()
        pdu.append(ModbusFunctionCode.readHoldingRegisters.rawValue)
        withUnsafeBytes(of: startAddress.bigEndian) { pdu.append(contentsOf: $0) }
        withUnsafeBytes(of: quantity.bigEndian) { pdu.append(contentsOf: $0) }

        let header = MBAPHeader(
            transactionID: nextTransactionID(),
            length: UInt16(pdu.count + 1), // +1 for unitID
            unitID: config.unitID
        )

        return header.toData() + pdu
    }

    /// Build Read Coils request (FC01)
    func buildReadCoils(startAddress: UInt16, quantity: UInt16) -> Data {
        var pdu = Data()
        pdu.append(ModbusFunctionCode.readCoils.rawValue)
        withUnsafeBytes(of: startAddress.bigEndian) { pdu.append(contentsOf: $0) }
        withUnsafeBytes(of: quantity.bigEndian) { pdu.append(contentsOf: $0) }

        let header = MBAPHeader(
            transactionID: nextTransactionID(),
            length: UInt16(pdu.count + 1),
            unitID: config.unitID
        )

        return header.toData() + pdu
    }

    /// Build Read Input Registers request (FC04)
    func buildReadInputRegisters(startAddress: UInt16, quantity: UInt16) -> Data {
        var pdu = Data()
        pdu.append(ModbusFunctionCode.readInputRegisters.rawValue)
        withUnsafeBytes(of: startAddress.bigEndian) { pdu.append(contentsOf: $0) }
        withUnsafeBytes(of: quantity.bigEndian) { pdu.append(contentsOf: $0) }

        let header = MBAPHeader(
            transactionID: nextTransactionID(),
            length: UInt16(pdu.count + 1),
            unitID: config.unitID
        )

        return header.toData() + pdu
    }

    // MARK: - Write Operations

    /// Build Write Single Register request (FC06)
    func buildWriteSingleRegister(address: UInt16, value: UInt16) -> Data {
        var pdu = Data()
        pdu.append(ModbusFunctionCode.writeSingleRegister.rawValue)
        withUnsafeBytes(of: address.bigEndian) { pdu.append(contentsOf: $0) }
        withUnsafeBytes(of: value.bigEndian) { pdu.append(contentsOf: $0) }

        let header = MBAPHeader(
            transactionID: nextTransactionID(),
            length: UInt16(pdu.count + 1),
            unitID: config.unitID
        )

        return header.toData() + pdu
    }

    /// Build Write Multiple Registers request (FC16)
    func buildWriteMultipleRegisters(startAddress: UInt16, values: [UInt16]) -> Data {
        var pdu = Data()
        pdu.append(ModbusFunctionCode.writeMultipleRegisters.rawValue)
        withUnsafeBytes(of: startAddress.bigEndian) { pdu.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(values.count).bigEndian) { pdu.append(contentsOf: $0) }
        pdu.append(UInt8(values.count * 2)) // byte count
        for value in values {
            withUnsafeBytes(of: value.bigEndian) { pdu.append(contentsOf: $0) }
        }

        let header = MBAPHeader(
            transactionID: nextTransactionID(),
            length: UInt16(pdu.count + 1),
            unitID: config.unitID
        )

        return header.toData() + pdu
    }

    /// Build Write Single Coil request (FC05)
    func buildWriteSingleCoil(address: UInt16, value: Bool) -> Data {
        var pdu = Data()
        pdu.append(ModbusFunctionCode.writeSingleCoil.rawValue)
        withUnsafeBytes(of: address.bigEndian) { pdu.append(contentsOf: $0) }
        withUnsafeBytes(of: (value ? UInt16(0xFF00) : UInt16(0x0000)).bigEndian) { pdu.append(contentsOf: $0) }

        let header = MBAPHeader(
            transactionID: nextTransactionID(),
            length: UInt16(pdu.count + 1),
            unitID: config.unitID
        )

        return header.toData() + pdu
    }

    // MARK: - Response Parsing

    /// Parse a Read Holding Registers response (FC03)
    func parseReadRegistersResponse(_ data: Data) -> [UInt16]? {
        guard let header = MBAPHeader.fromData(data) else { return nil }
        let pduOffset = MBAPHeader.size
        guard data.count > pduOffset + 2 else { return nil }

        let functionCode = data[pduOffset]

        // Check for exception response (high bit set)
        if functionCode & 0x80 != 0 {
            return nil
        }

        let byteCount = Int(data[pduOffset + 1])
        guard data.count >= pduOffset + 2 + byteCount else { return nil }

        var registers: [UInt16] = []
        for i in stride(from: pduOffset + 2, to: pduOffset + 2 + byteCount, by: 2) {
            let value = data.subdata(in: i..<i+2)
                .withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            registers.append(value)
        }

        return registers
    }

    /// Parse a Read Coils response (FC01)
    func parseReadCoilsResponse(_ data: Data) -> [Bool]? {
        guard let _ = MBAPHeader.fromData(data) else { return nil }
        let pduOffset = MBAPHeader.size
        guard data.count > pduOffset + 2 else { return nil }

        let functionCode = data[pduOffset]
        if functionCode & 0x80 != 0 { return nil }

        let byteCount = Int(data[pduOffset + 1])
        guard data.count >= pduOffset + 2 + byteCount else { return nil }

        var coils: [Bool] = []
        for i in 0..<byteCount {
            let byte = data[pduOffset + 2 + i]
            for bit in 0..<8 {
                coils.append((byte >> bit) & 0x01 == 1)
            }
        }

        return coils
    }

    /// Convert register pair to 32-bit float using configured byte/word order
    func registersToFloat(_ registers: [UInt16]) -> Float? {
        guard registers.count >= 2 else { return nil }

        var bytes: [UInt8]
        let reg0 = registers[0]
        let reg1 = registers[1]

        switch (config.byteOrder, config.wordOrder) {
        case (.bigEndian, .highFirst):
            bytes = [UInt8(reg0 >> 8), UInt8(reg0 & 0xFF), UInt8(reg1 >> 8), UInt8(reg1 & 0xFF)]
        case (.bigEndian, .lowFirst):
            bytes = [UInt8(reg1 >> 8), UInt8(reg1 & 0xFF), UInt8(reg0 >> 8), UInt8(reg0 & 0xFF)]
        case (.littleEndian, .highFirst):
            bytes = [UInt8(reg0 & 0xFF), UInt8(reg0 >> 8), UInt8(reg1 & 0xFF), UInt8(reg1 >> 8)]
        case (.littleEndian, .lowFirst):
            bytes = [UInt8(reg1 & 0xFF), UInt8(reg1 >> 8), UInt8(reg0 & 0xFF), UInt8(reg0 >> 8)]
        }

        return Data(bytes).withUnsafeBytes { $0.load(as: Float.self) }
    }
}
