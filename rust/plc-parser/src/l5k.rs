//! L5K (Legacy ASCII) parser for Allen-Bradley RSLogix 5000 / Studio 5000 files.
//!
//! # L5K File Structure
//!
//! An L5K file is a flat-text export of an entire controller project. The top-level
//! structure is a series of named sections, each delimited by keywords and braces.
//!
//! ```text
//! (* Header comment *)
//! CONTROLLER MyController (ProcessorType := "1769-L33ER", ...)
//!   DATATYPE MyUDT (...)
//!     ...
//!   END_DATATYPE
//!   TAG
//!     Motor_Start : BOOL (Description := "Start pushbutton") := 0;
//!     Line_Speed : DINT := 0;
//!     Delay_Timer : TIMER := [0,5000,0];
//!     MyArray : DINT[10] := [0,0,0,0,0,0,0,0,0,0];
//!   END_TAG
//!   PROGRAM MainProgram (Type := "PROGRAM")
//!     TAG ... END_TAG    (* Program-scoped tags *)
//!     ROUTINE MainRoutine (Type := "RLL")
//!       RC:="Motor seal-in";
//!       N: [XIC(Start_PB) ,XIC(Motor_Run)] OTL(Motor_Run) ;
//!       N: XIO(Stop_PB) OTU(Motor_Run) ;
//!       N: XIC(Motor_Run) TON(Delay_Timer,?,?) ;
//!     END_ROUTINE
//!   END_PROGRAM
//!   TASK MainTask (Type := CONTINUOUS, Rate := 10, Priority := 10)
//!     MainProgram;
//!   END_TASK
//! END_CONTROLLER
//! ```
//!
//! # Rung Expression Grammar
//!
//! The rung expression language is the heart of L5K parsing. Key rules:
//!
//! - Instructions are written as `MNEMONIC(operand1, operand2, ...)` with no spaces
//! - Series (AND) logic: instructions are separated by spaces
//! - Parallel (OR) branches: delimited by `[` and `]`, paths separated by `,`
//! - Branches can be nested: `[XIC(A) [XIC(B),XIC(C)], XIC(D)]`
//!
//! Grammar (simplified):
//! ```text
//! rung_expr   = element+
//! element     = instruction | branch
//! branch      = '[' path (',' path)* ']'
//! path        = element+
//! instruction = mnemonic '(' operand (',' operand)* ')'
//! mnemonic    = ALPHA (ALPHA | DIGIT | '_')*
//! operand     = tag_ref | int_literal | float_literal
//! tag_ref     = IDENT ('.' IDENT | '[' expr ']')*
//! ```

use winnow::prelude::*;
use winnow::ascii::{alpha1, digit1, space0};
use winnow::combinator::{alt, delimited, opt, preceded, repeat, separated};
use winnow::token::{take_while, take_till, one_of};

use plc_core::ast::*;
use plc_core::tags::*;

/// Errors that can occur during L5K parsing.
#[derive(Debug, Clone, thiserror::Error)]
pub enum L5kError {
    #[error("Parse error at position {position}: {message}")]
    ParseError { position: usize, message: String },

    #[error("Unexpected end of input")]
    UnexpectedEof,

    #[error("Unknown section: {0}")]
    UnknownSection(String),

    #[error("Invalid tag declaration: {0}")]
    InvalidTag(String),

    #[error("Invalid rung expression: {0}")]
    InvalidRung(String),

    #[error("Unsupported construct: {0}")]
    Unsupported(String),
}

#[allow(deprecated)]
type PResult<O> = winnow::PResult<O>;

// ─── Rung Expression Parser ─────────────────────────────────────────────────

/// Parse a complete rung expression string into a RungElement.
///
/// Example inputs:
///   "XIC(Motor_Start) OTE(Motor_Run)"
///   "[XIC(Start_PB) ,XIC(Motor_Run)] OTL(Motor_Run)"
///   "XIC(A) [XIC(B) XIC(C),XIC(D)] OTE(Y)"
pub fn parse_rung_expression(input: &str) -> Result<RungElement, L5kError> {
    let trimmed = input.trim();
    if trimmed.is_empty() {
        return Ok(RungElement::Series { elements: vec![] });
    }

    rung_expr.parse(trimmed).map_err(|e| L5kError::InvalidRung(format!("{}", e)))
}

/// Top-level rung expression: a series of elements.
fn rung_expr(input: &mut &str) -> PResult<RungElement> {
    let elements: Vec<RungElement> = repeat(1.., preceded(space0, element)).parse_next(input)?;

    if elements.len() == 1 {
        Ok(elements.into_iter().next().unwrap())
    } else {
        Ok(RungElement::Series { elements })
    }
}

/// A single element: either an instruction or a branch.
fn element(input: &mut &str) -> PResult<RungElement> {
    alt((branch, instruction_element)).parse_next(input)
}

/// Parallel branch: [path, path, ...]
fn branch(input: &mut &str) -> PResult<RungElement> {
    delimited(
        '[',
        separated(1.., branch_path, preceded(space0, ',')),
        preceded(space0, ']'),
    )
    .map(|branches: Vec<RungElement>| RungElement::Parallel { branches })
    .parse_next(input)
}

/// A single branch path (inside [..., ...]): one or more elements in series.
fn branch_path(input: &mut &str) -> PResult<RungElement> {
    let elements: Vec<RungElement> = repeat(1.., preceded(space0, element)).parse_next(input)?;

    if elements.len() == 1 {
        Ok(elements.into_iter().next().unwrap())
    } else {
        Ok(RungElement::Series { elements })
    }
}

/// A single instruction: MNEMONIC(operand, operand, ...)
fn instruction_element(input: &mut &str) -> PResult<RungElement> {
    let inst = instruction.parse_next(input)?;
    Ok(RungElement::Instruction { instruction: inst })
}

fn instruction(input: &mut &str) -> PResult<Instruction> {
    let mnemonic = mnemonic_name.parse_next(input)?;
    let operands = delimited('(', operand_list, ')').parse_next(input)?;

    let instruction_type = parse_mnemonic(mnemonic);
    Ok(Instruction::new(instruction_type, operands))
}

/// Parse a mnemonic name: alphabetic + optional digits/underscores.
fn mnemonic_name<'a>(input: &mut &'a str) -> PResult<&'a str> {
    (
        alpha1,
        take_while(0.., |c: char| c.is_alphanumeric() || c == '_'),
    )
        .recognize()
        .parse_next(input)
}

/// Comma-separated list of operands.
fn operand_list(input: &mut &str) -> PResult<Vec<Operand>> {
    separated(0.., preceded(space0, operand), preceded(space0, ',')).parse_next(input)
}

/// A single operand: tag reference, integer literal, or float literal, or '?' (don't care).
fn operand(input: &mut &str) -> PResult<Operand> {
    alt((
        // '?' means "don't care / use current value" — treat as integer 0
        '?'.map(|_| Operand::IntLiteral { value: 0 }),
        // Try float first (must contain a dot to distinguish from int)
        float_literal,
        // Then integer
        int_literal,
        // Finally tag reference (most general)
        tag_ref,
    ))
    .parse_next(input)
}

fn float_literal(input: &mut &str) -> PResult<Operand> {
    let val: f64 = (
        opt(one_of(['+', '-'])),
        digit1,
        '.',
        digit1,
    )
        .recognize()
        .try_map(|s: &str| s.parse::<f64>())
        .parse_next(input)?;
    Ok(Operand::RealLiteral { value: val })
}

fn int_literal(input: &mut &str) -> PResult<Operand> {
    let val: i64 = (
        opt(one_of(['+', '-'])),
        digit1,
    )
        .recognize()
        .try_map(|s: &str| s.parse::<i64>())
        .parse_next(input)?;
    Ok(Operand::IntLiteral { value: val })
}

/// Tag reference: identifier with optional array indexing and bit addressing.
/// Examples: "Motor_Start", "MyArray[5]", "MyDINT.2", "Timer1.DN", "UDT1.Field[3].Bit"
fn tag_ref(input: &mut &str) -> PResult<Operand> {
    let name = tag_name.parse_next(input)?;
    Ok(Operand::TagRef { name: name.to_string() })
}

/// Parse a full tag name including dots, array indices, and bit addressing.
fn tag_name<'a>(input: &mut &'a str) -> PResult<&'a str> {
    (
        identifier,
        repeat::<_, _, Vec<&str>, _, _>(0.., alt((
            // Array index: [expr]
            ('[', take_till(0.., ']'), ']').recognize(),
            // Dot accessor: .ident
            ('.', identifier).recognize(),
        ))),
    )
        .recognize()
        .parse_next(input)
}

/// Basic identifier: starts with alpha/underscore, followed by alphanumeric/underscore.
fn identifier<'a>(input: &mut &'a str) -> PResult<&'a str> {
    (
        one_of(|c: char| c.is_alphabetic() || c == '_'),
        take_while(0.., |c: char| c.is_alphanumeric() || c == '_'),
    )
        .recognize()
        .parse_next(input)
}

/// Convert an L5K mnemonic string to our InstructionType enum.
fn parse_mnemonic(mnemonic: &str) -> InstructionType {
    match mnemonic.to_uppercase().as_str() {
        "XIC" => InstructionType::Xic,
        "XIO" => InstructionType::Xio,
        "OTE" => InstructionType::Ote,
        "OTL" => InstructionType::Otl,
        "OTU" => InstructionType::Otu,
        "ONS" => InstructionType::Ons,
        "TON" => InstructionType::Ton,
        "TOF" => InstructionType::Tof,
        "RTO" => InstructionType::Rto,
        "CTU" => InstructionType::Ctu,
        "CTD" => InstructionType::Ctd,
        "RES" => InstructionType::Res,
        "EQU" => InstructionType::Equ,
        "NEQ" => InstructionType::Neq,
        "LES" => InstructionType::Les,
        "LEQ" => InstructionType::Leq,
        "GRT" => InstructionType::Grt,
        "GEQ" => InstructionType::Geq,
        "ADD" => InstructionType::Add,
        "SUB" => InstructionType::Sub,
        "MUL" => InstructionType::Mul,
        "DIV" => InstructionType::Div,
        "MOD" => InstructionType::Mod,
        "NEG" => InstructionType::Neg,
        "MOV" => InstructionType::Mov,
        "COP" => InstructionType::Cop,
        "JMP" => InstructionType::Jmp,
        "LBL" => InstructionType::Lbl,
        "JSR" => InstructionType::Jsr,
        "RET" => InstructionType::Ret,
        "SBR" => InstructionType::Sbr,
        other => InstructionType::Unknown { mnemonic: other.to_string() },
    }
}

// ─── Tag Declaration Parser ─────────────────────────────────────────────────

/// Parse an L5K tag declaration line.
///
/// Format: `name : TYPE (attrs) := value ;`
///
/// Examples:
///   Motor_Start : BOOL (Description := "Start pushbutton") := 0;
///   Line_Speed : DINT := 0;
///   Delay_Timer : TIMER := [0,5000,0];
///   MyArray : DINT[10] := [0,0,0,0,0,0,0,0,0,0];
///   BigTag : MyUDT (RADIX := Decimal, ExternalAccess := "Read/Write");
pub fn parse_tag_declaration(input: &str, scope: TagScope) -> Result<Tag, L5kError> {
    let trimmed = input.trim().trim_end_matches(';').trim();

    // Split on first ':' to get name and type+rest
    let colon_pos = trimmed.find(':')
        .ok_or_else(|| L5kError::InvalidTag(format!("No ':' found in: {}", trimmed)))?;

    let name = trimmed[..colon_pos].trim();
    let rest = trimmed[colon_pos + 1..].trim();

    // Parse type (may include array dimensions)
    let (data_type_str, rest) = extract_type_name(rest);
    let data_type = parse_data_type(data_type_str)?;

    // Parse optional attributes (Description, ExternalAccess, etc.)
    let mut description = String::new();
    let mut external_access = ExternalAccess::ReadWrite;
    let mut alias_for = None;

    if let Some(attr_start) = rest.find('(') {
        if let Some(attr_end) = rest.find(')') {
            let attrs = &rest[attr_start + 1..attr_end];
            for attr in attrs.split(',') {
                let attr = attr.trim();
                if let Some(desc_val) = extract_attr(attr, "Description") {
                    description = desc_val;
                } else if let Some(ea_val) = extract_attr(attr, "ExternalAccess") {
                    external_access = match ea_val.as_str() {
                        "Read Only" | "ReadOnly" => ExternalAccess::ReadOnly,
                        "None" => ExternalAccess::None,
                        _ => ExternalAccess::ReadWrite,
                    };
                } else if let Some(alias_val) = extract_attr(attr, "AliasFor") {
                    alias_for = Some(alias_val);
                }
            }
        }
    }

    // Parse optional initial value
    let initial_value = if let Some(eq_pos) = rest.rfind(":=") {
        rest[eq_pos + 2..].trim().to_string()
    } else {
        String::new()
    };

    Ok(Tag {
        id: uuid::Uuid::new_v4().to_string(),
        name: name.to_string(),
        data_type,
        scope,
        description,
        initial_value,
        alias_for,
        external_access,
    })
}

fn extract_type_name(input: &str) -> (&str, &str) {
    // Type name ends at space, '(', ':=', or end of string
    // Type name may include array brackets like DINT[10]
    let mut end = 0;
    let mut in_bracket = false;
    for (i, c) in input.char_indices() {
        match c {
            '[' => { in_bracket = true; end = i + c.len_utf8(); }
            ']' => { in_bracket = false; end = i + c.len_utf8(); }
            ' ' | '(' | ':' if !in_bracket => {
                return (&input[..end], &input[end..]);
            }
            _ => { end = i + c.len_utf8(); }
        }
    }
    (&input[..end], &input[end..])
}

fn parse_data_type(s: &str) -> Result<DataType, L5kError> {
    let s = s.trim();

    // Check for array: TYPE[dim] or TYPE[dim1,dim2]
    if let Some(bracket_pos) = s.find('[') {
        let base_type = &s[..bracket_pos];
        let close = s.find(']').unwrap_or(s.len());
        let dims_str = &s[bracket_pos + 1..close];
        let dimensions: Vec<u32> = dims_str
            .split(',')
            .map(|d| d.trim().parse::<u32>())
            .collect::<Result<Vec<_>, _>>()
            .map_err(|_| L5kError::InvalidTag(format!("Invalid array dimensions: {}", s)))?;

        return Ok(DataType::Array {
            element_type_name: base_type.to_string(),
            dimensions,
        });
    }

    match s.to_uppercase().as_str() {
        "BOOL" => Ok(DataType::Bool),
        "SINT" => Ok(DataType::Sint),
        "INT" => Ok(DataType::Int),
        "DINT" => Ok(DataType::Dint),
        "LINT" => Ok(DataType::Lint),
        "REAL" => Ok(DataType::Real),
        "STRING" => Ok(DataType::StringType),
        "TIMER" => Ok(DataType::Timer),
        "COUNTER" => Ok(DataType::Counter),
        _ => Ok(DataType::Udt { name: s.to_string() }), // preserve original case
    }
}

fn extract_attr(attr: &str, key: &str) -> Option<String> {
    let attr = attr.trim();
    if attr.starts_with(key) {
        if let Some(eq_pos) = attr.find(":=") {
            let val = attr[eq_pos + 2..].trim().trim_matches('"').to_string();
            return Some(val);
        }
    }
    None
}

// ─── Tests ──────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    // ── Rung Expression Tests ──

    #[test]
    fn parse_simple_xic_ote() {
        let result = parse_rung_expression("XIC(Motor_Start) OTE(Motor_Run)").unwrap();
        match result {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[0] {
                    RungElement::Instruction { instruction } => {
                        assert_eq!(instruction.instruction_type, InstructionType::Xic);
                        assert_eq!(instruction.operands.len(), 1);
                    }
                    _ => panic!("Expected instruction"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_parallel_branch() {
        let result = parse_rung_expression("[XIC(A),XIC(B)] OTE(Y)").unwrap();
        match result {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[0] {
                    RungElement::Parallel { branches } => {
                        assert_eq!(branches.len(), 2);
                    }
                    _ => panic!("Expected parallel"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_seal_in_circuit() {
        let result = parse_rung_expression("[XIC(Start_PB),XIC(Motor_Run)] OTL(Motor_Run)").unwrap();
        match result {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[0] {
                    RungElement::Parallel { branches } => assert_eq!(branches.len(), 2),
                    _ => panic!("Expected parallel"),
                }
                match &elements[1] {
                    RungElement::Instruction { instruction } => {
                        assert_eq!(instruction.instruction_type, InstructionType::Otl);
                    }
                    _ => panic!("Expected OTL instruction"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_nested_branch() {
        let result = parse_rung_expression("XIC(A) [XIC(B) XIC(C),XIC(D)] OTE(Y)").unwrap();
        match result {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 3);
                match &elements[1] {
                    RungElement::Parallel { branches } => {
                        assert_eq!(branches.len(), 2);
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
    fn parse_timer_instruction() {
        let result = parse_rung_expression("XIC(Enable) TON(MyTimer,5000,0)").unwrap();
        match result {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[1] {
                    RungElement::Instruction { instruction } => {
                        assert_eq!(instruction.instruction_type, InstructionType::Ton);
                        assert_eq!(instruction.operands.len(), 3);
                        assert!(matches!(&instruction.operands[0], Operand::TagRef { name } if name == "MyTimer"));
                        assert!(matches!(&instruction.operands[1], Operand::IntLiteral { value: 5000 }));
                    }
                    _ => panic!("Expected TON instruction"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_math_instruction() {
        let result = parse_rung_expression("XIC(Go) ADD(SourceA,SourceB,Dest)").unwrap();
        match result {
            RungElement::Series { elements } => {
                match &elements[1] {
                    RungElement::Instruction { instruction } => {
                        assert_eq!(instruction.instruction_type, InstructionType::Add);
                        assert_eq!(instruction.operands.len(), 3);
                    }
                    _ => panic!("Expected ADD"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_dotted_tag_reference() {
        let result = parse_rung_expression("XIC(MyTimer.DN) OTE(Output)").unwrap();
        match result {
            RungElement::Series { elements } => {
                match &elements[0] {
                    RungElement::Instruction { instruction } => {
                        assert!(matches!(&instruction.operands[0],
                            Operand::TagRef { name } if name == "MyTimer.DN"));
                    }
                    _ => panic!("Expected instruction"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_array_tag_reference() {
        let result = parse_rung_expression("XIC(MyArray[5]) OTE(Output)").unwrap();
        match result {
            RungElement::Series { elements } => {
                match &elements[0] {
                    RungElement::Instruction { instruction } => {
                        assert!(matches!(&instruction.operands[0],
                            Operand::TagRef { name } if name == "MyArray[5]"));
                    }
                    _ => panic!("Expected instruction"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_dont_care_operand() {
        let result = parse_rung_expression("TON(Timer1,?,?)").unwrap();
        match result {
            RungElement::Instruction { instruction } => {
                assert_eq!(instruction.instruction_type, InstructionType::Ton);
                assert!(matches!(&instruction.operands[1], Operand::IntLiteral { value: 0 }));
                assert!(matches!(&instruction.operands[2], Operand::IntLiteral { value: 0 }));
            }
            _ => panic!("Expected instruction"),
        }
    }

    #[test]
    fn parse_unknown_instruction() {
        let result = parse_rung_expression("XIC(A) MSG(Config,0,0) OTE(Done)").unwrap();
        match result {
            RungElement::Series { elements } => {
                match &elements[1] {
                    RungElement::Instruction { instruction } => {
                        assert!(matches!(&instruction.instruction_type,
                            InstructionType::Unknown { mnemonic } if mnemonic == "MSG"));
                    }
                    _ => panic!("Expected MSG instruction"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    #[test]
    fn parse_deeply_nested_branches() {
        // [A [B,C],D] — branch containing nested branch
        let result = parse_rung_expression("[XIC(A) [XIC(B),XIC(C)],XIC(D)] OTE(Y)").unwrap();
        match result {
            RungElement::Series { elements } => {
                assert_eq!(elements.len(), 2);
                match &elements[0] {
                    RungElement::Parallel { branches } => {
                        assert_eq!(branches.len(), 2);
                        // First branch: A then nested [B,C]
                        match &branches[0] {
                            RungElement::Series { elements } => {
                                assert_eq!(elements.len(), 2);
                                match &elements[1] {
                                    RungElement::Parallel { branches } => {
                                        assert_eq!(branches.len(), 2);
                                    }
                                    _ => panic!("Expected nested parallel"),
                                }
                            }
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
    fn parse_three_way_branch() {
        // Three parallel paths
        let result = parse_rung_expression("[XIC(A),XIC(B),XIC(C)] OTE(Y)").unwrap();
        match result {
            RungElement::Series { elements } => {
                match &elements[0] {
                    RungElement::Parallel { branches } => {
                        assert_eq!(branches.len(), 3);
                    }
                    _ => panic!("Expected parallel"),
                }
            }
            _ => panic!("Expected series"),
        }
    }

    // ── Tag Declaration Tests ──

    #[test]
    fn parse_bool_tag() {
        let tag = parse_tag_declaration(
            "Motor_Start : BOOL (Description := \"Start pushbutton\") := 0;",
            TagScope::Controller,
        ).unwrap();
        assert_eq!(tag.name, "Motor_Start");
        assert_eq!(tag.data_type, DataType::Bool);
        assert_eq!(tag.description, "Start pushbutton");
    }

    #[test]
    fn parse_dint_tag() {
        let tag = parse_tag_declaration(
            "Line_Speed : DINT := 100;",
            TagScope::Controller,
        ).unwrap();
        assert_eq!(tag.name, "Line_Speed");
        assert_eq!(tag.data_type, DataType::Dint);
        assert_eq!(tag.initial_value, "100");
    }

    #[test]
    fn parse_timer_tag() {
        let tag = parse_tag_declaration(
            "Delay_Timer : TIMER;",
            TagScope::Program { program_name: "MainProgram".to_string() },
        ).unwrap();
        assert_eq!(tag.name, "Delay_Timer");
        assert_eq!(tag.data_type, DataType::Timer);
    }

    #[test]
    fn parse_array_tag() {
        let tag = parse_tag_declaration(
            "MyArray : DINT[10] := [0,0,0,0,0,0,0,0,0,0];",
            TagScope::Controller,
        ).unwrap();
        assert_eq!(tag.name, "MyArray");
        match &tag.data_type {
            DataType::Array { element_type_name, dimensions } => {
                assert_eq!(element_type_name, "DINT");
                assert_eq!(dimensions, &vec![10]);
            }
            _ => panic!("Expected array"),
        }
    }

    #[test]
    fn parse_udt_tag() {
        let tag = parse_tag_declaration(
            "MotorData : Motor_UDT;",
            TagScope::Controller,
        ).unwrap();
        assert_eq!(tag.name, "MotorData");
        assert!(matches!(&tag.data_type, DataType::Udt { name } if name == "Motor_UDT"));
    }
}
