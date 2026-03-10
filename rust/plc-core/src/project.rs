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
}
