import Foundation

/// Exports a PlcProject to L5K (ASCII) format for Studio 5000.
enum L5KExporter {

    static func export(_ project: PlcProject) -> String {
        var out = ""

        let procType = project.controller.catalogNumber.isEmpty
            ? defaultProcessorType(project.controller.family)
            : project.controller.catalogNumber

        out += "CONTROLLER \(project.controller.name) (ProcessorType := \"\(procType)\", MajorRev := 34)\n"

        // Controller-scope tags
        let controllerTags = project.tagDatabase.tags.filter {
            if case .controller = $0.scope { return true }; return false
        }
        if !controllerTags.isEmpty {
            out += "  TAG\n"
            for tag in controllerTags {
                out += "    \(formatTag(tag))\n"
            }
            out += "  END_TAG\n"
        }

        // Programs
        for task in project.tasks {
            for program in task.programs {
                out += "  PROGRAM \(program.name) (Type := \"PROGRAM\")\n"

                // Program-scoped tags
                let progTags = project.tagDatabase.tags.filter {
                    if case .program(let pn) = $0.scope { return pn == program.name }; return false
                }
                if !progTags.isEmpty {
                    out += "    TAG\n"
                    for tag in progTags {
                        out += "      \(formatTag(tag))\n"
                    }
                    out += "    END_TAG\n"
                }

                // Routines
                for routine in program.routines {
                    out += "    ROUTINE \(routine.name) (Type := \"RLL\")\n"
                    for rung in routine.rungs {
                        if !rung.comment.isEmpty {
                            out += "      RC:=\"\(escapeL5K(rung.comment))\";\n"
                        }
                        let expr = formatRungElement(rung.element)
                        out += "      N: \(expr) ;\n"
                    }
                    out += "    END_ROUTINE\n"
                }

                out += "  END_PROGRAM\n"
            }
        }

        // Tasks
        for task in project.tasks {
            let typeStr: String
            switch task.taskType {
            case .continuous: typeStr = "CONTINUOUS"
            case .periodic(let ms): typeStr = "PERIODIC, Rate := \(ms)"
            case .event(let trigger): typeStr = "EVENT, EventTrigger := \"\(trigger)\""
            }
            out += "  TASK \(task.name) (Type := \(typeStr), Priority := \(task.priority))\n"
            for program in task.programs {
                out += "    \(program.name);\n"
            }
            out += "  END_TASK\n"
        }

        out += "END_CONTROLLER\n"
        return out
    }

    // MARK: - Helpers

    static func formatRungElement(_ element: RungElement) -> String {
        switch element {
        case .instruction(let inst):
            let ops = inst.operands.map { formatOperand($0) }.joined(separator: ",")
            return "\(inst.instructionType.mnemonic)(\(ops))"
        case .series(let elements):
            return elements.map { formatRungElement($0) }.joined(separator: " ")
        case .parallel(let branches):
            let paths = branches.map { formatRungElement($0) }.joined(separator: ",")
            return "[\(paths)]"
        }
    }

    private static func formatOperand(_ op: Operand) -> String {
        switch op {
        case .tagRef(let name): return name
        case .intLiteral(let value): return "\(value)"
        case .realLiteral(let value): return String(format: "%.1f", value)
        }
    }

    private static func formatTag(_ tag: Tag) -> String {
        let typeStr = formatDataType(tag.dataType)
        var result = "\(tag.name) : \(typeStr)"

        var attrs: [String] = []
        if !tag.description.isEmpty {
            attrs.append("Description := \"\(escapeL5K(tag.description))\"")
        }
        if !attrs.isEmpty {
            result += " (\(attrs.joined(separator: ", ")))"
        }

        if !tag.initialValue.isEmpty {
            result += " := \(tag.initialValue)"
        }
        result += ";"
        return result
    }

    private static func formatDataType(_ dt: DataType) -> String {
        switch dt {
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

    private static func escapeL5K(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func defaultProcessorType(_ family: ControllerFamily) -> String {
        switch family {
        case .controlLogix: return "1756-L85E"
        case .compactLogix: return "1769-L33ER"
        }
    }
}
