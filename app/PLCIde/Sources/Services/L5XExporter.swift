import Foundation

/// Exports a PlcProject to L5X (XML) format for Studio 5000.
enum L5XExporter {

    static func export(_ project: PlcProject) -> String {
        var out = ""

        let procType = project.controller.catalogNumber.isEmpty
            ? defaultProcessorType(project.controller.family)
            : project.controller.catalogNumber

        out += "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"
        out += "<RSLogix5000Content SchemaRevision=\"1.0\" SoftwareRevision=\"34.00\"\n"
        out += "                     TargetType=\"Controller\" ContainsContext=\"true\">\n"
        out += "  <Controller Name=\"\(xmlEscape(project.controller.name))\" ProcessorType=\"\(xmlEscape(procType))\">\n"

        // Controller tags
        out += "    <Tags>\n"
        for tag in project.tagDatabase.tags {
            if case .controller = tag.scope {
                formatTagXML(&out, tag: tag, indent: 6)
            }
        }
        out += "    </Tags>\n"

        // Programs
        out += "    <Programs>\n"
        for task in project.tasks {
            for program in task.programs {
                out += "      <Program Name=\"\(xmlEscape(program.name))\" Type=\"Normal\">\n"

                // Program-scoped tags
                let progTags = project.tagDatabase.tags.filter {
                    if case .program(let pn) = $0.scope { return pn == program.name }; return false
                }
                if !progTags.isEmpty {
                    out += "        <Tags>\n"
                    for tag in progTags {
                        formatTagXML(&out, tag: tag, indent: 10)
                    }
                    out += "        </Tags>\n"
                }

                // Routines
                out += "        <Routines>\n"
                for routine in program.routines {
                    out += "          <Routine Name=\"\(xmlEscape(routine.name))\" Type=\"RLL\">\n"
                    out += "            <RLLContent>\n"
                    for rung in routine.rungs {
                        out += "              <Rung Number=\"\(rung.number)\" Type=\"N\">\n"
                        if !rung.comment.isEmpty {
                            out += "                <Comment><![CDATA[\(rung.comment)]]></Comment>\n"
                        }
                        let expr = L5KExporter.formatRungElement(rung.element)
                        out += "                <Text><![CDATA[\(expr) ;]]></Text>\n"
                        out += "              </Rung>\n"
                    }
                    out += "            </RLLContent>\n"
                    out += "          </Routine>\n"
                }
                out += "        </Routines>\n"
                out += "      </Program>\n"
            }
        }
        out += "    </Programs>\n"

        // Tasks
        out += "    <Tasks>\n"
        for task in project.tasks {
            let typeStr: String
            let rate: UInt32
            switch task.taskType {
            case .continuous: typeStr = "CONTINUOUS"; rate = 10
            case .periodic(let ms): typeStr = "PERIODIC"; rate = ms
            case .event: typeStr = "EVENT"; rate = 10
            }
            out += "      <Task Name=\"\(xmlEscape(task.name))\" Type=\"\(typeStr)\" Rate=\"\(rate)\" Priority=\"\(task.priority)\">\n"
            out += "        <ScheduledPrograms>\n"
            for program in task.programs {
                out += "          <ScheduledProgram Name=\"\(xmlEscape(program.name))\"/>\n"
            }
            out += "        </ScheduledPrograms>\n"
            out += "      </Task>\n"
        }
        out += "    </Tasks>\n"

        out += "  </Controller>\n"
        out += "</RSLogix5000Content>\n"

        return out
    }

    // MARK: - Helpers

    private static func formatTagXML(_ out: inout String, tag: Tag, indent: Int) {
        let pad = String(repeating: " ", count: indent)
        let dtStr = formatDataTypeForXML(tag.dataType)
        let eaStr: String
        switch tag.externalAccess {
        case .readWrite: eaStr = "Read/Write"
        case .readOnly: eaStr = "Read Only"
        case .none: eaStr = "None"
        }

        if tag.description.isEmpty && tag.aliasFor == nil {
            out += "\(pad)<Tag Name=\"\(xmlEscape(tag.name))\" TagType=\"Base\" DataType=\"\(xmlEscape(dtStr))\" ExternalAccess=\"\(eaStr)\"/>\n"
        } else {
            out += "\(pad)<Tag Name=\"\(xmlEscape(tag.name))\" TagType=\"Base\" DataType=\"\(xmlEscape(dtStr))\" ExternalAccess=\"\(eaStr)\""
            if let alias = tag.aliasFor {
                out += " AliasFor=\"\(xmlEscape(alias))\""
            }
            out += ">\n"
            if !tag.description.isEmpty {
                out += "\(pad)  <Description><![CDATA[\(tag.description)]]></Description>\n"
            }
            out += "\(pad)</Tag>\n"
        }
    }

    private static func formatDataTypeForXML(_ dt: DataType) -> String {
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
        case .array(let el, _): return el
        case .udt(let name): return name
        }
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func defaultProcessorType(_ family: ControllerFamily) -> String {
        switch family {
        case .controlLogix: return "1756-L85E"
        case .compactLogix: return "1769-L33ER"
        }
    }
}
