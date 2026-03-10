//! Local ladder logic simulator — executes rungs against an I/O tag table.
//!
//! Phase 2.5 feature: run ladder logic offline for testing.
//! The simulator evaluates each rung left-to-right, tracking power flow
//! through contacts, branches, and coils.

use crate::ast::*;
use crate::project::PlcProject;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// Runtime value of a tag during simulation.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum TagValue {
    Bool { value: bool },
    Int { value: i64 },
    Real { value: f64 },
}

impl TagValue {
    pub fn as_bool(&self) -> bool {
        match self {
            TagValue::Bool { value } => *value,
            TagValue::Int { value } => *value != 0,
            TagValue::Real { value } => *value != 0.0,
        }
    }

    pub fn as_int(&self) -> i64 {
        match self {
            TagValue::Bool { value } => if *value { 1 } else { 0 },
            TagValue::Int { value } => *value,
            TagValue::Real { value } => *value as i64,
        }
    }

    pub fn as_real(&self) -> f64 {
        match self {
            TagValue::Bool { value } => if *value { 1.0 } else { 0.0 },
            TagValue::Int { value } => *value as f64,
            TagValue::Real { value } => *value,
        }
    }
}

/// A single tag's state during simulation, including timer/counter sub-fields.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct SimTag {
    pub name: String,
    pub value: TagValue,
}

/// Result of a single simulation scan.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct ScanResult {
    /// Tag values after the scan
    pub tags: Vec<SimTag>,
    /// Which rungs had power flow reaching the output (for highlighting)
    pub energized_rungs: Vec<u32>,
    /// Scan time in microseconds
    pub scan_time_us: u64,
}

/// The simulation state — holds the I/O table and runs scans.
pub struct SimulatorState {
    pub tags: HashMap<String, TagValue>,
    /// Timer accumulators (tag_name -> accumulated ms)
    timer_accum: HashMap<String, i64>,
    /// Counter accumulators
    counter_accum: HashMap<String, i64>,
    /// Previous contact states for one-shot (ONS) detection
    prev_contact: HashMap<String, bool>,
}

impl SimulatorState {
    /// Initialize simulator from a project's tag database.
    pub fn from_project(project: &PlcProject) -> Self {
        let mut tags = HashMap::new();
        for tag in &project.tag_database.tags {
            let value = match &tag.data_type {
                crate::tags::DataType::Bool => TagValue::Bool { value: false },
                crate::tags::DataType::Sint
                | crate::tags::DataType::Int
                | crate::tags::DataType::Dint
                | crate::tags::DataType::Lint => TagValue::Int { value: 0 },
                crate::tags::DataType::Real => TagValue::Real { value: 0.0 },
                crate::tags::DataType::Timer => {
                    // Timer has sub-fields: .PRE, .ACC, .EN, .TT, .DN
                    tags.insert(format!("{}.PRE", tag.name), TagValue::Int { value: 0 });
                    tags.insert(format!("{}.ACC", tag.name), TagValue::Int { value: 0 });
                    tags.insert(format!("{}.EN", tag.name), TagValue::Bool { value: false });
                    tags.insert(format!("{}.TT", tag.name), TagValue::Bool { value: false });
                    tags.insert(format!("{}.DN", tag.name), TagValue::Bool { value: false });
                    TagValue::Int { value: 0 }
                }
                crate::tags::DataType::Counter => {
                    tags.insert(format!("{}.PRE", tag.name), TagValue::Int { value: 0 });
                    tags.insert(format!("{}.ACC", tag.name), TagValue::Int { value: 0 });
                    tags.insert(format!("{}.CU", tag.name), TagValue::Bool { value: false });
                    tags.insert(format!("{}.DN", tag.name), TagValue::Bool { value: false });
                    TagValue::Int { value: 0 }
                }
                _ => TagValue::Int { value: 0 },
            };
            tags.insert(tag.name.clone(), value);
        }

        SimulatorState {
            tags,
            timer_accum: HashMap::new(),
            counter_accum: HashMap::new(),
            prev_contact: HashMap::new(),
        }
    }

    /// Set a tag value (for forcing I/O).
    pub fn set_tag(&mut self, name: &str, value: TagValue) {
        self.tags.insert(name.to_string(), value);
    }

    /// Get a tag value.
    pub fn get_tag(&self, name: &str) -> TagValue {
        self.tags.get(name).cloned().unwrap_or(TagValue::Bool { value: false })
    }

    /// Run one scan of a routine's rungs. Returns which rungs are energized.
    pub fn scan_routine(&mut self, routine: &Routine, scan_period_ms: i64) -> Vec<u32> {
        let mut energized = Vec::new();
        for rung in &routine.rungs {
            let power = self.evaluate_element(&rung.element, true, scan_period_ms);
            if power {
                energized.push(rung.number);
            }
        }
        energized
    }

    /// Evaluate a rung element, returning whether power flows through.
    fn evaluate_element(&mut self, element: &RungElement, power_in: bool, scan_period_ms: i64) -> bool {
        match element {
            RungElement::Instruction { instruction } => {
                self.evaluate_instruction(instruction, power_in, scan_period_ms)
            }
            RungElement::Series { elements } => {
                let mut power = power_in;
                for el in elements {
                    power = self.evaluate_element(el, power, scan_period_ms);
                }
                power
            }
            RungElement::Parallel { branches } => {
                // Any branch passing power makes the parallel pass
                let mut any_power = false;
                for branch in branches {
                    if self.evaluate_element(branch, power_in, scan_period_ms) {
                        any_power = true;
                    }
                }
                any_power
            }
        }
    }

    fn evaluate_instruction(&mut self, inst: &Instruction, power_in: bool, scan_period_ms: i64) -> bool {
        use InstructionType::*;
        match &inst.instruction_type {
            // ── Contacts (input instructions) ──
            Xic => {
                if !power_in { return false; }
                let tag = self.operand_tag_name(&inst.operands, 0);
                self.get_tag(&tag).as_bool()
            }
            Xio => {
                if !power_in { return false; }
                let tag = self.operand_tag_name(&inst.operands, 0);
                !self.get_tag(&tag).as_bool()
            }
            Ons => {
                if !power_in { return false; }
                let tag = self.operand_tag_name(&inst.operands, 0);
                let current = power_in;
                let prev = self.prev_contact.get(&tag).copied().unwrap_or(false);
                self.prev_contact.insert(tag, current);
                current && !prev
            }

            // ── Coils (output instructions) ──
            Ote => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                self.tags.insert(tag, TagValue::Bool { value: power_in });
                power_in
            }
            Otl => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                if power_in {
                    self.tags.insert(tag, TagValue::Bool { value: true });
                }
                power_in
            }
            Otu => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                if power_in {
                    self.tags.insert(tag, TagValue::Bool { value: false });
                }
                power_in
            }

            // ── Timers ──
            Ton => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                let preset = self.operand_int(&inst.operands, 1);
                if power_in {
                    let acc = self.timer_accum.entry(tag.clone()).or_insert(0);
                    *acc += scan_period_ms;
                    let done = *acc >= preset;
                    self.tags.insert(format!("{}.EN", tag), TagValue::Bool { value: true });
                    self.tags.insert(format!("{}.TT", tag), TagValue::Bool { value: !done });
                    self.tags.insert(format!("{}.DN", tag), TagValue::Bool { value: done });
                    self.tags.insert(format!("{}.ACC", tag), TagValue::Int { value: *acc });
                } else {
                    self.timer_accum.insert(tag.clone(), 0);
                    self.tags.insert(format!("{}.EN", tag), TagValue::Bool { value: false });
                    self.tags.insert(format!("{}.TT", tag), TagValue::Bool { value: false });
                    self.tags.insert(format!("{}.DN", tag), TagValue::Bool { value: false });
                    self.tags.insert(format!("{}.ACC", tag), TagValue::Int { value: 0 });
                }
                power_in
            }
            Tof => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                let preset = self.operand_int(&inst.operands, 1);
                if !power_in {
                    let acc = self.timer_accum.entry(tag.clone()).or_insert(0);
                    *acc += scan_period_ms;
                    let done = *acc >= preset;
                    self.tags.insert(format!("{}.DN", tag), TagValue::Bool { value: done });
                } else {
                    self.timer_accum.insert(tag.clone(), 0);
                    self.tags.insert(format!("{}.DN", tag), TagValue::Bool { value: false });
                }
                power_in
            }
            Rto => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                let preset = self.operand_int(&inst.operands, 1);
                if power_in {
                    let acc = self.timer_accum.entry(tag.clone()).or_insert(0);
                    *acc += scan_period_ms;
                    let done = *acc >= preset;
                    self.tags.insert(format!("{}.EN", tag), TagValue::Bool { value: true });
                    self.tags.insert(format!("{}.DN", tag), TagValue::Bool { value: done });
                    self.tags.insert(format!("{}.ACC", tag), TagValue::Int { value: *acc });
                }
                // RTO doesn't reset on false — that's what RES is for
                power_in
            }

            // ── Counters ──
            Ctu => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                let preset = self.operand_int(&inst.operands, 1);
                let prev = self.prev_contact.get(&tag).copied().unwrap_or(false);
                if power_in && !prev {
                    let acc = self.counter_accum.entry(tag.clone()).or_insert(0);
                    *acc += 1;
                    let done = *acc >= preset;
                    self.tags.insert(format!("{}.ACC", tag), TagValue::Int { value: *acc });
                    self.tags.insert(format!("{}.DN", tag), TagValue::Bool { value: done });
                }
                self.prev_contact.insert(tag, power_in);
                power_in
            }
            Ctd => {
                let tag = self.operand_tag_name(&inst.operands, 0);
                let prev = self.prev_contact.get(&tag).copied().unwrap_or(false);
                if power_in && !prev {
                    let acc = self.counter_accum.entry(tag.clone()).or_insert(0);
                    *acc -= 1;
                    self.tags.insert(format!("{}.ACC", tag), TagValue::Int { value: *acc });
                }
                self.prev_contact.insert(tag, power_in);
                power_in
            }
            Res => {
                if power_in {
                    let tag = self.operand_tag_name(&inst.operands, 0);
                    self.timer_accum.insert(tag.clone(), 0);
                    self.counter_accum.insert(tag.clone(), 0);
                    self.tags.insert(format!("{}.ACC", tag), TagValue::Int { value: 0 });
                    self.tags.insert(format!("{}.DN", tag), TagValue::Bool { value: false });
                    self.tags.insert(format!("{}.EN", tag), TagValue::Bool { value: false });
                    self.tags.insert(format!("{}.TT", tag), TagValue::Bool { value: false });
                }
                power_in
            }

            // ── Compare (input instructions — pass or block power) ──
            Equ => {
                if !power_in { return false; }
                let a = self.resolve_operand_value(&inst.operands, 0);
                let b = self.resolve_operand_value(&inst.operands, 1);
                a.as_int() == b.as_int()
            }
            Neq => {
                if !power_in { return false; }
                let a = self.resolve_operand_value(&inst.operands, 0);
                let b = self.resolve_operand_value(&inst.operands, 1);
                a.as_int() != b.as_int()
            }
            Les => {
                if !power_in { return false; }
                let a = self.resolve_operand_value(&inst.operands, 0);
                let b = self.resolve_operand_value(&inst.operands, 1);
                a.as_int() < b.as_int()
            }
            Leq => {
                if !power_in { return false; }
                let a = self.resolve_operand_value(&inst.operands, 0);
                let b = self.resolve_operand_value(&inst.operands, 1);
                a.as_int() <= b.as_int()
            }
            Grt => {
                if !power_in { return false; }
                let a = self.resolve_operand_value(&inst.operands, 0);
                let b = self.resolve_operand_value(&inst.operands, 1);
                a.as_int() > b.as_int()
            }
            Geq => {
                if !power_in { return false; }
                let a = self.resolve_operand_value(&inst.operands, 0);
                let b = self.resolve_operand_value(&inst.operands, 1);
                a.as_int() >= b.as_int()
            }

            // ── Math (output instructions — execute when power flows) ──
            Add => {
                if power_in {
                    let a = self.resolve_operand_value(&inst.operands, 0).as_int();
                    let b = self.resolve_operand_value(&inst.operands, 1).as_int();
                    let dest = self.operand_tag_name(&inst.operands, 2);
                    self.tags.insert(dest, TagValue::Int { value: a + b });
                }
                power_in
            }
            Sub => {
                if power_in {
                    let a = self.resolve_operand_value(&inst.operands, 0).as_int();
                    let b = self.resolve_operand_value(&inst.operands, 1).as_int();
                    let dest = self.operand_tag_name(&inst.operands, 2);
                    self.tags.insert(dest, TagValue::Int { value: a - b });
                }
                power_in
            }
            Mul => {
                if power_in {
                    let a = self.resolve_operand_value(&inst.operands, 0).as_int();
                    let b = self.resolve_operand_value(&inst.operands, 1).as_int();
                    let dest = self.operand_tag_name(&inst.operands, 2);
                    self.tags.insert(dest, TagValue::Int { value: a * b });
                }
                power_in
            }
            Div => {
                if power_in {
                    let a = self.resolve_operand_value(&inst.operands, 0).as_int();
                    let b = self.resolve_operand_value(&inst.operands, 1).as_int();
                    let dest = self.operand_tag_name(&inst.operands, 2);
                    if b != 0 {
                        self.tags.insert(dest, TagValue::Int { value: a / b });
                    }
                }
                power_in
            }
            Mod => {
                if power_in {
                    let a = self.resolve_operand_value(&inst.operands, 0).as_int();
                    let b = self.resolve_operand_value(&inst.operands, 1).as_int();
                    let dest = self.operand_tag_name(&inst.operands, 2);
                    if b != 0 {
                        self.tags.insert(dest, TagValue::Int { value: a % b });
                    }
                }
                power_in
            }
            Neg => {
                if power_in {
                    let a = self.resolve_operand_value(&inst.operands, 0).as_int();
                    let dest = self.operand_tag_name(&inst.operands, 1);
                    self.tags.insert(dest, TagValue::Int { value: -a });
                }
                power_in
            }
            Mov => {
                if power_in {
                    let val = self.resolve_operand_value(&inst.operands, 0);
                    let dest = self.operand_tag_name(&inst.operands, 1);
                    self.tags.insert(dest, val);
                }
                power_in
            }
            Cop => {
                // Simplified: treat as MOV for basic types
                if power_in {
                    let val = self.resolve_operand_value(&inst.operands, 0);
                    let dest = self.operand_tag_name(&inst.operands, 1);
                    self.tags.insert(dest, val);
                }
                power_in
            }

            // Program control — pass power through (not simulated in basic mode)
            Jmp | Lbl | Jsr | Ret | Sbr => power_in,

            // Unknown — pass power through
            Unknown { .. } => power_in,
        }
    }

    // ── Operand helpers ──

    fn operand_tag_name(&self, operands: &[Operand], index: usize) -> String {
        match operands.get(index) {
            Some(Operand::TagRef { name }) => name.clone(),
            _ => String::new(),
        }
    }

    fn operand_int(&self, operands: &[Operand], index: usize) -> i64 {
        match operands.get(index) {
            Some(Operand::IntLiteral { value }) => *value,
            Some(Operand::TagRef { name }) => self.get_tag(name).as_int(),
            Some(Operand::RealLiteral { value }) => *value as i64,
            None => 0,
        }
    }

    fn resolve_operand_value(&self, operands: &[Operand], index: usize) -> TagValue {
        match operands.get(index) {
            Some(Operand::TagRef { name }) => self.get_tag(name),
            Some(Operand::IntLiteral { value }) => TagValue::Int { value: *value },
            Some(Operand::RealLiteral { value }) => TagValue::Real { value: *value },
            None => TagValue::Int { value: 0 },
        }
    }

    /// Export all tag values as SimTag list for the UI.
    pub fn export_tags(&self) -> Vec<SimTag> {
        let mut tags: Vec<SimTag> = self.tags.iter()
            .map(|(name, value)| SimTag { name: name.clone(), value: value.clone() })
            .collect();
        tags.sort_by(|a, b| a.name.cmp(&b.name));
        tags
    }
}

// ─── UniFFI-exposed simulation functions ────────────────────────────────────

/// Initialize a simulator from a project (creates the I/O table).
/// Returns the initial tag values.
#[uniffi::export]
pub fn sim_init(project: &PlcProject) -> Vec<SimTag> {
    let state = SimulatorState::from_project(project);
    state.export_tags()
}

/// Run one scan of a routine. Takes current tag values, returns updated tags
/// and which rungs are energized.
///
/// Note: This is a stateless call — timer/counter accumulators are derived
/// from the tag values. For full stateful simulation, the Swift side
/// maintains a SimulatorState wrapper.
#[uniffi::export]
pub fn sim_scan_stateless(
    project: &PlcProject,
    program_name: String,
    routine_name: String,
    tag_values: Vec<SimTag>,
    scan_period_ms: i64,
) -> ScanResult {
    let start = std::time::Instant::now();

    // Build state from provided tags
    let mut state = SimulatorState::from_project(project);
    for sim_tag in &tag_values {
        state.tags.insert(sim_tag.name.clone(), sim_tag.value.clone());
    }

    // Find and scan the routine
    let energized = if let Some(routine) = project.find_routine(&program_name, &routine_name) {
        state.scan_routine(routine, scan_period_ms)
    } else {
        vec![]
    };

    let elapsed = start.elapsed();

    ScanResult {
        tags: state.export_tags(),
        energized_rungs: energized,
        scan_time_us: elapsed.as_micros() as u64,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::tags::*;

    fn build_test_project() -> PlcProject {
        let mut project = PlcProject::new("SimTest", ControllerFamily::CompactLogix);
        project.tag_database.add_tag(Tag::new_bool("Start", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Stop", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_bool("Motor", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_dint("Speed", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_dint("Setpoint", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_timer("Delay", TagScope::Controller));
        project.tag_database.add_tag(Tag::new_counter("Count", TagScope::Controller));

        let mut task = Task::new_continuous("MainTask");
        let mut program = Program::new("MainProgram");

        if let Some(routine) = program.main_routine_mut() {
            // Rung 0: XIC(Start) OTL(Motor)
            routine.add_rung(RungElement::series(vec![
                RungElement::instruction(Instruction::contact(true, "Start")),
                RungElement::instruction(Instruction::coil(InstructionType::Otl, "Motor")),
            ]));

            // Rung 1: XIC(Stop) OTU(Motor) — unlatch when Stop IS pressed
            routine.add_rung(RungElement::series(vec![
                RungElement::instruction(Instruction::contact(true, "Stop")),
                RungElement::instruction(Instruction::coil(InstructionType::Otu, "Motor")),
            ]));

            // Rung 2: XIC(Motor) MOV(Setpoint, Speed)
            routine.add_rung(RungElement::series(vec![
                RungElement::instruction(Instruction::contact(true, "Motor")),
                RungElement::instruction(Instruction::new(InstructionType::Mov, vec![
                    Operand::TagRef { name: "Setpoint".to_string() },
                    Operand::TagRef { name: "Speed".to_string() },
                ])),
            ]));

            // Rung 3: XIC(Motor) TON(Delay, 1000, 0)
            routine.add_rung(RungElement::series(vec![
                RungElement::instruction(Instruction::contact(true, "Motor")),
                RungElement::instruction(Instruction::new(InstructionType::Ton, vec![
                    Operand::TagRef { name: "Delay".to_string() },
                    Operand::IntLiteral { value: 1000 },
                    Operand::IntLiteral { value: 0 },
                ])),
            ]));
        }

        task.add_program(program);
        project.add_task(task);
        project
    }

    #[test]
    fn basic_contact_and_coil() {
        let project = build_test_project();
        let routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let mut sim = SimulatorState::from_project(&project);

        // Start is false — Motor should stay off
        sim.scan_routine(routine, 100);
        assert!(!sim.get_tag("Motor").as_bool());

        // Set Start = true — Motor should latch on
        sim.set_tag("Start", TagValue::Bool { value: true });
        sim.scan_routine(routine, 100);
        assert!(sim.get_tag("Motor").as_bool());

        // Start goes false — Motor stays latched (OTL)
        sim.set_tag("Start", TagValue::Bool { value: false });
        sim.scan_routine(routine, 100);
        assert!(sim.get_tag("Motor").as_bool());
    }

    #[test]
    fn stop_unlatches_motor() {
        let project = build_test_project();
        let routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let mut sim = SimulatorState::from_project(&project);

        // Start motor
        sim.set_tag("Start", TagValue::Bool { value: true });
        sim.scan_routine(routine, 100);
        assert!(sim.get_tag("Motor").as_bool());

        // Stop (XIC — pressing stop button unlatches motor)
        sim.set_tag("Stop", TagValue::Bool { value: true });
        sim.scan_routine(routine, 100);
        assert!(!sim.get_tag("Motor").as_bool());
    }

    #[test]
    fn mov_copies_value() {
        let project = build_test_project();
        let routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let mut sim = SimulatorState::from_project(&project);

        sim.set_tag("Start", TagValue::Bool { value: true });
        sim.set_tag("Setpoint", TagValue::Int { value: 1500 });
        sim.scan_routine(routine, 100);

        // Motor is on, so MOV should have copied Setpoint to Speed
        assert_eq!(sim.get_tag("Speed").as_int(), 1500);
    }

    #[test]
    fn timer_accumulates() {
        let project = build_test_project();
        let routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let mut sim = SimulatorState::from_project(&project);

        // Start motor, run timer
        sim.set_tag("Start", TagValue::Bool { value: true });

        // Run 5 scans at 100ms each = 500ms accumulated
        for _ in 0..5 {
            sim.scan_routine(routine, 100);
        }
        assert_eq!(sim.get_tag("Delay.ACC").as_int(), 500);
        assert!(!sim.get_tag("Delay.DN").as_bool()); // Not done yet (preset = 1000)

        // Run 5 more = 1000ms total — should be done
        for _ in 0..5 {
            sim.scan_routine(routine, 100);
        }
        assert_eq!(sim.get_tag("Delay.ACC").as_int(), 1000);
        assert!(sim.get_tag("Delay.DN").as_bool());
    }

    #[test]
    fn timer_resets_on_false_rung() {
        let project = build_test_project();
        let routine = project.find_routine("MainProgram", "MainRoutine").unwrap();
        let mut sim = SimulatorState::from_project(&project);

        // Start motor and accumulate
        sim.set_tag("Start", TagValue::Bool { value: true });
        for _ in 0..5 {
            sim.scan_routine(routine, 100);
        }
        assert_eq!(sim.get_tag("Delay.ACC").as_int(), 500);

        // Stop motor — timer should reset (TON resets on false rung)
        sim.set_tag("Stop", TagValue::Bool { value: true });
        sim.scan_routine(routine, 100);
        assert_eq!(sim.get_tag("Delay.ACC").as_int(), 0);
    }

    #[test]
    fn stateless_scan_api() {
        let project = build_test_project();
        let tags = sim_init(&project);
        assert!(!tags.is_empty());

        // Set Start = true via tag values
        let mut tag_values = tags;
        for tag in &mut tag_values {
            if tag.name == "Start" {
                tag.value = TagValue::Bool { value: true };
            }
            if tag.name == "Setpoint" {
                tag.value = TagValue::Int { value: 1500 };
            }
        }

        let result = sim_scan_stateless(
            &project,
            "MainProgram".to_string(),
            "MainRoutine".to_string(),
            tag_values,
            100,
        );

        // Rung 0 (start→latch) should be energized
        assert!(result.energized_rungs.contains(&0));
        // Motor should be on
        let motor = result.tags.iter().find(|t| t.name == "Motor").unwrap();
        assert!(motor.value.as_bool());
    }
}
