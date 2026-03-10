//! Export module — serialize PlcProject to L5K (ASCII) and L5X (XML) formats.
//!
//! The rung expression format reuses `format_rung_element()` logic from `project.rs`,
//! which already outputs valid L5K syntax (e.g., `[XIC(A),XIC(B)] OTE(Y)`).

use crate::ast::*;
use crate::project::{format_instruction_type, PlcProject};
use crate::tags::*;

// ─── L5K Export ──────────────────────────────────────────────────────────────

/// Export a project to L5K (ASCII) format.
#[uniffi::export]
pub fn export_l5k(project: &PlcProject) -> Result<String, String> {
    let mut out = String::with_capacity(4096);

    // Controller header
    let proc_type = if project.controller.catalog_number.is_empty() {
        match project.controller.family {
            ControllerFamily::ControlLogix => "1756-L85E",
            ControllerFamily::CompactLogix => "1769-L33ER",
        }
    } else {
        &project.controller.catalog_number
    };

    out.push_str(&format!(
        "CONTROLLER {} (ProcessorType := \"{}\", MajorRev := 34)\n",
        project.controller.name, proc_type
    ));

    // Controller-scope tags
    let controller_tags: Vec<&Tag> = project.tag_database.tags.iter()
        .filter(|t| matches!(t.scope, TagScope::Controller))
        .collect();
    if !controller_tags.is_empty() {
        out.push_str("  TAG\n");
        for tag in &controller_tags {
            out.push_str("    ");
            out.push_str(&format_tag_l5k(tag));
            out.push('\n');
        }
        out.push_str("  END_TAG\n");
    }

    // Programs
    for task in &project.tasks {
        for program in &task.programs {
            out.push_str(&format!("  PROGRAM {} (Type := \"PROGRAM\")\n", program.name));

            // Program-scoped tags
            let prog_tags: Vec<&Tag> = project.tag_database.tags.iter()
                .filter(|t| matches!(&t.scope, TagScope::Program { program_name } if program_name == &program.name))
                .collect();
            if !prog_tags.is_empty() {
                out.push_str("    TAG\n");
                for tag in &prog_tags {
                    out.push_str("      ");
                    out.push_str(&format_tag_l5k(tag));
                    out.push('\n');
                }
                out.push_str("    END_TAG\n");
            }

            // Routines
            for routine in &program.routines {
                out.push_str(&format!("    ROUTINE {} (Type := \"RLL\")\n", routine.name));
                for rung in &routine.rungs {
                    if !rung.comment.is_empty() {
                        out.push_str(&format!("      RC:=\"{}\";\n", escape_l5k_string(&rung.comment)));
                    }
                    let expr = format_rung_l5k(&rung.element);
                    out.push_str(&format!("      N: {} ;\n", expr));
                }
                out.push_str("    END_ROUTINE\n");
            }

            out.push_str("  END_PROGRAM\n");
        }
    }

    // Tasks
    for task in &project.tasks {
        let type_str = match &task.task_type {
            TaskType::Continuous => "CONTINUOUS".to_string(),
            TaskType::Periodic { period_ms } => format!("PERIODIC, Rate := {}", period_ms),
            TaskType::Event { trigger } => format!("EVENT, EventTrigger := \"{}\"", trigger),
        };
        out.push_str(&format!(
            "  TASK {} (Type := {}, Priority := {})\n",
            task.name, type_str, task.priority
        ));
        for program in &task.programs {
            out.push_str(&format!("    {};\n", program.name));
        }
        out.push_str("  END_TASK\n");
    }

    out.push_str("END_CONTROLLER\n");
    Ok(out)
}

/// Format a rung element as L5K rung expression text.
/// This produces valid L5K syntax: `XIC(tag) OTE(out)`, `[branch1,branch2]`, etc.
pub fn format_rung_l5k(element: &RungElement) -> String {
    match element {
        RungElement::Instruction { instruction } => {
            let mnemonic = format_instruction_type(&instruction.instruction_type);
            let operands: Vec<String> = instruction.operands.iter()
                .map(format_operand_l5k)
                .collect();
            format!("{}({})", mnemonic, operands.join(","))
        }
        RungElement::Series { elements } => {
            elements.iter().map(format_rung_l5k).collect::<Vec<_>>().join(" ")
        }
        RungElement::Parallel { branches } => {
            let paths: Vec<String> = branches.iter().map(format_rung_l5k).collect();
            format!("[{}]", paths.join(","))
        }
    }
}

fn format_operand_l5k(op: &Operand) -> String {
    match op {
        Operand::TagRef { name } => name.clone(),
        Operand::IntLiteral { value } => value.to_string(),
        Operand::RealLiteral { value } => format!("{:.1}", value),
    }
}

fn format_tag_l5k(tag: &Tag) -> String {
    let type_str = format_data_type_l5k(&tag.data_type);
    let mut result = format!("{} : {}", tag.name, type_str);

    let mut attrs = Vec::new();
    if !tag.description.is_empty() {
        attrs.push(format!("Description := \"{}\"", escape_l5k_string(&tag.description)));
    }
    if tag.external_access != ExternalAccess::ReadWrite {
        let ea = match tag.external_access {
            ExternalAccess::ReadOnly => "Read Only",
            ExternalAccess::None => "None",
            ExternalAccess::ReadWrite => "Read/Write",
        };
        attrs.push(format!("ExternalAccess := \"{}\"", ea));
    }
    if let Some(ref alias) = tag.alias_for {
        attrs.push(format!("AliasFor := \"{}\"", alias));
    }
    if !attrs.is_empty() {
        result.push_str(&format!(" ({})", attrs.join(", ")));
    }

    if !tag.initial_value.is_empty() {
        result.push_str(&format!(" := {}", tag.initial_value));
    }
    result.push(';');
    result
}

fn format_data_type_l5k(dt: &DataType) -> String {
    match dt {
        DataType::Bool => "BOOL".into(),
        DataType::Sint => "SINT".into(),
        DataType::Int => "INT".into(),
        DataType::Dint => "DINT".into(),
        DataType::Lint => "LINT".into(),
        DataType::Real => "REAL".into(),
        DataType::StringType => "STRING".into(),
        DataType::Timer => "TIMER".into(),
        DataType::Counter => "COUNTER".into(),
        DataType::Array { element_type_name, dimensions } => {
            let dims: Vec<String> = dimensions.iter().map(|d| d.to_string()).collect();
            format!("{}[{}]", element_type_name, dims.join(","))
        }
        DataType::Udt { name } => name.clone(),
    }
}

fn escape_l5k_string(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

// ─── L5X Export ──────────────────────────────────────────────────────────────

/// Export a project to L5X (XML) format.
#[uniffi::export]
pub fn export_l5x(project: &PlcProject) -> Result<String, String> {
    let mut out = String::with_capacity(8192);

    let proc_type = if project.controller.catalog_number.is_empty() {
        match project.controller.family {
            ControllerFamily::ControlLogix => "1756-L85E",
            ControllerFamily::CompactLogix => "1769-L33ER",
        }
    } else {
        &project.controller.catalog_number
    };

    // XML header
    out.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n");
    out.push_str("<RSLogix5000Content SchemaRevision=\"1.0\" SoftwareRevision=\"34.00\"\n");
    out.push_str("                     TargetType=\"Controller\" ContainsContext=\"true\">\n");
    out.push_str(&format!(
        "  <Controller Name=\"{}\" ProcessorType=\"{}\">\n",
        xml_escape(&project.controller.name), xml_escape(proc_type)
    ));

    // Controller tags
    out.push_str("    <Tags>\n");
    for tag in &project.tag_database.tags {
        if matches!(tag.scope, TagScope::Controller) {
            format_tag_l5x(&mut out, tag, 6);
        }
    }
    out.push_str("    </Tags>\n");

    // Programs
    out.push_str("    <Programs>\n");
    for task in &project.tasks {
        for program in &task.programs {
            out.push_str(&format!(
                "      <Program Name=\"{}\" Type=\"Normal\">\n",
                xml_escape(&program.name)
            ));

            // Program-scoped tags
            let prog_tags: Vec<&Tag> = project.tag_database.tags.iter()
                .filter(|t| matches!(&t.scope, TagScope::Program { program_name } if program_name == &program.name))
                .collect();
            if !prog_tags.is_empty() {
                out.push_str("        <Tags>\n");
                for tag in &prog_tags {
                    format_tag_l5x(&mut out, tag, 10);
                }
                out.push_str("        </Tags>\n");
            }

            // Routines
            out.push_str("        <Routines>\n");
            for routine in &program.routines {
                out.push_str(&format!(
                    "          <Routine Name=\"{}\" Type=\"RLL\">\n",
                    xml_escape(&routine.name)
                ));
                out.push_str("            <RLLContent>\n");
                for rung in &routine.rungs {
                    out.push_str(&format!(
                        "              <Rung Number=\"{}\" Type=\"N\">\n",
                        rung.number
                    ));
                    if !rung.comment.is_empty() {
                        out.push_str(&format!(
                            "                <Comment><![CDATA[{}]]></Comment>\n",
                            rung.comment
                        ));
                    }
                    let expr = format_rung_l5k(&rung.element);
                    out.push_str(&format!(
                        "                <Text><![CDATA[{} ;]]></Text>\n",
                        expr
                    ));
                    out.push_str("              </Rung>\n");
                }
                out.push_str("            </RLLContent>\n");
                out.push_str("          </Routine>\n");
            }
            out.push_str("        </Routines>\n");
            out.push_str("      </Program>\n");
        }
    }
    out.push_str("    </Programs>\n");

    // Tasks
    out.push_str("    <Tasks>\n");
    for task in &project.tasks {
        let type_str = match &task.task_type {
            TaskType::Continuous => "CONTINUOUS",
            TaskType::Periodic { .. } => "PERIODIC",
            TaskType::Event { .. } => "EVENT",
        };
        let rate = match &task.task_type {
            TaskType::Periodic { period_ms } => *period_ms,
            _ => 10,
        };
        out.push_str(&format!(
            "      <Task Name=\"{}\" Type=\"{}\" Rate=\"{}\" Priority=\"{}\">\n",
            xml_escape(&task.name), type_str, rate, task.priority
        ));
        out.push_str("        <ScheduledPrograms>\n");
        for program in &task.programs {
            out.push_str(&format!(
                "          <ScheduledProgram Name=\"{}\"/>\n",
                xml_escape(&program.name)
            ));
        }
        out.push_str("        </ScheduledPrograms>\n");
        out.push_str("      </Task>\n");
    }
    out.push_str("    </Tasks>\n");

    out.push_str("  </Controller>\n");
    out.push_str("</RSLogix5000Content>\n");

    Ok(out)
}

fn format_tag_l5x(out: &mut String, tag: &Tag, indent: usize) {
    let pad = " ".repeat(indent);
    let dt_str = format_data_type_l5k(&tag.data_type);

    // Array dimensions attribute
    let dims_attr = match &tag.data_type {
        DataType::Array { dimensions, .. } => {
            let dims_str: Vec<String> = dimensions.iter().map(|d| d.to_string()).collect();
            format!(" Dimensions=\"{}\"", dims_str.join(" "))
        }
        _ => String::new(),
    };

    // Base data type for arrays
    let base_dt = match &tag.data_type {
        DataType::Array { element_type_name, .. } => element_type_name.clone(),
        _ => dt_str.clone(),
    };

    let ea_str = match tag.external_access {
        ExternalAccess::ReadWrite => "Read/Write",
        ExternalAccess::ReadOnly => "Read Only",
        ExternalAccess::None => "None",
    };

    if tag.description.is_empty() && tag.alias_for.is_none() {
        // Self-closing tag
        out.push_str(&format!(
            "{}<Tag Name=\"{}\" TagType=\"Base\" DataType=\"{}\"{}  ExternalAccess=\"{}\"/>\n",
            pad, xml_escape(&tag.name), xml_escape(&base_dt), dims_attr, ea_str
        ));
    } else {
        out.push_str(&format!(
            "{}<Tag Name=\"{}\" TagType=\"Base\" DataType=\"{}\"{}  ExternalAccess=\"{}\"",
            pad, xml_escape(&tag.name), xml_escape(&base_dt), dims_attr, ea_str
        ));
        if let Some(ref alias) = tag.alias_for {
            out.push_str(&format!(" AliasFor=\"{}\"", xml_escape(alias)));
        }
        out.push_str(">\n");
        if !tag.description.is_empty() {
            out.push_str(&format!(
                "{}  <Description><![CDATA[{}]]></Description>\n",
                pad, tag.description
            ));
        }
        out.push_str(&format!("{}</Tag>\n", pad));
    }
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

// ─── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn build_test_project() -> PlcProject {
        let mut project = PlcProject::new("TestCtrl", ControllerFamily::CompactLogix);
        project.controller.catalog_number = "1769-L33ER".to_string();

        // Tags
        project.tag_database.add_tag(Tag::new_bool("Start_PB", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Motor_Run", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_timer("Delay", TagScope::Controller));

        // Task + Program + Routine
        let mut task = Task::new_continuous("MainTask");
        let mut program = Program::new("MainProgram");

        if let Some(routine) = program.main_routine_mut() {
            // Rung 0: seal-in
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::parallel(vec![
                        RungElement::instruction(Instruction::contact(true, "Start_PB")),
                        RungElement::instruction(Instruction::contact(true, "Motor_Run")),
                    ]),
                    RungElement::instruction(Instruction::coil(InstructionType::Otl, "Motor_Run")),
                ]),
                "Seal-in circuit",
            );

            // Rung 1: timer
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(true, "Motor_Run")),
                    RungElement::instruction(Instruction::new(
                        InstructionType::Ton,
                        vec![
                            Operand::TagRef { name: "Delay".to_string() },
                            Operand::IntLiteral { value: 5000 },
                            Operand::IntLiteral { value: 0 },
                        ],
                    )),
                ]),
                "Run delay",
            );
        }

        task.add_program(program);
        project.add_task(task);
        project
    }

    #[test]
    fn l5k_export_basic_structure() {
        let project = build_test_project();
        let l5k = export_l5k(&project).unwrap();

        assert!(l5k.starts_with("CONTROLLER TestCtrl"));
        assert!(l5k.contains("ProcessorType := \"1769-L33ER\""));
        assert!(l5k.contains("Start_PB : BOOL := 0;"));
        assert!(l5k.contains("Motor_Run : BOOL := 0;"));
        assert!(l5k.contains("Delay : TIMER;"));
        assert!(l5k.contains("PROGRAM MainProgram"));
        assert!(l5k.contains("ROUTINE MainRoutine"));
        assert!(l5k.contains("RC:=\"Seal-in circuit\""));
        assert!(l5k.contains("[XIC(Start_PB),XIC(Motor_Run)] OTL(Motor_Run)"));
        assert!(l5k.contains("TON(Delay,5000,0)"));
        assert!(l5k.contains("TASK MainTask"));
        assert!(l5k.contains("END_CONTROLLER"));
    }

    #[test]
    fn l5x_export_basic_structure() {
        let project = build_test_project();
        let l5x = export_l5x(&project).unwrap();

        assert!(l5x.contains("<?xml version=\"1.0\""));
        assert!(l5x.contains("<RSLogix5000Content"));
        assert!(l5x.contains("Controller Name=\"TestCtrl\""));
        assert!(l5x.contains("ProcessorType=\"1769-L33ER\""));
        assert!(l5x.contains("Tag Name=\"Start_PB\""));
        assert!(l5x.contains("DataType=\"BOOL\""));
        assert!(l5x.contains("Program Name=\"MainProgram\""));
        assert!(l5x.contains("Routine Name=\"MainRoutine\""));
        assert!(l5x.contains("<![CDATA[Seal-in circuit]]>"));
        assert!(l5x.contains("[XIC(Start_PB),XIC(Motor_Run)] OTL(Motor_Run) ;"));
        assert!(l5x.contains("Task Name=\"MainTask\""));
        assert!(l5x.contains("</RSLogix5000Content>"));
    }

    #[test]
    fn l5k_rung_format_unknown_instruction() {
        let element = RungElement::series(vec![
            RungElement::instruction(Instruction::contact(true, "A")),
            RungElement::instruction(Instruction::new(
                InstructionType::Unknown { mnemonic: "MSG".to_string() },
                vec![
                    Operand::TagRef { name: "Config".to_string() },
                    Operand::IntLiteral { value: 0 },
                ],
            )),
            RungElement::instruction(Instruction::coil(InstructionType::Ote, "Done")),
        ]);

        let l5k = format_rung_l5k(&element);
        assert_eq!(l5k, "XIC(A) MSG(Config,0) OTE(Done)");
    }

    #[test]
    fn l5k_export_program_scoped_tags() {
        let mut project = build_test_project();
        project.tag_database.add_tag(Tag::new_dint("Local_Count", TagScope::Program {
            program_name: "MainProgram".to_string(),
        }));

        let l5k = export_l5k(&project).unwrap();
        // Program-scoped tags appear inside the PROGRAM block
        let program_section_start = l5k.find("PROGRAM MainProgram").unwrap();
        let end_program = l5k.find("END_PROGRAM").unwrap();
        let program_section = &l5k[program_section_start..end_program];
        assert!(program_section.contains("Local_Count : DINT"));
    }

    // NOTE: Round-trip tests (export → re-import) live in plc-parser::import::tests
    // because plc-core can't depend on plc-parser (would create a cycle).

    #[test]
    fn l5k_tag_with_description() {
        let mut tag = Tag::new_bool("Motor_Start", TagScope::Controller);
        tag.description = "Start pushbutton".to_string();

        let formatted = format_tag_l5k(&tag);
        assert_eq!(formatted, "Motor_Start : BOOL (Description := \"Start pushbutton\") := 0;");
    }

    #[test]
    fn l5k_array_tag() {
        let tag = Tag {
            id: "test".to_string(),
            name: "Speeds".to_string(),
            data_type: DataType::Array {
                element_type_name: "DINT".to_string(),
                dimensions: vec![10],
            },
            scope: TagScope::Controller,
            description: String::new(),
            initial_value: String::new(),
            alias_for: None,
            external_access: ExternalAccess::ReadWrite,
        };

        let formatted = format_tag_l5k(&tag);
        assert_eq!(formatted, "Speeds : DINT[10];");
    }
}
