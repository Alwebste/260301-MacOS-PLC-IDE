// AddDriverSheet.swift
// PLCCommManager - PLC Communications Manager
// Sheet for creating a new communication driver with protocol-specific configuration

import SwiftUI

struct AddDriverSheet: View {
    @EnvironmentObject var commStore: CommManagerStore
    @Environment(\.dismiss) var dismiss

    @State private var driverName: String = ""
    @State private var selectedProtocol: CommProtocol = .ethernetIP
    @State private var autoStart: Bool = false

    // EtherNet/IP fields
    @State private var eipAddress: String = "192.168.1.1"
    @State private var eipPort: String = "44818"
    @State private var eipSlot: String = "0"
    @State private var eipTimeout: String = "5"
    @State private var eipFamily: PLCFamily = .controlLogix
    @State private var eipKeepAlive: Bool = true
    @State private var eipRPI: String = "100"

    // Modbus TCP fields
    @State private var mbAddress: String = "192.168.1.1"
    @State private var mbPort: String = "502"
    @State private var mbUnitID: String = "1"
    @State private var mbTimeout: String = "3"
    @State private var mbByteOrder: ModbusByteOrder = .bigEndian
    @State private var mbWordOrder: ModbusWordOrder = .highFirst
    @State private var mbPollRate: String = "1.0"

    // OPC UA fields
    @State private var opcEndpoint: String = "opc.tcp://192.168.1.1:4840"
    @State private var opcSecurity: OPCSecurityMode = .none
    @State private var opcAuth: OPCAuthMode = .anonymous
    @State private var opcUsername: String = ""
    @State private var opcPassword: String = ""

    // Serial DF1 fields
    @State private var serialPort: String = "/dev/tty.usbserial"
    @State private var serialBaud: BaudRate = .b19200
    @State private var serialDataBits: DataBits = .eight
    @State private var serialParity: SerialParity = .none
    @State private var serialStopBits: StopBits = .one
    @State private var serialStation: String = "0"

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Communication Driver")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // General settings
                    generalSection

                    Divider()

                    // Protocol-specific settings
                    protocolConfigSection
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Driver") { addDriver() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(driverName.isEmpty)
            }
            .padding()
        }
        .frame(width: 600, height: 650)
        .onAppear {
            driverName = suggestedName(for: selectedProtocol)
        }
        .onChange(of: selectedProtocol) { newProtocol in
            if driverName.isEmpty || CommProtocol.allCases.map({ suggestedName(for: $0) }).contains(driverName) {
                driverName = suggestedName(for: newProtocol)
            }
        }
    }

    // MARK: - General Settings

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("General")
                .font(.headline)

            LabeledContent("Driver Name") {
                TextField("Enter driver name", text: $driverName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
            }

            LabeledContent("Protocol") {
                Picker("", selection: $selectedProtocol) {
                    ForEach(CommProtocol.allCases) { proto in
                        Label(proto.rawValue, systemImage: proto.icon)
                            .tag(proto)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
            }

            LabeledContent("Auto-Start") {
                Toggle("Start driver when application launches", isOn: $autoStart)
                    .toggleStyle(.checkbox)
            }

            Text(selectedProtocol.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
        }
    }

    // MARK: - Protocol Config

    @ViewBuilder
    private var protocolConfigSection: some View {
        switch selectedProtocol {
        case .ethernetIP, .cip:
            ethernetIPSection
        case .modbusTCP:
            modbusTCPSection
        case .opcUA:
            opcUASection
        case .serialDF1:
            serialDF1Section
        }
    }

    // MARK: - EtherNet/IP Configuration

    private var ethernetIPSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("EtherNet/IP Configuration")
                .font(.headline)

            LabeledContent("PLC Family") {
                Picker("", selection: $eipFamily) {
                    ForEach(PLCFamily.allCases.filter { $0.supportedProtocols.contains(.ethernetIP) }) { family in
                        Text(family.rawValue).tag(family)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 300)
            }

            LabeledContent("IP Address") {
                TextField("192.168.1.1", text: $eipAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            LabeledContent("Port") {
                TextField("44818", text: $eipPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
            }

            LabeledContent("Slot Number") {
                TextField("0", text: $eipSlot)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
                Text("(CPU slot in chassis)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LabeledContent("Connection Timeout (s)") {
                TextField("5", text: $eipTimeout)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }

            LabeledContent("RPI (ms)") {
                TextField("100", text: $eipRPI)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
                Text("Requested Packet Interval")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LabeledContent("Keep Alive") {
                Toggle("Enable connection keep-alive", isOn: $eipKeepAlive)
                    .toggleStyle(.checkbox)
            }
        }
    }

    // MARK: - Modbus TCP Configuration

    private var modbusTCPSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Modbus TCP Configuration")
                .font(.headline)

            LabeledContent("IP Address") {
                TextField("192.168.1.1", text: $mbAddress)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)
            }

            LabeledContent("Port") {
                TextField("502", text: $mbPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 100)
            }

            LabeledContent("Unit ID") {
                TextField("1", text: $mbUnitID)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
                Text("Modbus slave address (1-247)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            LabeledContent("Response Timeout (s)") {
                TextField("3", text: $mbTimeout)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }

            LabeledContent("Default Poll Rate (s)") {
                TextField("1.0", text: $mbPollRate)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }

            LabeledContent("Byte Order") {
                Picker("", selection: $mbByteOrder) {
                    ForEach(ModbusByteOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            LabeledContent("Word Order") {
                Picker("", selection: $mbWordOrder) {
                    ForEach(ModbusWordOrder.allCases) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }
        }
    }

    // MARK: - OPC UA Configuration

    private var opcUASection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OPC UA Configuration")
                .font(.headline)

            LabeledContent("Endpoint URL") {
                TextField("opc.tcp://192.168.1.1:4840", text: $opcEndpoint)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 350)
            }

            LabeledContent("Security Mode") {
                Picker("", selection: $opcSecurity) {
                    ForEach(OPCSecurityMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            LabeledContent("Authentication") {
                Picker("", selection: $opcAuth) {
                    ForEach(OPCAuthMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            if opcAuth == .usernamePassword {
                LabeledContent("Username") {
                    TextField("Username", text: $opcUsername)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }

                LabeledContent("Password") {
                    SecureField("Password", text: $opcPassword)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                }
            }
        }
    }

    // MARK: - Serial DF1 Configuration

    private var serialDF1Section: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Serial DF1 Configuration")
                .font(.headline)

            LabeledContent("Serial Port") {
                TextField("/dev/tty.usbserial", text: $serialPort)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 250)
            }

            LabeledContent("Baud Rate") {
                Picker("", selection: $serialBaud) {
                    ForEach(BaudRate.allCases) { rate in
                        Text(rate.display).tag(rate)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 150)
            }

            LabeledContent("Data Bits") {
                Picker("", selection: $serialDataBits) {
                    ForEach(DataBits.allCases) { bits in
                        Text(bits.display).tag(bits)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150)
            }

            LabeledContent("Parity") {
                Picker("", selection: $serialParity) {
                    ForEach(SerialParity.allCases) { parity in
                        Text(parity.rawValue).tag(parity)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }

            LabeledContent("Stop Bits") {
                Picker("", selection: $serialStopBits) {
                    ForEach(StopBits.allCases) { bits in
                        Text(bits.display).tag(bits)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 150)
            }

            LabeledContent("Station Address") {
                TextField("0", text: $serialStation)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 80)
            }
        }
    }

    // MARK: - Actions

    private func addDriver() {
        var driver = CommDriver(name: driverName, protocol_: selectedProtocol)
        driver.autoStart = autoStart

        switch selectedProtocol {
        case .ethernetIP, .cip:
            var config = EthernetIPConfig()
            config.ipAddress = eipAddress
            config.port = UInt16(eipPort) ?? 44818
            config.slot = Int(eipSlot) ?? 0
            config.connectionTimeout = TimeInterval(eipTimeout) ?? 5.0
            config.plcFamily = eipFamily
            config.enableKeepAlive = eipKeepAlive
            config.rpi = UInt32(eipRPI) ?? 100_000
            driver.ethernetIPConfig = config

        case .modbusTCP:
            var config = ModbusTCPConfig()
            config.ipAddress = mbAddress
            config.port = UInt16(mbPort) ?? 502
            config.unitID = UInt8(mbUnitID) ?? 1
            config.responseTimeout = TimeInterval(mbTimeout) ?? 3.0
            config.defaultPollRate = TimeInterval(mbPollRate) ?? 1.0
            config.byteOrder = mbByteOrder
            config.wordOrder = mbWordOrder
            driver.modbusTCPConfig = config

        case .opcUA:
            var config = OPCUAConfig()
            config.endpointURL = opcEndpoint
            config.securityMode = opcSecurity
            config.authMode = opcAuth
            config.username = opcUsername
            config.password = opcPassword
            driver.opcUAConfig = config

        case .serialDF1:
            var config = SerialDF1Config()
            config.portName = serialPort
            config.baudRate = serialBaud
            config.dataBits = serialDataBits
            config.parity = serialParity
            config.stopBits = serialStopBits
            config.stationAddress = UInt8(serialStation) ?? 0
            driver.serialDF1Config = config
        }

        commStore.addDriver(driver)
        dismiss()
    }

    private func suggestedName(for proto: CommProtocol) -> String {
        let count = commStore.drivers.filter { $0.protocol_ == proto }.count
        let suffix = count > 0 ? " \(count + 1)" : ""
        switch proto {
        case .ethernetIP: return "AB Ethernet\(suffix)"
        case .modbusTCP: return "Modbus TCP\(suffix)"
        case .opcUA: return "OPC UA\(suffix)"
        case .serialDF1: return "Serial DF1\(suffix)"
        case .cip: return "CIP Driver\(suffix)"
        }
    }
}

// MARK: - Edit Driver Sheet

struct EditDriverSheet: View {
    @EnvironmentObject var commStore: CommManagerStore
    @Environment(\.dismiss) var dismiss
    let driver: CommDriver

    // For a full implementation, this would mirror AddDriverSheet with pre-populated fields
    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Driver: \(driver.name)")
                .font(.title3.weight(.semibold))

            Text("Driver editing will use the same configuration form as Add Driver, pre-populated with current settings.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 200)
    }
}
