//! L5X (XML) parser for Allen-Bradley RSLogix 5000 / Studio 5000 files.
//!
//! # L5X File Structure
//!
//! L5X is Rockwell's XML-based export format. The structure mirrors the project hierarchy:
//!
//! ```xml
//! <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
//! <RSLogix5000Content SchemaRevision="1.0" SoftwareRevision="34.00"
//!                      TargetType="Controller" ContainsContext="true">
//!   <Controller Name="MainController" ProcessorType="1769-L33ER" ...>
//!     <DataTypes>
//!       <DataType Name="MyUDT" ...>
//!         <Members>
//!           <Member Name="Field1" DataType="DINT" Dimension="0" .../>
//!         </Members>
//!       </DataType>
//!     </DataTypes>
//!
//!     <Tags>
//!       <Tag Name="Motor_Start" TagType="Base" DataType="BOOL" ...>
//!         <Description><![CDATA[Start pushbutton]]></Description>
//!         <Data Format="Decorated">
//!           <DataValue DataType="BOOL" Value="0"/>
//!         </Data>
//!       </Tag>
//!       <Tag Name="Delay_Timer" TagType="Base" DataType="TIMER" ...>
//!         <Data Format="Decorated">
//!           <Structure DataType="TIMER">
//!             <DataValueMember Name="PRE" DataType="DINT" Value="5000"/>
//!             <DataValueMember Name="ACC" DataType="DINT" Value="0"/>
//!             <DataValueMember Name="EN" DataType="BOOL" Value="0"/>
//!             <DataValueMember Name="TT" DataType="BOOL" Value="0"/>
//!             <DataValueMember Name="DN" DataType="BOOL" Value="0"/>
//!           </Structure>
//!         </Data>
//!       </Tag>
//!     </Tags>
//!
//!     <Programs>
//!       <Program Name="MainProgram" Type="Normal" ...>
//!         <Tags><!-- Program-scoped tags --></Tags>
//!         <Routines>
//!           <Routine Name="MainRoutine" Type="RLL">
//!             <RLLContent>
//!               <Rung Number="0" Type="N">
//!                 <Comment><![CDATA[Motor seal-in circuit]]></Comment>
//!                 <Text><![CDATA[[XIC(Start_PB) ,XIC(Motor_Run)] OTL(Motor_Run) ;]]></Text>
//!               </Rung>
//!             </RLLContent>
//!           </Routine>
//!         </Routines>
//!       </Program>
//!     </Programs>
//!
//!     <Tasks>
//!       <Task Name="MainTask" Type="CONTINUOUS" Rate="10" Priority="10" ...>
//!         <ScheduledPrograms>
//!           <ScheduledProgram Name="MainProgram"/>
//!         </ScheduledPrograms>
//!       </Task>
//!     </Tasks>
//!   </Controller>
//! </RSLogix5000Content>
//! ```
//!
//! Key points:
//! - Rung expressions in `<Text>` elements use the SAME syntax as L5K
//! - Tags store both raw data and decorated (human-readable) data
//! - Structure types (TIMER, COUNTER, UDTs) have nested `<Structure>` elements
//! - Comments use CDATA sections

use quick_xml::events::Event;
use quick_xml::reader::Reader;

use plc_core::ast::*;
use plc_core::tags::*;
use plc_core::project::PlcProject;

use crate::l5k;

/// Errors that can occur during L5X parsing.
#[derive(Debug, Clone, thiserror::Error)]
pub enum L5xError {
    #[error("XML parse error: {0}")]
    XmlError(String),

    #[error("Missing required attribute '{attribute}' on element '{element}'")]
    MissingAttribute { element: String, attribute: String },

    #[error("Unexpected element: {0}")]
    UnexpectedElement(String),

    #[error("Rung expression error: {0}")]
    RungError(String),

    #[error("Unsupported routine type: {0} (only RLL/ladder is supported in v1)")]
    UnsupportedRoutineType(String),
}

/// Parse an L5X file from a string into a PlcProject.
pub fn parse_l5x(xml_content: &str) -> Result<PlcProject, L5xError> {
    let mut reader = Reader::from_str(xml_content);
    reader.config_mut().trim_text(true);

    let mut project: Option<PlcProject> = None;
    let mut state = ParseState::Root;
    let mut current_program_name = String::new();
    let mut current_routine_name = String::new();
    let mut current_rung_number: u32 = 0;
    let mut current_rung_comment = String::new();
    let mut buf = Vec::new();

    // Track nesting for skip logic
    let mut skip_depth: usize = 0;
    let mut skipping = false;

    loop {
        match reader.read_event_into(&mut buf) {
            Ok(Event::Start(e)) => {
                if skipping {
                    skip_depth += 1;
                    continue;
                }

                let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();

                match tag_name.as_str() {
                    "Controller" => {
                        let name = get_attr(&e, "Name")?;
                        let proc_type = get_attr(&e, "ProcessorType").unwrap_or_default();
                        let family = if proc_type.starts_with("1756") {
                            ControllerFamily::ControlLogix
                        } else {
                            ControllerFamily::CompactLogix
                        };
                        let mut p = PlcProject::new(&name, family);
                        p.controller.catalog_number = proc_type;
                        project = Some(p);
                        state = ParseState::Controller;
                    }

                    "Tag" if matches!(state, ParseState::ControllerTags | ParseState::ProgramTags) => {
                        parse_tag_element(&e, &state, &current_program_name, &mut project)?;
                    }

                    "Tags" if matches!(state, ParseState::Controller) => {
                        state = ParseState::ControllerTags;
                    }
                    "Tags" if matches!(state, ParseState::Program) => {
                        state = ParseState::ProgramTags;
                    }

                    "Programs" => {
                        state = ParseState::Programs;
                    }
                    "Program" if matches!(state, ParseState::Programs) => {
                        current_program_name = get_attr(&e, "Name")?;
                        let program = Program::new(&current_program_name);
                        if let Some(ref mut proj) = project {
                            // Ensure we have a task to attach this program to
                            if proj.tasks.is_empty() {
                                proj.tasks.push(Task::new_continuous("MainTask"));
                            }
                            proj.tasks.last_mut().unwrap().programs.push(program);
                        }
                        state = ParseState::Program;
                    }

                    "Routine" if matches!(state, ParseState::Program | ParseState::Routines) => {
                        current_routine_name = get_attr(&e, "Name")?;
                        let routine_type = get_attr(&e, "Type").unwrap_or_default();

                        if routine_type != "RLL" {
                            // Skip non-ladder routines (ST, FBD, SFC)
                            skipping = true;
                            skip_depth = 1;
                            continue;
                        }

                        state = ParseState::Routine;
                    }

                    "Routines" if matches!(state, ParseState::Program) => {
                        state = ParseState::Routines;
                    }

                    "Rung" if matches!(state, ParseState::Routine | ParseState::RllContent) => {
                        current_rung_number = get_attr(&e, "Number")
                            .ok()
                            .and_then(|s| s.parse().ok())
                            .unwrap_or(0);
                        current_rung_comment.clear();
                        state = ParseState::Rung;
                    }

                    "RLLContent" if matches!(state, ParseState::Routine) => {
                        state = ParseState::RllContent;
                    }

                    "Comment" if matches!(state, ParseState::Rung) => {
                        state = ParseState::RungComment;
                    }

                    "Text" if matches!(state, ParseState::Rung) => {
                        state = ParseState::RungText;
                    }

                    "Tasks" => {
                        state = ParseState::Tasks;
                    }
                    "Task" if matches!(state, ParseState::Tasks) => {
                        let name = get_attr(&e, "Name")?;
                        let task_type_str = get_attr(&e, "Type").unwrap_or_default();
                        let rate = get_attr(&e, "Rate")
                            .ok()
                            .and_then(|s| s.parse::<f32>().ok())
                            .unwrap_or(10.0);
                        let priority = get_attr(&e, "Priority")
                            .ok()
                            .and_then(|s| s.parse::<u32>().ok())
                            .unwrap_or(10);

                        if let Some(ref mut proj) = project {
                            if let Some(t) = proj.tasks.iter_mut().find(|t| t.name == name) {
                                t.priority = priority;
                            } else {
                                let mut t = match task_type_str.as_str() {
                                    "PERIODIC" => Task::new_periodic(&name, rate as u32),
                                    _ => Task::new_continuous(&name),
                                };
                                t.priority = priority;
                                proj.tasks.push(t);
                            }
                        }
                    }

                    // Skip elements we don't handle yet
                    "DataTypes" | "Modules" | "AddOnInstructionDefinitions" | "Trends" => {
                        skipping = true;
                        skip_depth = 1;
                    }

                    _ => {}
                }
            }

            Ok(Event::End(e)) => {
                if skipping {
                    skip_depth -= 1;
                    if skip_depth == 0 {
                        skipping = false;
                    }
                    continue;
                }

                let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                match tag_name.as_str() {
                    "Tags" => {
                        state = match state {
                            ParseState::ControllerTags => ParseState::Controller,
                            ParseState::ProgramTags => ParseState::Program,
                            _ => state,
                        };
                    }
                    "Programs" => state = ParseState::Controller,
                    "Program" => state = ParseState::Programs,
                    "Routines" => state = ParseState::Program,
                    "Routine" => state = ParseState::Routines,
                    "RLLContent" => state = ParseState::Routine,
                    "Rung" => state = ParseState::RllContent,
                    "Comment" => state = ParseState::Rung,
                    "Text" => state = ParseState::Rung,
                    "Tasks" => state = ParseState::Controller,
                    _ => {}
                }
            }

            Ok(Event::Text(e)) => {
                if skipping {
                    continue;
                }
                let text = e.unescape().unwrap_or_default().to_string();
                handle_text_content(
                    &text, &state, &mut current_rung_comment, &mut project,
                    &current_program_name, &current_routine_name, current_rung_number,
                )?;
            }

            Ok(Event::CData(e)) => {
                if skipping {
                    continue;
                }
                let text = String::from_utf8_lossy(&e).to_string();
                handle_text_content(
                    &text, &state, &mut current_rung_comment, &mut project,
                    &current_program_name, &current_routine_name, current_rung_number,
                )?;
            }

            Ok(Event::Empty(e)) => {
                if skipping {
                    continue;
                }

                let tag_name = String::from_utf8_lossy(e.name().as_ref()).to_string();
                // Self-closing elements: <Tag ... />, <ScheduledProgram ... />, etc.
                if tag_name == "Tag" && matches!(state, ParseState::ControllerTags | ParseState::ProgramTags) {
                    parse_tag_element(&e, &state, &current_program_name, &mut project)?;
                }
            }

            Ok(Event::Eof) => break,
            Err(e) => return Err(L5xError::XmlError(format!("XML error at position {}: {}", reader.error_position(), e))),
            _ => {}
        }
        buf.clear();
    }

    project.ok_or_else(|| L5xError::XmlError("No Controller element found".to_string()))
}

#[derive(Debug, Clone, PartialEq)]
enum ParseState {
    Root,
    Controller,
    ControllerTags,
    Programs,
    Program,
    ProgramTags,
    Routines,
    Routine,
    RllContent,
    Rung,
    RungComment,
    RungText,
    Tasks,
}

fn get_attr(e: &quick_xml::events::BytesStart, name: &str) -> Result<String, L5xError> {
    for attr in e.attributes().flatten() {
        if attr.key.as_ref() == name.as_bytes() {
            return Ok(String::from_utf8_lossy(&attr.value).to_string());
        }
    }
    Err(L5xError::MissingAttribute {
        element: String::from_utf8_lossy(e.name().as_ref()).to_string(),
        attribute: name.to_string(),
    })
}

fn parse_tag_element(
    e: &quick_xml::events::BytesStart,
    state: &ParseState,
    current_program_name: &str,
    project: &mut Option<PlcProject>,
) -> Result<(), L5xError> {
    let name = get_attr(e, "Name")?;
    let dt_str = get_attr(e, "DataType").unwrap_or_default();
    let scope = match state {
        ParseState::ProgramTags => TagScope::Program {
            program_name: current_program_name.to_string(),
        },
        _ => TagScope::Controller,
    };
    let data_type = parse_l5x_data_type(&dt_str, e);
    let alias_for = get_attr(e, "AliasFor").ok();

    if let Some(ref mut proj) = project {
        proj.tag_database.add_tag(Tag {
            id: uuid::Uuid::new_v4().to_string(),
            name,
            data_type,
            scope,
            description: String::new(),
            initial_value: String::new(),
            alias_for,
            external_access: match get_attr(e, "ExternalAccess")
                .unwrap_or_default()
                .as_str()
            {
                "Read Only" => ExternalAccess::ReadOnly,
                "None" => ExternalAccess::None,
                _ => ExternalAccess::ReadWrite,
            },
        });
    }
    Ok(())
}

fn handle_text_content(
    text: &str,
    state: &ParseState,
    current_rung_comment: &mut String,
    project: &mut Option<PlcProject>,
    current_program_name: &str,
    current_routine_name: &str,
    current_rung_number: u32,
) -> Result<(), L5xError> {
    match state {
        ParseState::RungComment => {
            *current_rung_comment = text.to_string();
        }
        ParseState::RungText => {
            let expr_text = text.trim().trim_end_matches(';').trim();
            if !expr_text.is_empty() {
                let element = l5k::parse_rung_expression(expr_text)
                    .map_err(|e| L5xError::RungError(e.to_string()))?;

                if let Some(ref mut proj) = project {
                    if let Some(task) = proj.tasks.last_mut() {
                        if let Some(program) = task.programs.iter_mut()
                            .find(|p| p.name == current_program_name)
                        {
                            let routine = if let Some(r) = program.routines.iter_mut()
                                .find(|r| r.name == current_routine_name)
                            {
                                r
                            } else {
                                program.routines.push(Routine::new(current_routine_name));
                                program.routines.last_mut().unwrap()
                            };

                            let mut rung = Rung::new(current_rung_number, element);
                            if !current_rung_comment.is_empty() {
                                rung.comment = current_rung_comment.clone();
                            }
                            rung.editable = true;
                            routine.rungs.push(rung);
                        }
                    }
                }
            }
        }
        _ => {}
    }
    Ok(())
}

fn parse_l5x_data_type(dt_str: &str, e: &quick_xml::events::BytesStart) -> DataType {
    // Check for array dimension
    let dimension = get_attr(e, "Dimensions")
        .ok()
        .and_then(|s| {
            // Can be "10" or "10 5" for multi-dimensional
            let dims: Vec<u32> = s.split_whitespace()
                .filter_map(|d| d.parse().ok())
                .collect();
            if dims.is_empty() || dims.iter().all(|&d| d == 0) {
                None
            } else {
                Some(dims)
            }
        });

    if let Some(dims) = dimension {
        return DataType::Array {
            element_type_name: dt_str.to_string(),
            dimensions: dims,
        };
    }

    match dt_str.to_uppercase().as_str() {
        "BOOL" => DataType::Bool,
        "SINT" => DataType::Sint,
        "INT" => DataType::Int,
        "DINT" => DataType::Dint,
        "LINT" => DataType::Lint,
        "REAL" => DataType::Real,
        "STRING" => DataType::StringType,
        "TIMER" => DataType::Timer,
        "COUNTER" => DataType::Counter,
        other => DataType::Udt { name: other.to_string() },
    }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_L5X: &str = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<RSLogix5000Content SchemaRevision="1.0" SoftwareRevision="34.00"
                     TargetType="Controller" ContainsContext="true">
  <Controller Name="ConveyorCtrl" ProcessorType="1769-L33ER"
              MajorRev="34" MinorRev="11">
    <Tags>
      <Tag Name="Start_PB" TagType="Base" DataType="BOOL" Radix="Decimal"
           ExternalAccess="Read/Write">
        <Description><![CDATA[Start pushbutton]]></Description>
      </Tag>
      <Tag Name="Stop_PB" TagType="Base" DataType="BOOL" Radix="Decimal"
           ExternalAccess="Read/Write">
        <Description><![CDATA[Stop pushbutton]]></Description>
      </Tag>
      <Tag Name="Motor_Run" TagType="Base" DataType="BOOL" Radix="Decimal"
           ExternalAccess="Read/Write"/>
      <Tag Name="Line_Speed" TagType="Base" DataType="DINT" Radix="Decimal"
           ExternalAccess="Read/Write"/>
      <Tag Name="Delay_Timer" TagType="Base" DataType="TIMER"
           ExternalAccess="Read/Write"/>
    </Tags>
    <Programs>
      <Program Name="MainProgram" Type="Normal">
        <Routines>
          <Routine Name="MainRoutine" Type="RLL">
            <RLLContent>
              <Rung Number="0" Type="N">
                <Comment><![CDATA[Motor seal-in circuit]]></Comment>
                <Text><![CDATA[[XIC(Start_PB),XIC(Motor_Run)] OTL(Motor_Run) ;]]></Text>
              </Rung>
              <Rung Number="1" Type="N">
                <Comment><![CDATA[Motor stop circuit]]></Comment>
                <Text><![CDATA[XIO(Stop_PB) OTU(Motor_Run) ;]]></Text>
              </Rung>
              <Rung Number="2" Type="N">
                <Comment><![CDATA[Run delay timer]]></Comment>
                <Text><![CDATA[XIC(Motor_Run) TON(Delay_Timer,5000,0) ;]]></Text>
              </Rung>
            </RLLContent>
          </Routine>
        </Routines>
      </Program>
    </Programs>
    <Tasks>
      <Task Name="MainTask" Type="CONTINUOUS" Rate="10" Priority="10"
            Watchdog="500" DisableUpdateOutputs="false">
        <ScheduledPrograms>
          <ScheduledProgram Name="MainProgram"/>
        </ScheduledPrograms>
      </Task>
    </Tasks>
  </Controller>
</RSLogix5000Content>"#;

    #[test]
    fn parse_complete_l5x_file() {
        let project = parse_l5x(SAMPLE_L5X).unwrap();

        assert_eq!(project.name, "ConveyorCtrl");
        assert_eq!(project.controller.catalog_number, "1769-L33ER");
        assert_eq!(project.controller.family, ControllerFamily::CompactLogix);
    }

    #[test]
    fn parse_l5x_tags() {
        let project = parse_l5x(SAMPLE_L5X).unwrap();

        assert_eq!(project.tag_database.tags.len(), 5);

        let start = project.tag_database.find_by_name("Start_PB").unwrap();
        assert_eq!(start.data_type, DataType::Bool);

        let speed = project.tag_database.find_by_name("Line_Speed").unwrap();
        assert_eq!(speed.data_type, DataType::Dint);

        let timer = project.tag_database.find_by_name("Delay_Timer").unwrap();
        assert_eq!(timer.data_type, DataType::Timer);
    }

    #[test]
    fn parse_l5x_program_structure() {
        let project = parse_l5x(SAMPLE_L5X).unwrap();

        assert!(project.tasks.len() >= 1);
        let task = &project.tasks[0];
        assert_eq!(task.programs.len(), 1);

        let program = &task.programs[0];
        assert_eq!(program.name, "MainProgram");
    }

    #[test]
    fn parse_l5x_rungs() {
        let project = parse_l5x(SAMPLE_L5X).unwrap();

        let routine = project.find_routine("MainProgram", "MainRoutine");
        assert!(routine.is_some());
        let routine = routine.unwrap();
        assert_eq!(routine.rungs.len(), 3);

        // Rung 0: Seal-in with branch
        assert_eq!(routine.rungs[0].comment, "Motor seal-in circuit");
        match &routine.rungs[0].element {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[0] {
                    RungElement::Parallel { branches } => assert_eq!(branches.len(), 2),
                    _ => panic!("Expected parallel branch in rung 0"),
                }
            }
            _ => panic!("Expected series in rung 0"),
        }

        // Rung 1: Simple stop
        assert_eq!(routine.rungs[1].comment, "Motor stop circuit");

        // Rung 2: Timer
        assert_eq!(routine.rungs[2].comment, "Run delay timer");
        match &routine.rungs[2].element {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[1] {
                    RungElement::Instruction { instruction } => {
                        assert_eq!(instruction.instruction_type, InstructionType::Ton);
                    }
                    _ => panic!("Expected TON instruction in rung 2"),
                }
            }
            _ => panic!("Expected series in rung 2"),
        }
    }

    #[test]
    fn l5x_to_json_roundtrip() {
        let project = parse_l5x(SAMPLE_L5X).unwrap();
        let json = project.to_json().unwrap();
        let reloaded = PlcProject::from_json(&json).unwrap();

        assert_eq!(project.name, reloaded.name);
        assert_eq!(project.tag_database.tags.len(), reloaded.tag_database.tags.len());

        let orig_routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let reload_routine = reloaded.find_routine("MainProgram", "MainRoutine").unwrap();
        assert_eq!(orig_routine.rungs.len(), reload_routine.rungs.len());
    }

    #[test]
    fn parse_l5x_with_non_rll_routine_skipped() {
        // L5X with an ST routine that should be skipped
        let xml = r#"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<RSLogix5000Content SchemaRevision="1.0" SoftwareRevision="34.00"
                     TargetType="Controller">
  <Controller Name="TestCtrl" ProcessorType="1756-L85E">
    <Tags/>
    <Programs>
      <Program Name="MainProgram" Type="Normal">
        <Routines>
          <Routine Name="STRoutine" Type="ST">
            <STContent>
              <Line Number="0"><![CDATA[x := x + 1;]]></Line>
            </STContent>
          </Routine>
          <Routine Name="LadderRoutine" Type="RLL">
            <RLLContent>
              <Rung Number="0" Type="N">
                <Text><![CDATA[XIC(A) OTE(B) ;]]></Text>
              </Rung>
            </RLLContent>
          </Routine>
        </Routines>
      </Program>
    </Programs>
    <Tasks>
      <Task Name="MainTask" Type="CONTINUOUS" Rate="10" Priority="10"/>
    </Tasks>
  </Controller>
</RSLogix5000Content>"#;

        let project = parse_l5x(xml).unwrap();
        // ST routine is skipped, only ladder routine is parsed
        let routine = project.find_routine("MainProgram", "LadderRoutine");
        assert!(routine.is_some());
        assert_eq!(routine.unwrap().rungs.len(), 1);
    }
}
