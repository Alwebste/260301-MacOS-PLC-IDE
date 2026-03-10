//! Basic validation — checks rung structure and tag references.

use crate::ast::*;
use crate::project::PlcProject;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum Severity {
    Error,
    Warning,
    Info,
}

#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct ValidationIssue {
    pub severity: Severity,
    pub message: String,
    /// Which rung (if applicable)
    pub rung_number: Option<u32>,
    /// Which routine
    pub routine_name: String,
    /// Which program
    pub program_name: String,
}

/// Validate an entire project, returning all issues found.
#[uniffi::export]
pub fn validate_project(project: PlcProject) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();

    for task in &project.tasks {
        for program in &task.programs {
            for routine in &program.routines {
                for rung in &routine.rungs {
                    validate_rung_element(
                        &rung.element,
                        &project,
                        &program.name,
                        &routine.name,
                        rung.number,
                        &mut issues,
                    );
                }
            }
        }
    }

    issues
}

fn validate_rung_element(
    element: &RungElement,
    project: &PlcProject,
    program_name: &str,
    routine_name: &str,
    rung_number: u32,
    issues: &mut Vec<ValidationIssue>,
) {
    match element {
        RungElement::Instruction { instruction } => {
            // Check that all tag references exist
            for operand in &instruction.operands {
                if let Operand::TagRef { name } = operand {
                    // Strip array indexing and bit addressing for lookup
                    let base_name = name.split('[').next().unwrap_or(name);
                    let base_name = base_name.split('.').next().unwrap_or(base_name);

                    if project.tag_database.find_by_name(base_name).is_none() {
                        issues.push(ValidationIssue {
                            severity: Severity::Error,
                            message: format!("Tag '{}' not found in tag database", name),
                            rung_number: Some(rung_number),
                            routine_name: routine_name.to_string(),
                            program_name: program_name.to_string(),
                        });
                    }
                }
            }

            // Check operand count for known instructions
            let expected = expected_operand_count(&instruction.instruction_type);
            if let Some(count) = expected {
                if instruction.operands.len() != count {
                    issues.push(ValidationIssue {
                        severity: Severity::Error,
                        message: format!(
                            "{:?} expects {} operand(s), got {}",
                            instruction.instruction_type, count, instruction.operands.len()
                        ),
                        rung_number: Some(rung_number),
                        routine_name: routine_name.to_string(),
                        program_name: program_name.to_string(),
                    });
                }
            }
        }
        RungElement::Series { elements } => {
            if elements.is_empty() {
                issues.push(ValidationIssue {
                    severity: Severity::Warning,
                    message: "Empty series (no instructions)".to_string(),
                    rung_number: Some(rung_number),
                    routine_name: routine_name.to_string(),
                    program_name: program_name.to_string(),
                });
            }
            for el in elements {
                validate_rung_element(el, project, program_name, routine_name, rung_number, issues);
            }
        }
        RungElement::Parallel { branches } => {
            if branches.len() < 2 {
                issues.push(ValidationIssue {
                    severity: Severity::Warning,
                    message: "Parallel branch with fewer than 2 paths".to_string(),
                    rung_number: Some(rung_number),
                    routine_name: routine_name.to_string(),
                    program_name: program_name.to_string(),
                });
            }
            for branch in branches {
                validate_rung_element(branch, project, program_name, routine_name, rung_number, issues);
            }
        }
    }
}

fn expected_operand_count(instruction_type: &InstructionType) -> Option<usize> {
    match instruction_type {
        // Bit: 1 operand (tag)
        InstructionType::Xic
        | InstructionType::Xio
        | InstructionType::Ote
        | InstructionType::Otl
        | InstructionType::Otu
        | InstructionType::Ons
        | InstructionType::Res => Some(1),

        // Timer/Counter: 3 operands (tag, preset, accum)
        InstructionType::Ton
        | InstructionType::Tof
        | InstructionType::Rto
        | InstructionType::Ctu
        | InstructionType::Ctd => Some(3),

        // Compare: 2 operands (source_a, source_b)
        InstructionType::Equ
        | InstructionType::Neq
        | InstructionType::Les
        | InstructionType::Leq
        | InstructionType::Grt
        | InstructionType::Geq => Some(2),

        // Math: 3 operands (source_a, source_b, dest)
        InstructionType::Add
        | InstructionType::Sub
        | InstructionType::Mul
        | InstructionType::Div
        | InstructionType::Mod => Some(3),

        // Neg/Mov: 2 operands (source, dest)
        InstructionType::Neg | InstructionType::Mov => Some(2),

        // Cop: 3 operands (source, dest, length)
        InstructionType::Cop => Some(3),

        // Program control: variable, skip validation
        InstructionType::Jmp
        | InstructionType::Lbl
        | InstructionType::Jsr
        | InstructionType::Ret
        | InstructionType::Sbr => None,

        // Unknown: skip
        InstructionType::Unknown { .. } => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tags::*;

    #[test]
    fn validates_missing_tags() {
        let mut project = PlcProject::new("Test", ControllerFamily::CompactLogix);
        project.tag_database.add_tag(Tag::new_bool("Existing_Tag", TagScope::Controller));

        let mut task = Task::new_continuous("MainTask");
        let mut program = Program::new("MainProgram");

        if let Some(routine) = program.main_routine_mut() {
            // Reference a tag that exists
            routine.add_rung(RungElement::series(vec![
                RungElement::instruction(Instruction::contact(true, "Existing_Tag")),
                RungElement::instruction(Instruction::coil(InstructionType::Ote, "Missing_Tag")),
            ]));
        }

        task.add_program(program);
        project.add_task(task);

        let issues = validate_project(project);
        // Should find one error for Missing_Tag
        let errors: Vec<_> = issues.iter().filter(|i| i.severity == Severity::Error).collect();
        assert_eq!(errors.len(), 1);
        assert!(errors[0].message.contains("Missing_Tag"));
    }

    #[test]
    fn validates_operand_count() {
        let mut project = PlcProject::new("Test", ControllerFamily::CompactLogix);
        project.tag_database.add_tag(Tag::new_bool("A", TagScope::Controller));

        let mut task = Task::new_continuous("MainTask");
        let mut program = Program::new("MainProgram");

        if let Some(routine) = program.main_routine_mut() {
            // XIC with wrong number of operands (should be 1)
            routine.add_rung(RungElement::instruction(Instruction::new(
                InstructionType::Xic,
                vec![
                    Operand::TagRef { name: "A".to_string() },
                    Operand::TagRef { name: "A".to_string() },
                ],
            )));
        }

        task.add_program(program);
        project.add_task(task);

        let issues = validate_project(project);
        let errors: Vec<_> = issues.iter().filter(|i| i.severity == Severity::Error).collect();
        assert!(errors.iter().any(|e| e.message.contains("expects 1 operand")));
    }
}
