import Foundation

// ─── PlcCoreBridge ──────────────────────────────────────────────────────────
//
// This file provides Swift mirror types for the Rust plc-core data model.
// When building on macOS with the real UniFFI bindings, replace the #if DEMO
// blocks with actual UniFFI calls. The types match the UniFFI-generated types
// exactly (same field names, same enum case names).
//
// Phase 1: Uses these types directly. Phase 3: UniFFI generates them from Rust.
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - Enums

enum ControllerFamily {
    case controlLogix
    case compactLogix

    var displayName: String {
        switch self {
        case .controlLogix: return "ControlLogix"
        case .compactLogix: return "CompactLogix"
        }
    }
}

enum TaskType: Codable {
    case continuous
    case periodic(periodMs: UInt32)
    case event(trigger: String)

    var displayName: String {
        switch self {
        case .continuous: return "Continuous"
        case .periodic(let ms): return "Periodic (\(ms)ms)"
        case .event(let trigger): return "Event (\(trigger))"
        }
    }
}

enum InstructionType: Codable, Equatable {
    // Bit
    case xic, xio, ote, otl, otu, ons
    // Timer
    case ton, tof, rto
    // Counter
    case ctu, ctd, res
    // Compare
    case equ, neq, les, leq, grt, geq
    // Math
    case add, sub, mul, div, mod_, neg
    // Move
    case mov, cop
    // Program control
    case jmp, lbl, jsr, ret, sbr
    // Unknown
    case unknown(mnemonic: String)

    var mnemonic: String {
        switch self {
        case .xic: return "XIC"
        case .xio: return "XIO"
        case .ote: return "OTE"
        case .otl: return "OTL"
        case .otu: return "OTU"
        case .ons: return "ONS"
        case .ton: return "TON"
        case .tof: return "TOF"
        case .rto: return "RTO"
        case .ctu: return "CTU"
        case .ctd: return "CTD"
        case .res: return "RES"
        case .equ: return "EQU"
        case .neq: return "NEQ"
        case .les: return "LES"
        case .leq: return "LEQ"
        case .grt: return "GRT"
        case .geq: return "GEQ"
        case .add: return "ADD"
        case .sub: return "SUB"
        case .mul: return "MUL"
        case .div: return "DIV"
        case .mod_: return "MOD"
        case .neg: return "NEG"
        case .mov: return "MOV"
        case .cop: return "COP"
        case .jmp: return "JMP"
        case .lbl: return "LBL"
        case .jsr: return "JSR"
        case .ret: return "RET"
        case .sbr: return "SBR"
        case .unknown(let m): return m
        }
    }

    /// Whether this is an input instruction (contact/condition)
    var isInput: Bool {
        switch self {
        case .xic, .xio, .ons, .equ, .neq, .les, .leq, .grt, .geq:
            return true
        default:
            return false
        }
    }

    /// Whether this is an output instruction (coil/action)
    var isOutput: Bool {
        switch self {
        case .ote, .otl, .otu:
            return true
        default:
            return false
        }
    }
}

enum Operand: Codable {
    case tagRef(name: String)
    case intLiteral(value: Int64)
    case realLiteral(value: Double)

    var displayString: String {
        switch self {
        case .tagRef(let name): return name
        case .intLiteral(let value): return "\(value)"
        case .realLiteral(let value): return String(format: "%.1f", value)
        }
    }
}

enum DataType: Codable {
    case bool_
    case sint
    case int_
    case dint
    case lint
    case real
    case stringType
    case timer
    case counter
    case array(elementTypeName: String, dimensions: [UInt32])
    case udt(name: String)

    var displayName: String {
        switch self {
        case .bool_: return "BOOL"
        case .sint: return "SINT"
        case .int_: return "INT"
        case .dint: return "DINT"
        case .lint: return "LINT"
        case .real: return "REAL"
        case .stringType: return "STRING"
        case .timer: return "TIMER"
        case .counter: return "COUNTER"
        case .array(let el, let dims):
            let dimStr = dims.map { "\($0)" }.joined(separator: ",")
            return "\(el)[\(dimStr)]"
        case .udt(let name): return name
        }
    }
}

enum TagScope: Codable, Equatable {
    case controller
    case program(programName: String)

    var displayName: String {
        switch self {
        case .controller: return "Controller"
        case .program(let name): return name
        }
    }
}

enum ExternalAccess: String, Codable {
    case readWrite = "Read/Write"
    case readOnly = "Read Only"
    case none = "None"
}

enum Severity: Codable {
    case error
    case warning
    case info
}

// MARK: - Structs

struct Instruction: Codable, Identifiable {
    let id: String
    let instructionType: InstructionType
    let operands: [Operand]
    let comment: String
}

indirect enum RungElement: Codable {
    case instruction(instruction: Instruction)
    case series(elements: [RungElement])
    case parallel(branches: [RungElement])

    /// Format as neutral text (same as Rust format_rung_element)
    var neutralText: String {
        switch self {
        case .instruction(let inst):
            let ops = inst.operands.map { $0.displayString }.joined(separator: ",")
            return "\(inst.instructionType.mnemonic)(\(ops))"
        case .series(let elements):
            return elements.map { $0.neutralText }.joined(separator: " ")
        case .parallel(let branches):
            let paths = branches.map { $0.neutralText }.joined(separator: ",")
            return "[\(paths)]"
        }
    }
}

struct Rung: Codable, Identifiable {
    let id: String
    let number: UInt32
    let element: RungElement
    let comment: String
    let editable: Bool
}

struct Routine: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let rungs: [Rung]
}

struct Program: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let mainRoutineName: String
    let faultRoutineName: String
    let routines: [Routine]
}

struct Task: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let taskType: TaskType
    let priority: UInt32
    let programs: [Program]
}

struct Controller: Codable {
    let name: String
    let family: ControllerFamily
    let catalogNumber: String
    let firmwareVersion: String
    let description: String
}

struct Tag: Codable, Identifiable {
    let id: String
    let name: String
    let dataType: DataType
    let scope: TagScope
    let description: String
    let initialValue: String
    let aliasFor: String?
    let externalAccess: ExternalAccess
}

struct TagDatabase: Codable {
    let tags: [Tag]
}

struct PlcProject: Codable {
    let formatVersion: UInt32
    let id: String
    let name: String
    let description: String
    let controller: Controller
    let tasks: [Task]
    let tagDatabase: TagDatabase
    let importedFrom: String?
}

struct ValidationIssue: Codable, Identifiable {
    var id: String { "\(programName).\(routineName).\(rungNumber ?? 0).\(message)" }
    let severity: Severity
    let message: String
    let rungNumber: UInt32?
    let routineName: String
    let programName: String
}

struct ProjectSummary {
    let name: String
    let controllerFamily: String
    let catalogNumber: String
    let taskCount: UInt32
    let programCount: UInt32
    let routineCount: UInt32
    let rungCount: UInt32
    let tagCount: UInt32
}

// MARK: - Codable conformances for enums with associated values

extension ControllerFamily: Codable {
    // Serde serializes Rust enums as strings for unit variants
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "ControlLogix": self = .controlLogix
        case "CompactLogix": self = .compactLogix
        default: self = .controlLogix
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(displayName)
    }
}

// MARK: - Helper Extensions

extension PlcProject {
    /// Compute project summary
    var summary: ProjectSummary {
        var programCount: UInt32 = 0
        var routineCount: UInt32 = 0
        var rungCount: UInt32 = 0
        for task in tasks {
            for program in task.programs {
                programCount += 1
                for routine in program.routines {
                    routineCount += 1
                    rungCount += UInt32(routine.rungs.count)
                }
            }
        }
        return ProjectSummary(
            name: name,
            controllerFamily: controller.family.displayName,
            catalogNumber: controller.catalogNumber,
            taskCount: UInt32(tasks.count),
            programCount: programCount,
            routineCount: routineCount,
            rungCount: rungCount,
            tagCount: UInt32(tagDatabase.tags.count)
        )
    }

    /// Get all program names
    var programNames: [String] {
        tasks.flatMap { $0.programs.map { $0.name } }
    }

    /// Find a routine by program and routine name
    func findRoutine(programName: String, routineName: String) -> Routine? {
        for task in tasks {
            for program in task.programs {
                if program.name == programName {
                    return program.routines.first { $0.name == routineName }
                }
            }
        }
        return nil
    }

    /// Get controller-scope tags
    var controllerTags: [Tag] {
        tagDatabase.tags.filter {
            if case .controller = $0.scope { return true }
            return false
        }
    }

    /// Get program-scope tags for a specific program
    func programTags(for programName: String) -> [Tag] {
        tagDatabase.tags.filter {
            if case .program(let pn) = $0.scope { return pn == programName }
            return false
        }
    }
}
