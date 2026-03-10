//! Ladder Logic AST — the core data model for representing AB ladder programs.
//!
//! Design decisions:
//! - Tree-based model: Rung contains a top-level Element, which can be a single
//!   instruction, a series chain, or a parallel branch. This maps cleanly to both
//!   L5K text syntax and visual rendering.
//! - Instructions carry typed operands referencing tags by name (resolved at validation time).
//! - Branch nesting is recursive — a parallel branch can contain series chains,
//!   which can contain nested parallel branches. This matches real AB behavior.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

// ─── Instructions ───────────────────────────────────────────────────────────

/// An instruction operand — a reference to a tag or a literal value.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum Operand {
    /// Reference to a tag by name (e.g., "Motor_Start", "MyArray[5]", "MyDINT.2")
    TagRef { name: String },
    /// Integer literal (used in some compare/math instructions)
    IntLiteral { value: i64 },
    /// Float literal
    RealLiteral { value: f64 },
}

/// The type of a ladder instruction.
///
/// Each variant maps to an AB instruction mnemonic.
/// Operand count and types are validated separately.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum InstructionType {
    // ── Bit ──
    /// Examine If Closed (normally open contact)
    Xic,
    /// Examine If Open (normally closed contact)
    Xio,
    /// Output Energize
    Ote,
    /// Output Latch
    Otl,
    /// Output Unlatch
    Otu,
    /// One-Shot Rising
    Ons,

    // ── Timer ──
    /// Timer On Delay — operands: timer_tag, preset, accum
    Ton,
    /// Timer Off Delay
    Tof,
    /// Retentive Timer On
    Rto,

    // ── Counter ──
    /// Count Up — operands: counter_tag, preset, accum
    Ctu,
    /// Count Down
    Ctd,
    /// Reset (timer or counter)
    Res,

    // ── Compare ──
    /// Equal — operands: source_a, source_b
    Equ,
    /// Not Equal
    Neq,
    /// Less Than
    Les,
    /// Less Than or Equal
    Leq,
    /// Greater Than
    Grt,
    /// Greater Than or Equal
    Geq,

    // ── Math ──
    /// Add — operands: source_a, source_b, dest
    Add,
    /// Subtract
    Sub,
    /// Multiply
    Mul,
    /// Divide
    Div,
    /// Modulo
    Mod,
    /// Negate — operands: source, dest
    Neg,

    // ── Move ──
    /// Move — operands: source, dest
    Mov,
    /// Copy — operands: source, dest, length
    Cop,

    // ── Program Control ──
    /// Jump to Label
    Jmp,
    /// Label
    Lbl,
    /// Jump to Subroutine — operands: routine_name, input params...
    Jsr,
    /// Return from Subroutine
    Ret,
    /// Subroutine entry
    Sbr,

    /// Unknown/unsupported instruction (preserved for round-tripping)
    Unknown { mnemonic: String },
}

/// A single ladder instruction with its operands.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Instruction {
    pub id: String,
    pub instruction_type: InstructionType,
    pub operands: Vec<Operand>,
    /// Optional comment on this instruction
    pub comment: String,
}

impl Instruction {
    pub fn new(instruction_type: InstructionType, operands: Vec<Operand>) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            instruction_type,
            operands,
            comment: String::new(),
        }
    }

    /// Create a simple contact instruction (XIC/XIO) with one tag operand.
    pub fn contact(xic: bool, tag_name: &str) -> Self {
        Self::new(
            if xic { InstructionType::Xic } else { InstructionType::Xio },
            vec![Operand::TagRef { name: tag_name.to_string() }],
        )
    }

    /// Create a simple coil instruction (OTE/OTL/OTU) with one tag operand.
    pub fn coil(instruction_type: InstructionType, tag_name: &str) -> Self {
        Self::new(
            instruction_type,
            vec![Operand::TagRef { name: tag_name.to_string() }],
        )
    }
}

// ─── Rung Elements (tree structure for branches) ────────────────────────────

/// A rung element — the building block for ladder logic structure.
///
/// This recursive enum models how AB ladder logic works:
/// - A rung is a series chain of elements from left rail to right rail
/// - Elements can be single instructions, series chains, or parallel branches
/// - Parallel branches contain multiple paths, each of which is a series chain
///
/// Example: XIC(A) --+-- XIC(B) --+-- OTE(Y)
///                    |            |
///                    +-- XIC(C) --+
///
/// Represented as:
///   Series([
///     Instruction(XIC A),
///     Parallel([
///       Series([Instruction(XIC B)]),
///       Series([Instruction(XIC C)]),
///     ]),
///     Instruction(OTE Y),
///   ])
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Enum)]
pub enum RungElement {
    /// A single instruction
    Instruction { instruction: Instruction },
    /// Series chain — elements wired left-to-right
    Series { elements: Vec<RungElement> },
    /// Parallel branch — multiple paths, any one can pass power
    Parallel { branches: Vec<RungElement> },
}

impl RungElement {
    pub fn instruction(inst: Instruction) -> Self {
        RungElement::Instruction { instruction: inst }
    }

    pub fn series(elements: Vec<RungElement>) -> Self {
        RungElement::Series { elements }
    }

    pub fn parallel(branches: Vec<RungElement>) -> Self {
        RungElement::Parallel { branches }
    }
}

// ─── Rung ───────────────────────────────────────────────────────────────────

/// A single rung in a ladder routine.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Rung {
    pub id: String,
    /// Rung number (display order, 0-based)
    pub number: u32,
    /// The logic content of this rung
    pub element: RungElement,
    /// Rung comment (displayed above the rung in the editor)
    pub comment: String,
    /// Whether this rung is editable (false = imported, read-only)
    pub editable: bool,
}

impl Rung {
    pub fn new(number: u32, element: RungElement) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            number,
            element,
            comment: String::new(),
            editable: true,
        }
    }

    pub fn with_comment(mut self, comment: &str) -> Self {
        self.comment = comment.to_string();
        self
    }
}

// ─── Routine / Program / Task ───────────────────────────────────────────────

/// A ladder routine — a sequence of rungs.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Routine {
    pub id: String,
    pub name: String,
    pub description: String,
    pub rungs: Vec<Rung>,
}

impl Routine {
    pub fn new(name: &str) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            description: String::new(),
            rungs: Vec::new(),
        }
    }

    pub fn add_rung(&mut self, element: RungElement) -> &Rung {
        let number = self.rungs.len() as u32;
        self.rungs.push(Rung::new(number, element));
        self.rungs.last().unwrap()
    }

    pub fn add_commented_rung(&mut self, element: RungElement, comment: &str) -> &Rung {
        let number = self.rungs.len() as u32;
        self.rungs.push(Rung::new(number, element).with_comment(comment));
        self.rungs.last().unwrap()
    }
}

/// A program — contains routines and program-scoped tags.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Program {
    pub id: String,
    pub name: String,
    pub description: String,
    /// The main routine name (executed when program runs)
    pub main_routine_name: String,
    /// The fault routine name (executed on program fault)
    pub fault_routine_name: String,
    pub routines: Vec<Routine>,
}

impl Program {
    pub fn new(name: &str) -> Self {
        let mut program = Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            description: String::new(),
            main_routine_name: "MainRoutine".to_string(),
            fault_routine_name: String::new(),
            routines: Vec::new(),
        };
        // Every program gets a default main routine
        program.routines.push(Routine::new("MainRoutine"));
        program
    }

    pub fn main_routine_mut(&mut self) -> Option<&mut Routine> {
        let name = self.main_routine_name.clone();
        self.routines.iter_mut().find(|r| r.name == name)
    }

    pub fn find_routine(&self, name: &str) -> Option<&Routine> {
        self.routines.iter().find(|r| r.name == name)
    }
}

/// Task type — maps to AB task types.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum TaskType {
    /// Runs continuously
    Continuous,
    /// Runs at a fixed period (milliseconds)
    Periodic { period_ms: u32 },
    /// Runs on an event trigger
    Event { trigger: String },
}

/// A task — the top-level execution unit, contains programs.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Task {
    pub id: String,
    pub name: String,
    pub description: String,
    pub task_type: TaskType,
    pub priority: u32,
    pub programs: Vec<Program>,
}

impl Task {
    pub fn new_continuous(name: &str) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            description: String::new(),
            task_type: TaskType::Continuous,
            priority: 10,
            programs: Vec::new(),
        }
    }

    pub fn new_periodic(name: &str, period_ms: u32) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            description: String::new(),
            task_type: TaskType::Periodic { period_ms },
            priority: 10,
            programs: Vec::new(),
        }
    }

    pub fn add_program(&mut self, program: Program) {
        self.programs.push(program);
    }
}

// ─── Controller ─────────────────────────────────────────────────────────────

/// Controller family.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum ControllerFamily {
    ControlLogix,
    CompactLogix,
}

/// Top-level controller definition.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Controller {
    pub name: String,
    pub family: ControllerFamily,
    pub catalog_number: String,
    pub firmware_version: String,
    pub description: String,
}

impl Controller {
    pub fn new(name: &str, family: ControllerFamily) -> Self {
        Self {
            name: name.to_string(),
            family,
            catalog_number: String::new(),
            firmware_version: String::new(),
            description: String::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Build a realistic 5-rung routine to validate the AST can represent real AB logic.
    ///
    /// Rung 0: Simple seal-in circuit
    ///   XIC(Start_PB) --+-- OTL(Motor_Run)
    ///                    |
    ///   XIC(Motor_Run) --+
    ///
    /// Rung 1: Stop circuit
    ///   XIO(Stop_PB) --- OTU(Motor_Run)
    ///
    /// Rung 2: Timer - motor run delay
    ///   XIC(Motor_Run) --- TON(Run_Delay, 5000, 0)
    ///
    /// Rung 3: Counter - count start presses
    ///   XIC(Start_PB) --- CTU(Start_Count, 100, 0)
    ///
    /// Rung 4: Math - calculate speed
    ///   XIC(Motor_Run) --- MUL(Base_Speed, Speed_Factor, Actual_Speed)
    #[test]
    fn build_realistic_routine() {
        let mut routine = Routine::new("MainRoutine");

        // Rung 0: Seal-in (parallel branch for start OR running)
        let seal_in = RungElement::series(vec![
            RungElement::parallel(vec![
                RungElement::instruction(Instruction::contact(true, "Start_PB")),
                RungElement::instruction(Instruction::contact(true, "Motor_Run")),
            ]),
            RungElement::instruction(Instruction::coil(InstructionType::Otl, "Motor_Run")),
        ]);
        routine.add_commented_rung(seal_in, "Motor seal-in circuit");

        // Rung 1: Stop
        let stop = RungElement::series(vec![
            RungElement::instruction(Instruction::contact(false, "Stop_PB")),
            RungElement::instruction(Instruction::coil(InstructionType::Otu, "Motor_Run")),
        ]);
        routine.add_commented_rung(stop, "Motor stop circuit");

        // Rung 2: Timer
        let timer_rung = RungElement::series(vec![
            RungElement::instruction(Instruction::contact(true, "Motor_Run")),
            RungElement::instruction(Instruction::new(
                InstructionType::Ton,
                vec![
                    Operand::TagRef { name: "Run_Delay".to_string() },
                    Operand::IntLiteral { value: 5000 },
                    Operand::IntLiteral { value: 0 },
                ],
            )),
        ]);
        routine.add_commented_rung(timer_rung, "Motor run delay timer (5 seconds)");

        // Rung 3: Counter
        let counter_rung = RungElement::series(vec![
            RungElement::instruction(Instruction::contact(true, "Start_PB")),
            RungElement::instruction(Instruction::new(
                InstructionType::Ctu,
                vec![
                    Operand::TagRef { name: "Start_Count".to_string() },
                    Operand::IntLiteral { value: 100 },
                    Operand::IntLiteral { value: 0 },
                ],
            )),
        ]);
        routine.add_commented_rung(counter_rung, "Count start button presses");

        // Rung 4: Math
        let math_rung = RungElement::series(vec![
            RungElement::instruction(Instruction::contact(true, "Motor_Run")),
            RungElement::instruction(Instruction::new(
                InstructionType::Mul,
                vec![
                    Operand::TagRef { name: "Base_Speed".to_string() },
                    Operand::TagRef { name: "Speed_Factor".to_string() },
                    Operand::TagRef { name: "Actual_Speed".to_string() },
                ],
            )),
        ]);
        routine.add_commented_rung(math_rung, "Calculate actual motor speed");

        assert_eq!(routine.rungs.len(), 5);
        assert_eq!(routine.rungs[0].comment, "Motor seal-in circuit");

        // Verify the seal-in branch structure
        match &routine.rungs[0].element {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[0] {
                    RungElement::Parallel { branches } => assert_eq!(branches.len(), 2),
                    _ => panic!("Expected parallel branch"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn ast_serialization_roundtrip() {
        let mut routine = Routine::new("TestRoutine");

        // Build a rung with nested branches
        let complex_rung = RungElement::series(vec![
            RungElement::parallel(vec![
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(true, "A")),
                    RungElement::instruction(Instruction::contact(true, "B")),
                ]),
                RungElement::instruction(Instruction::contact(true, "C")),
            ]),
            RungElement::instruction(Instruction::coil(InstructionType::Ote, "Y")),
        ]);
        routine.add_rung(complex_rung);

        let json = serde_json::to_string_pretty(&routine).unwrap();
        let deserialized: Routine = serde_json::from_str(&json).unwrap();

        assert_eq!(routine.rungs.len(), deserialized.rungs.len());
        assert_eq!(routine.name, deserialized.name);

        // Verify nested structure survived
        match &deserialized.rungs[0].element {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[0] {
                    RungElement::Parallel { branches } => {
                        assert_eq!(branches.len(), 2);
                        // First branch should be a series of two instructions
                        match &branches[0] {
                            RungElement::Series { elements } => assert_eq!(elements.len(), 2),
                            _ => panic!("Expected series in first branch"),
                        }
                    }
                    _ => panic!("Expected parallel"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn nested_branch_depth() {
        // Test deeply nested branches — real AB projects can have 3-4 levels
        let deep = RungElement::series(vec![
            RungElement::instruction(Instruction::contact(true, "A")),
            RungElement::parallel(vec![
                RungElement::series(vec![
                    RungElement::instruction(Instruction::contact(true, "B")),
                    RungElement::parallel(vec![
                        RungElement::instruction(Instruction::contact(true, "C")),
                        RungElement::instruction(Instruction::contact(true, "D")),
                    ]),
                ]),
                RungElement::instruction(Instruction::contact(true, "E")),
            ]),
            RungElement::instruction(Instruction::coil(InstructionType::Ote, "Y")),
        ]);

        let json = serde_json::to_string(&deep).unwrap();
        let back: RungElement = serde_json::from_str(&json).unwrap();
        // If this doesn't panic, we handle nesting fine
        match &back {
            RungElement::Series { elements } => assert_eq!(elements.len(), 3),
            _ => panic!("Expected series"),
        }
    }
}
