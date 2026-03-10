import Foundation

/// Import preview data for the import dialog.
struct ImportPreview {
    let controllerName: String
    let processorType: String
    let programNames: [String]
    let routineCount: Int
    let tagCount: Int
    let rungCount: Int
    let warnings: [String]
}

/// Parses L5X (XML) files into the internal PlcProject model.
///
/// L5X is Rockwell Automation's XML export format from Studio 5000.
/// Rung expressions in `<Text>` elements use L5K syntax:
///   `[XIC(Start_PB),XIC(Motor_Run)] OTL(Motor_Run) ;`
enum L5XImporter {

    /// Quick preview without full rung parsing.
    static func preview(_ xml: String) -> ImportPreview? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let parser = L5XPreviewParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }

        return ImportPreview(
            controllerName: parser.controllerName,
            processorType: parser.processorType,
            programNames: parser.programNames,
            routineCount: parser.routineCount,
            tagCount: parser.tagCount,
            rungCount: parser.rungCount,
            warnings: parser.warnings
        )
    }

    /// Full parse into a PlcProject.
    static func parse(_ xml: String) -> PlcProject? {
        guard let data = xml.data(using: .utf8) else { return nil }
        let parser = L5XFullParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        guard xmlParser.parse() else { return nil }
        return parser.project
    }
}

// MARK: - Preview Parser (lightweight)

private class L5XPreviewParser: NSObject, XMLParserDelegate {
    var controllerName = ""
    var processorType = ""
    var programNames: [String] = []
    var routineCount = 0
    var tagCount = 0
    var rungCount = 0
    var warnings: [String] = []
    private var inTags = false

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        switch elementName {
        case "Controller":
            controllerName = attributes["Name"] ?? ""
            processorType = attributes["ProcessorType"] ?? ""
        case "Program":
            if let name = attributes["Name"] { programNames.append(name) }
        case "Routine":
            if attributes["Type"] == "RLL" { routineCount += 1 }
        case "Tag":
            tagCount += 1
        case "Rung":
            rungCount += 1
        default: break
        }
    }
}

// MARK: - Full Parser

private class L5XFullParser: NSObject, XMLParserDelegate {
    var project: PlcProject?

    private var controllerName = ""
    private var processorType = ""

    // Build state
    private var tasks: [Task] = []
    private var tags: [Tag] = []
    private var currentProgramName = ""
    private var currentRoutineName = ""
    private var currentRungNumber: UInt32 = 0
    private var currentRungComment = ""
    private var programs: [(String, [RoutineBuild])] = []  // (programName, routines)
    private var currentRoutines: [RoutineBuild] = []
    private var currentRungs: [Rung] = []

    // Text accumulation
    private var currentText = ""
    private var capturingText = false
    private var capturingComment = false

    // Tag scope tracking
    private var inControllerTags = false
    private var inProgramTags = false
    private var inRoutine = false
    private var skipDepth = 0

    private struct RoutineBuild {
        let name: String
        let rungs: [Rung]
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        if skipDepth > 0 { skipDepth += 1; return }

        switch elementName {
        case "Controller":
            controllerName = attributes["Name"] ?? ""
            processorType = attributes["ProcessorType"] ?? ""

        case "Tags":
            if currentProgramName.isEmpty {
                inControllerTags = true
            } else {
                inProgramTags = true
            }

        case "Tag" where inControllerTags || inProgramTags:
            let name = attributes["Name"] ?? ""
            let dtStr = attributes["DataType"] ?? "BOOL"
            let scope: TagScope = inProgramTags
                ? .program(programName: currentProgramName)
                : .controller
            let ea: ExternalAccess
            switch attributes["ExternalAccess"] ?? "" {
            case "Read Only": ea = .readOnly
            case "None": ea = .none
            default: ea = .readWrite
            }
            let dims = attributes["Dimensions"]
            let dataType = Self.parseDataType(dtStr, dimensions: dims)

            tags.append(Tag(
                id: UUID().uuidString,
                name: name,
                dataType: dataType,
                scope: scope,
                description: "",
                initialValue: "",
                aliasFor: attributes["AliasFor"],
                externalAccess: ea
            ))

        case "Program":
            currentProgramName = attributes["Name"] ?? ""
            currentRoutines = []

        case "Routine":
            let routineType = attributes["Type"] ?? ""
            if routineType != "RLL" {
                skipDepth = 1
                return
            }
            currentRoutineName = attributes["Name"] ?? ""
            currentRungs = []
            inRoutine = true

        case "Rung" where inRoutine:
            currentRungNumber = UInt32(attributes["Number"] ?? "0") ?? 0
            currentRungComment = ""

        case "Comment" where inRoutine:
            capturingComment = true
            currentText = ""

        case "Text" where inRoutine:
            capturingText = true
            currentText = ""

        case "DataTypes", "Modules", "AddOnInstructionDefinitions", "Trends":
            skipDepth = 1

        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturingText || capturingComment {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if capturingText || capturingComment {
            if let str = String(data: CDATABlock, encoding: .utf8) {
                currentText += str
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if skipDepth > 0 {
            skipDepth -= 1
            return
        }

        switch elementName {
        case "Tags":
            inControllerTags = false
            inProgramTags = false

        case "Comment" where capturingComment:
            currentRungComment = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            capturingComment = false

        case "Text" where capturingText:
            let expr = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ";"))
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !expr.isEmpty {
                let element = RungExpressionParser.parse(expr)
                let rung = Rung(
                    id: UUID().uuidString,
                    number: currentRungNumber,
                    element: element,
                    comment: currentRungComment,
                    editable: true
                )
                currentRungs.append(rung)
            }
            capturingText = false

        case "Routine" where inRoutine:
            currentRoutines.append(RoutineBuild(name: currentRoutineName, rungs: currentRungs))
            inRoutine = false

        case "Program":
            programs.append((currentProgramName, currentRoutines))
            currentProgramName = ""

        case "Controller":
            buildProject()

        default: break
        }
    }

    private func buildProject() {
        let family: ControllerFamily = processorType.hasPrefix("1756")
            ? .controlLogix : .compactLogix

        var builtPrograms: [Program] = []
        for (progName, routines) in programs {
            let builtRoutines = routines.map { rb in
                Routine(id: UUID().uuidString, name: rb.name, description: "", rungs: rb.rungs)
            }
            builtPrograms.append(Program(
                id: UUID().uuidString,
                name: progName,
                description: "",
                mainRoutineName: routines.first?.name ?? "MainRoutine",
                faultRoutineName: "",
                routines: builtRoutines
            ))
        }

        let task = Task(
            id: UUID().uuidString,
            name: "MainTask",
            description: "",
            taskType: .continuous,
            priority: 10,
            programs: builtPrograms
        )

        project = PlcProject(
            formatVersion: 1,
            id: UUID().uuidString,
            name: controllerName,
            description: "",
            controller: Controller(
                name: controllerName,
                family: family,
                catalogNumber: processorType,
                firmwareVersion: "",
                description: ""
            ),
            tasks: [task],
            tagDatabase: TagDatabase(tags: tags),
            importedFrom: "L5X"
        )
    }

    private static func parseDataType(_ str: String, dimensions: String?) -> DataType {
        if let dims = dimensions, !dims.isEmpty {
            let dimValues = dims.split(separator: " ").compactMap { UInt32($0) }.filter { $0 > 0 }
            if !dimValues.isEmpty {
                return .array(elementTypeName: str, dimensions: dimValues)
            }
        }
        switch str.uppercased() {
        case "BOOL": return .bool_
        case "SINT": return .sint
        case "INT": return .int_
        case "DINT": return .dint
        case "LINT": return .lint
        case "REAL": return .real
        case "STRING": return .stringType
        case "TIMER": return .timer
        case "COUNTER": return .counter
        default: return .udt(name: str)
        }
    }
}

// MARK: - Rung Expression Parser

/// Parses L5K rung expression syntax into RungElement tree.
///
/// Grammar:
///   rung_expr = element+
///   element   = instruction | branch
///   branch    = '[' path (',' path)* ']'
///   path      = element+
///   instruction = MNEMONIC '(' operand (',' operand)* ')'
enum RungExpressionParser {

    static func parse(_ input: String) -> RungElement {
        var pos = input.startIndex
        let elements = parseElements(input, &pos, until: nil)
        if elements.count == 1 { return elements[0] }
        return .series(elements: elements)
    }

    private static func parseElements(_ input: String, _ pos: inout String.Index,
                                       until terminator: Character?) -> [RungElement] {
        var elements: [RungElement] = []
        skipSpaces(input, &pos)

        while pos < input.endIndex {
            let ch = input[pos]

            if let term = terminator, (ch == term || ch == ",") {
                break
            }

            if ch == "[" {
                pos = input.index(after: pos)
                let branch = parseBranch(input, &pos)
                elements.append(branch)
            } else if ch.isLetter || ch == "_" {
                let inst = parseInstruction(input, &pos)
                elements.append(.instruction(instruction: inst))
            } else {
                pos = input.index(after: pos) // skip unexpected char
            }
            skipSpaces(input, &pos)
        }

        return elements
    }

    private static func parseBranch(_ input: String, _ pos: inout String.Index) -> RungElement {
        var branches: [RungElement] = []

        while pos < input.endIndex {
            let path = parseElements(input, &pos, until: "]")
            let pathElement = path.count == 1 ? path[0] : .series(elements: path)
            branches.append(pathElement)

            if pos < input.endIndex && input[pos] == "," {
                pos = input.index(after: pos)
                skipSpaces(input, &pos)
            } else {
                break
            }
        }

        if pos < input.endIndex && input[pos] == "]" {
            pos = input.index(after: pos)
        }

        return .parallel(branches: branches)
    }

    private static func parseInstruction(_ input: String, _ pos: inout String.Index) -> Instruction {
        // Parse mnemonic
        let mnemonicStart = pos
        while pos < input.endIndex && (input[pos].isLetter || input[pos].isNumber || input[pos] == "_") {
            pos = input.index(after: pos)
        }
        let mnemonic = String(input[mnemonicStart..<pos])

        // Parse operands in parens
        var operands: [Operand] = []
        skipSpaces(input, &pos)
        if pos < input.endIndex && input[pos] == "(" {
            pos = input.index(after: pos)
            operands = parseOperands(input, &pos)
            if pos < input.endIndex && input[pos] == ")" {
                pos = input.index(after: pos)
            }
        }

        let instructionType = parseMnemonic(mnemonic)
        return Instruction(
            id: UUID().uuidString,
            instructionType: instructionType,
            operands: operands,
            comment: ""
        )
    }

    private static func parseOperands(_ input: String, _ pos: inout String.Index) -> [Operand] {
        var operands: [Operand] = []
        skipSpaces(input, &pos)

        while pos < input.endIndex && input[pos] != ")" {
            let op = parseOperand(input, &pos)
            operands.append(op)
            skipSpaces(input, &pos)
            if pos < input.endIndex && input[pos] == "," {
                pos = input.index(after: pos)
                skipSpaces(input, &pos)
            }
        }
        return operands
    }

    private static func parseOperand(_ input: String, _ pos: inout String.Index) -> Operand {
        skipSpaces(input, &pos)
        guard pos < input.endIndex else { return .intLiteral(value: 0) }

        // ? = don't care
        if input[pos] == "?" {
            pos = input.index(after: pos)
            return .intLiteral(value: 0)
        }

        // Try numeric (int or real)
        let numStart = pos
        var hasSign = false
        if input[pos] == "-" || input[pos] == "+" {
            hasSign = true
            pos = input.index(after: pos)
        }

        if pos < input.endIndex && input[pos].isNumber {
            var hasDot = false
            while pos < input.endIndex && (input[pos].isNumber || input[pos] == ".") {
                if input[pos] == "." { hasDot = true }
                pos = input.index(after: pos)
            }
            let numStr = String(input[numStart..<pos])

            // If next char is letter/underscore, this was actually a tag name start
            // (shouldn't happen with proper L5K but be defensive)
            if hasDot {
                if let val = Double(numStr) { return .realLiteral(value: val) }
            } else {
                if let val = Int64(numStr) { return .intLiteral(value: val) }
            }
        }

        // Reset if numeric parse consumed sign but nothing useful
        if hasSign && pos == input.index(after: numStart) {
            pos = numStart
        }

        // Tag reference
        let tagStart = pos
        while pos < input.endIndex {
            let ch = input[pos]
            if ch.isLetter || ch.isNumber || ch == "_" || ch == "." {
                pos = input.index(after: pos)
            } else if ch == "[" {
                // Array index
                pos = input.index(after: pos)
                while pos < input.endIndex && input[pos] != "]" {
                    pos = input.index(after: pos)
                }
                if pos < input.endIndex { pos = input.index(after: pos) }
            } else {
                break
            }
        }

        let tagName = String(input[tagStart..<pos])
        return .tagRef(name: tagName)
    }

    private static func parseMnemonic(_ mnemonic: String) -> InstructionType {
        switch mnemonic.uppercased() {
        case "XIC": return .xic
        case "XIO": return .xio
        case "OTE": return .ote
        case "OTL": return .otl
        case "OTU": return .otu
        case "ONS": return .ons
        case "TON": return .ton
        case "TOF": return .tof
        case "RTO": return .rto
        case "CTU": return .ctu
        case "CTD": return .ctd
        case "RES": return .res
        case "EQU", "EQ": return .equ
        case "NEQ", "NE": return .neq
        case "LES", "LT": return .les
        case "LEQ", "LE": return .leq
        case "GRT", "GT": return .grt
        case "GEQ", "GE": return .geq
        case "ADD": return .add
        case "SUB": return .sub
        case "MUL": return .mul
        case "DIV": return .div
        case "MOD": return .mod_
        case "NEG": return .neg
        case "MOV", "MOVE": return .mov
        case "COP": return .cop
        case "JMP": return .jmp
        case "LBL": return .lbl
        case "JSR": return .jsr
        case "RET": return .ret
        case "SBR": return .sbr
        default: return .unknown(mnemonic: mnemonic)
        }
    }

    private static func skipSpaces(_ input: String, _ pos: inout String.Index) {
        while pos < input.endIndex && input[pos] == " " {
            pos = input.index(after: pos)
        }
    }
}
