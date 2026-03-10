//! Project model — the top-level container for an entire PLC project (.plcproj).

use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::ast::{Controller, ControllerFamily, Task};
use crate::tags::TagDatabase;

/// File format version for .plcproj files.
const PROJECT_FORMAT_VERSION: u32 = 1;

/// A complete PLC project — serialized to disk as .plcproj (JSON).
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct PlcProject {
    /// Format version (for migration support)
    pub format_version: u32,
    /// Unique project ID
    pub id: String,
    /// Project name
    pub name: String,
    /// Project description
    pub description: String,
    /// Controller definition
    pub controller: Controller,
    /// All tasks (contain programs, which contain routines)
    pub tasks: Vec<Task>,
    /// Tag database (controller-scope and program-scope tags)
    pub tag_database: TagDatabase,
    /// Path to original imported file, if any
    pub imported_from: Option<String>,
}

impl PlcProject {
    /// Create a new empty project with sensible defaults.
    pub fn new(name: &str, family: ControllerFamily) -> Self {
        Self {
            format_version: PROJECT_FORMAT_VERSION,
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            description: String::new(),
            controller: Controller::new(name, family),
            tasks: Vec::new(),
            tag_database: TagDatabase::new(),
            imported_from: None,
        }
    }

    /// Serialize to JSON string (for saving to .plcproj file).
    pub fn to_json(&self) -> Result<String, String> {
        serde_json::to_string_pretty(self).map_err(|e| e.to_string())
    }

    /// Deserialize from JSON string (for loading from .plcproj file).
    pub fn from_json(json: &str) -> Result<Self, String> {
        serde_json::from_str(json).map_err(|e| e.to_string())
    }

    pub fn add_task(&mut self, task: Task) {
        self.tasks.push(task);
    }

    /// Find a routine by program and routine name.
    pub fn find_routine(&self, program_name: &str, routine_name: &str) -> Option<&crate::ast::Routine> {
        for task in &self.tasks {
            for program in &task.programs {
                if program.name == program_name {
                    return program.find_routine(routine_name);
                }
            }
        }
        None
    }
}

// ─── UniFFI-exposed functions ───────────────────────────────────────────────

/// Create a new PLC project. Exposed to Swift via UniFFI.
#[uniffi::export]
pub fn create_project(name: String, family: ControllerFamily) -> PlcProject {
    PlcProject::new(&name, family)
}

/// Serialize a project to JSON. Exposed to Swift via UniFFI.
#[uniffi::export]
pub fn save_project_to_json(project: PlcProject) -> Result<String, String> {
    project.to_json()
}

/// Deserialize a project from JSON. Exposed to Swift via UniFFI.
#[uniffi::export]
pub fn load_project_from_json(json: String) -> Result<PlcProject, String> {
    PlcProject::from_json(&json)
}

// ─── Phase 1: Query functions for Swift UI ──────────────────────────────────

/// Get all program names in the project.
#[uniffi::export]
pub fn get_program_names(project: &PlcProject) -> Vec<String> {
    project.tasks.iter()
        .flat_map(|t| t.programs.iter().map(|p| p.name.clone()))
        .collect()
}

/// Get all routine names for a given program.
#[uniffi::export]
pub fn get_routine_names(project: &PlcProject, program_name: String) -> Vec<String> {
    for task in &project.tasks {
        for program in &task.programs {
            if program.name == program_name {
                return program.routines.iter().map(|r| r.name.clone()).collect();
            }
        }
    }
    vec![]
}

/// Get a routine's rungs as JSON (for display in the ladder viewer).
#[uniffi::export]
pub fn get_routine_rungs(project: &PlcProject, program_name: String, routine_name: String) -> Vec<Rung> {
    project.find_routine(&program_name, &routine_name)
        .map(|r| r.rungs.clone())
        .unwrap_or_default()
}

/// Get all controller-scope tags.
#[uniffi::export]
pub fn get_controller_tags(project: &PlcProject) -> Vec<crate::tags::Tag> {
    project.tag_database.tags.iter()
        .filter(|t| matches!(t.scope, crate::tags::TagScope::Controller))
        .cloned()
        .collect()
}

/// Get all program-scope tags for a specific program.
#[uniffi::export]
pub fn get_program_tags(project: &PlcProject, program_name: String) -> Vec<crate::tags::Tag> {
    project.tag_database.tags.iter()
        .filter(|t| matches!(&t.scope, crate::tags::TagScope::Program { program_name: pn } if pn == &program_name))
        .cloned()
        .collect()
}

/// Get project summary info for display.
#[derive(Debug, Clone, uniffi::Record)]
pub struct ProjectSummary {
    pub name: String,
    pub controller_family: String,
    pub catalog_number: String,
    pub task_count: u32,
    pub program_count: u32,
    pub routine_count: u32,
    pub rung_count: u32,
    pub tag_count: u32,
}

#[uniffi::export]
pub fn get_project_summary(project: &PlcProject) -> ProjectSummary {
    let mut program_count = 0u32;
    let mut routine_count = 0u32;
    let mut rung_count = 0u32;

    for task in &project.tasks {
        for program in &task.programs {
            program_count += 1;
            for routine in &program.routines {
                routine_count += 1;
                rung_count += routine.rungs.len() as u32;
            }
        }
    }

    ProjectSummary {
        name: project.name.clone(),
        controller_family: format!("{:?}", project.controller.family),
        catalog_number: project.controller.catalog_number.clone(),
        task_count: project.tasks.len() as u32,
        program_count,
        routine_count,
        rung_count,
        tag_count: project.tag_database.tags.len() as u32,
    }
}

/// Format a rung element as human-readable text (for the text-based rung display).
#[uniffi::export]
pub fn format_rung_element(element: &crate::ast::RungElement) -> String {
    format_element(element)
}

fn format_element(element: &crate::ast::RungElement) -> String {
    match element {
        crate::ast::RungElement::Instruction { instruction } => {
            let mnemonic = format_instruction_type(&instruction.instruction_type);
            let operands: Vec<String> = instruction.operands.iter()
                .map(format_operand)
                .collect();
            format!("{}({})", mnemonic, operands.join(","))
        }
        crate::ast::RungElement::Series { elements } => {
            elements.iter().map(format_element).collect::<Vec<_>>().join(" ")
        }
        crate::ast::RungElement::Parallel { branches } => {
            let paths: Vec<String> = branches.iter().map(format_element).collect();
            format!("[{}]", paths.join(","))
        }
    }
}

fn format_instruction_type(it: &crate::ast::InstructionType) -> &'static str {
    use crate::ast::InstructionType::*;
    match it {
        Xic => "XIC", Xio => "XIO", Ote => "OTE", Otl => "OTL", Otu => "OTU", Ons => "ONS",
        Ton => "TON", Tof => "TOF", Rto => "RTO",
        Ctu => "CTU", Ctd => "CTD", Res => "RES",
        Equ => "EQU", Neq => "NEQ", Les => "LES", Leq => "LEQ", Grt => "GRT", Geq => "GEQ",
        Add => "ADD", Sub => "SUB", Mul => "MUL", Div => "DIV", Mod => "MOD", Neg => "NEG",
        Mov => "MOV", Cop => "COP",
        Jmp => "JMP", Lbl => "LBL", Jsr => "JSR", Ret => "RET", Sbr => "SBR",
        Unknown { .. } => "???",
    }
}

fn format_operand(op: &crate::ast::Operand) -> String {
    match op {
        crate::ast::Operand::TagRef { name } => name.clone(),
        crate::ast::Operand::IntLiteral { value } => value.to_string(),
        crate::ast::Operand::RealLiteral { value } => format!("{:.1}", value),
    }
}

use crate::ast::{Rung, RungElement, Routine};

// ─── Phase 2: Mutation functions for editor ─────────────────────────────────

/// Insert a new empty rung at the given index in a routine.
/// Returns the updated project.
#[uniffi::export]
pub fn insert_rung(
    mut project: PlcProject,
    program_name: String,
    routine_name: String,
    at_index: u32,
    comment: String,
) -> PlcProject {
    if let Some(routine) = find_routine_mut(&mut project, &program_name, &routine_name) {
        let idx = (at_index as usize).min(routine.rungs.len());
        let rung = Rung::new(idx as u32, RungElement::Series { elements: vec![] });
        let rung = if comment.is_empty() { rung } else { rung.with_comment(&comment) };
        routine.rungs.insert(idx, rung);
        renumber_rungs(routine);
    }
    project
}

/// Delete a rung by index. Returns the updated project.
#[uniffi::export]
pub fn delete_rung(
    mut project: PlcProject,
    program_name: String,
    routine_name: String,
    rung_index: u32,
) -> PlcProject {
    if let Some(routine) = find_routine_mut(&mut project, &program_name, &routine_name) {
        let idx = rung_index as usize;
        if idx < routine.rungs.len() {
            routine.rungs.remove(idx);
            renumber_rungs(routine);
        }
    }
    project
}

/// Move a rung from one position to another. Returns the updated project.
#[uniffi::export]
pub fn move_rung(
    mut project: PlcProject,
    program_name: String,
    routine_name: String,
    from_index: u32,
    to_index: u32,
) -> PlcProject {
    if let Some(routine) = find_routine_mut(&mut project, &program_name, &routine_name) {
        let from = from_index as usize;
        let to = to_index as usize;
        if from < routine.rungs.len() && to < routine.rungs.len() && from != to {
            let rung = routine.rungs.remove(from);
            let insert_at = to.min(routine.rungs.len());
            routine.rungs.insert(insert_at, rung);
            renumber_rungs(routine);
        }
    }
    project
}

/// Update a rung's comment. Returns the updated project.
#[uniffi::export]
pub fn update_rung_comment(
    mut project: PlcProject,
    program_name: String,
    routine_name: String,
    rung_index: u32,
    comment: String,
) -> PlcProject {
    if let Some(routine) = find_routine_mut(&mut project, &program_name, &routine_name) {
        let idx = rung_index as usize;
        if idx < routine.rungs.len() {
            routine.rungs[idx].comment = comment;
        }
    }
    project
}

/// Replace the entire element tree for a rung. Used after drag-drop or structural edits.
#[uniffi::export]
pub fn update_rung_element(
    mut project: PlcProject,
    program_name: String,
    routine_name: String,
    rung_index: u32,
    new_element: RungElement,
) -> PlcProject {
    if let Some(routine) = find_routine_mut(&mut project, &program_name, &routine_name) {
        let idx = rung_index as usize;
        if idx < routine.rungs.len() {
            routine.rungs[idx].element = new_element;
        }
    }
    project
}

/// Add a new tag to the project. Returns the updated project.
#[uniffi::export]
pub fn add_tag(
    mut project: PlcProject,
    name: String,
    data_type: crate::tags::DataType,
    scope: crate::tags::TagScope,
    description: String,
) -> PlcProject {
    let tag = crate::tags::Tag {
        id: uuid::Uuid::new_v4().to_string(),
        name,
        data_type,
        scope,
        description,
        initial_value: String::new(),
        alias_for: None,
        external_access: crate::tags::ExternalAccess::ReadWrite,
    };
    project.tag_database.add_tag(tag);
    project
}

/// Delete a tag by name. Returns the updated project.
#[uniffi::export]
pub fn delete_tag(mut project: PlcProject, tag_name: String) -> PlcProject {
    project.tag_database.tags.retain(|t| t.name != tag_name);
    project
}

/// Add a new routine to a program. Returns the updated project.
#[uniffi::export]
pub fn add_routine(
    mut project: PlcProject,
    program_name: String,
    routine_name: String,
) -> PlcProject {
    for task in &mut project.tasks {
        for program in &mut task.programs {
            if program.name == program_name {
                program.routines.push(Routine::new(&routine_name));
                return project;
            }
        }
    }
    project
}

/// Duplicate a rung (insert copy below). Returns the updated project.
#[uniffi::export]
pub fn duplicate_rung(
    mut project: PlcProject,
    program_name: String,
    routine_name: String,
    rung_index: u32,
) -> PlcProject {
    if let Some(routine) = find_routine_mut(&mut project, &program_name, &routine_name) {
        let idx = rung_index as usize;
        if idx < routine.rungs.len() {
            let mut new_rung = routine.rungs[idx].clone();
            new_rung.id = uuid::Uuid::new_v4().to_string();
            routine.rungs.insert(idx + 1, new_rung);
            renumber_rungs(routine);
        }
    }
    project
}

// ─── Internal helpers ───────────────────────────────────────────────────────

fn find_routine_mut<'a>(
    project: &'a mut PlcProject,
    program_name: &str,
    routine_name: &str,
) -> Option<&'a mut Routine> {
    for task in &mut project.tasks {
        for program in &mut task.programs {
            if program.name == program_name {
                return program.routines.iter_mut().find(|r| r.name == routine_name);
            }
        }
    }
    None
}

fn renumber_rungs(routine: &mut Routine) {
    for (i, rung) in routine.rungs.iter_mut().enumerate() {
        rung.number = i as u32;
    }
}

// ─── Phase 1: Task/Program query functions ──────────────────────────────────

/// Get all task names in the project.
#[uniffi::export]
pub fn get_task_names(project: &PlcProject) -> Vec<String> {
    project.tasks.iter().map(|t| t.name.clone()).collect()
}

/// Get the programs scheduled in a specific task.
#[uniffi::export]
pub fn get_task_program_names(project: &PlcProject, task_name: String) -> Vec<String> {
    for task in &project.tasks {
        if task.name == task_name {
            return task.programs.iter().map(|p| p.name.clone()).collect();
        }
    }
    vec![]
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::ast::*;
    use crate::tags::*;

    #[test]
    fn full_project_roundtrip() {
        // Build a realistic project
        let mut project = PlcProject::new("ConveyorLine1", ControllerFamily::CompactLogix);
        project.controller.catalog_number = "1769-L33ER".to_string();
        project.controller.firmware_version = "34.011".to_string();
        project.description = "Main conveyor line control".to_string();

        // Add tags
        project.tag_database.add_tag(Tag::new_bool("Start_PB", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Stop_PB", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Motor_Run", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_dint("Line_Speed", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_timer("Delay_Timer", TagScope::Program {
            program_name: "MainProgram".to_string(),
        }));

        // Build a task with a program
        let mut task = Task::new_continuous("MainTask");
        let mut program = Program::new("MainProgram");

        // Add rungs to the main routine
        if let Some(routine) = program.main_routine_mut() {
            // Seal-in
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::parallel(vec![
                        RungElement::instruction(Instruction::contact(true, "Start_PB")),
                        RungElement::instruction(Instruction::contact(true, "Motor_Run")),
                    ]),
                    RungElement::instruction(Instruction::coil(InstructionType::Otl, "Motor_Run")),
                ]),
                "Motor seal-in circuit",
            );

            // Stop
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(false, "Stop_PB")),
                    RungElement::instruction(Instruction::coil(InstructionType::Otu, "Motor_Run")),
                ]),
                "Motor stop circuit",
            );
        }

        task.add_program(program);
        project.add_task(task);

        // Serialize
        let json = project.to_json().expect("Serialization failed");
        assert!(json.contains("ConveyorLine1"));
        assert!(json.contains("Motor_Run"));
        assert!(json.contains("seal-in"));

        // Deserialize
        let loaded = PlcProject::from_json(&json).expect("Deserialization failed");
        assert_eq!(loaded.name, "ConveyorLine1");
        assert_eq!(loaded.controller.catalog_number, "1769-L33ER");
        assert_eq!(loaded.tag_database.tags.len(), 5);
        assert_eq!(loaded.tasks.len(), 1);
        assert_eq!(loaded.tasks[0].programs[0].routines[0].rungs.len(), 2);

        // Verify routine lookup works
        let routine = loaded.find_routine("MainProgram", "MainRoutine");
        assert!(routine.is_some());
        assert_eq!(routine.unwrap().rungs.len(), 2);
    }

    #[test]
    fn uniffi_exported_functions() {
        let project = create_project("TestProject".to_string(), ControllerFamily::ControlLogix);
        assert_eq!(project.name, "TestProject");

        let json = save_project_to_json(project).unwrap();
        let loaded = load_project_from_json(json).unwrap();
        assert_eq!(loaded.name, "TestProject");
    }

    #[test]
    fn generate_demo_project_file() {
        // Build a realistic demo project matching the Swift DemoProject
        let mut project = PlcProject::new("ConveyorLine1", ControllerFamily::CompactLogix);
        project.controller.catalog_number = "1769-L33ER".to_string();
        project.controller.firmware_version = "34.011".to_string();
        project.description = "Conveyor Line 1 — Main production line control".to_string();

        // Controller-scope tags
        project.tag_database.add_tag(Tag::new_bool("Start_PB", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Stop_PB", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Motor_Run", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("E_Stop", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_dint("Line_Speed", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_dint("Speed_Setpoint", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_timer("Run_Delay", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_counter("Fault_Count", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Sensor_1", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Sensor_2", TagScope::Controller));

        // Program-scope tags
        project.tag_database.add_tag(Tag::new_timer("Cycle_Timer", TagScope::Program {
            program_name: "MainProgram".to_string(),
        }));
        project.tag_database.add_tag(Tag::new_counter("Part_Count", TagScope::Program {
            program_name: "MainProgram".to_string(),
        }));

        // Add descriptions
        for tag in &mut project.tag_database.tags {
            tag.description = match tag.name.as_str() {
                "Start_PB" => "Start pushbutton".to_string(),
                "Stop_PB" => "Stop pushbutton (NC)".to_string(),
                "Motor_Run" => "Motor running status".to_string(),
                "E_Stop" => "Emergency stop (NC)".to_string(),
                "Line_Speed" => "Conveyor line speed (RPM)".to_string(),
                "Speed_Setpoint" => "Speed setpoint from HMI".to_string(),
                "Run_Delay" => "Motor start delay timer".to_string(),
                "Fault_Count" => "Accumulated fault count".to_string(),
                "Sensor_1" => "Proximity sensor - entry".to_string(),
                "Sensor_2" => "Proximity sensor - exit".to_string(),
                "Cycle_Timer" => "Production cycle timer".to_string(),
                "Part_Count" => "Parts produced counter".to_string(),
                _ => String::new(),
            };
        }

        // Build task/program/routine
        let mut task = Task::new_continuous("MainTask");
        let mut program = Program::new("MainProgram");

        // Add a fault handler routine (empty)
        program.routines.push(Routine::new("FaultHandler"));

        if let Some(routine) = program.main_routine_mut() {
            // Rung 0: Seal-in with E-Stop
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::parallel(vec![
                        RungElement::instruction(Instruction::contact(true, "Start_PB")),
                        RungElement::instruction(Instruction::contact(true, "Motor_Run")),
                    ]),
                    RungElement::instruction(Instruction::contact(false, "E_Stop")),
                    RungElement::instruction(Instruction::coil(InstructionType::Otl, "Motor_Run")),
                ]),
                "Motor seal-in circuit with E-Stop interlock",
            );

            // Rung 1: Stop
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(false, "Stop_PB")),
                    RungElement::instruction(Instruction::coil(InstructionType::Otu, "Motor_Run")),
                ]),
                "Motor stop circuit",
            );

            // Rung 2: Timer
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(true, "Motor_Run")),
                    RungElement::instruction(Instruction::new(
                        InstructionType::Ton,
                        vec![
                            Operand::TagRef { name: "Run_Delay".to_string() },
                            Operand::IntLiteral { value: 5000 },
                            Operand::IntLiteral { value: 0 },
                        ],
                    )),
                ]),
                "Motor run delay timer (5 seconds)",
            );

            // Rung 3: Speed move after delay
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(true, "Run_Delay.DN")),
                    RungElement::instruction(Instruction::new(
                        InstructionType::Mov,
                        vec![
                            Operand::TagRef { name: "Speed_Setpoint".to_string() },
                            Operand::TagRef { name: "Line_Speed".to_string() },
                        ],
                    )),
                ]),
                "After delay, apply speed setpoint",
            );

            // Rung 4: Part counting
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(true, "Sensor_2")),
                    RungElement::instruction(Instruction::new(
                        InstructionType::Ctu,
                        vec![
                            Operand::TagRef { name: "Part_Count".to_string() },
                            Operand::IntLiteral { value: 99999 },
                            Operand::IntLiteral { value: 0 },
                        ],
                    )),
                ]),
                "Count parts at exit sensor",
            );

            // Rung 5: Fault detection with parallel
            routine.add_commented_rung(
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(true, "Motor_Run")),
                    RungElement::parallel(vec![
                        RungElement::instruction(Instruction::contact(false, "Sensor_1")),
                        RungElement::instruction(Instruction::contact(false, "Sensor_2")),
                    ]),
                    RungElement::instruction(Instruction::new(
                        InstructionType::Ctu,
                        vec![
                            Operand::TagRef { name: "Fault_Count".to_string() },
                            Operand::IntLiteral { value: 100 },
                            Operand::IntLiteral { value: 0 },
                        ],
                    )),
                ]),
                "Fault detection: motor running but no sensor activity",
            );
        }

        task.add_program(program);
        project.add_task(task);

        let json = project.to_json().expect("Serialization failed");

        // Write to samples directory
        let samples_dir = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .parent().unwrap()
            .parent().unwrap()
            .join("samples");
        std::fs::create_dir_all(&samples_dir).ok();
        let path = samples_dir.join("ConveyorLine1.plcproj");
        std::fs::write(&path, &json).expect("Failed to write sample file");

        // Verify it round-trips
        let loaded = PlcProject::from_json(&json).expect("Failed to parse");
        assert_eq!(loaded.name, "ConveyorLine1");
        assert_eq!(loaded.tag_database.tags.len(), 12);
        assert_eq!(loaded.tasks[0].programs[0].routines[0].rungs.len(), 6);
    }

    #[test]
    fn phase1_query_functions() {
        let project = create_project("Test".to_string(), ControllerFamily::CompactLogix);
        assert!(get_task_names(&project).is_empty());
        assert!(get_program_names(&project).is_empty());

        // Build a project with data
        let mut project = PlcProject::new("Test", ControllerFamily::CompactLogix);
        let mut task = Task::new_continuous("MainTask");
        task.add_program(Program::new("MainProgram"));
        project.add_task(task);

        assert_eq!(get_task_names(&project), vec!["MainTask"]);
        assert_eq!(get_program_names(&project), vec!["MainProgram"]);
        assert_eq!(get_task_program_names(&project, "MainTask".to_string()), vec!["MainProgram"]);
        assert_eq!(get_routine_names(&project, "MainProgram".to_string()), vec!["MainRoutine"]);

        let summary = get_project_summary(&project);
        assert_eq!(summary.task_count, 1);
        assert_eq!(summary.program_count, 1);
        assert_eq!(summary.routine_count, 1);
    }
}
