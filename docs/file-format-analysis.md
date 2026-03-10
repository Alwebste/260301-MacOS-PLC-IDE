# File Format Analysis — L5K and L5X

**Phase 0C deliverable**

---

## 1. L5K Format (ASCII Export)

### Overview
L5K is a flat-text, human-readable export format from RSLogix 5000 / Studio 5000.
Every element of a controller project is represented as nested keyword-delimited sections.

### Top-Level Structure
```
(* Optional header comment *)
CONTROLLER ControllerName (ProcessorType := "1769-L33ER", MajorRev := 34, ...)
  DATATYPE UdtName (FamilyType := NoFamily)
    MEMBER Field1 : DINT;
    MEMBER Field2 : BOOL;
  END_DATATYPE

  TAG
    TagName : DataType (Description := "text", ...) := InitialValue;
    ...
  END_TAG

  PROGRAM ProgramName (Type := "PROGRAM")
    TAG
      ProgramScopedTag : BOOL := 0;
    END_TAG
    ROUTINE RoutineName (Type := "RLL")
      RC:="Rung comment text";
      N: InstructionExpression ;
      ...
    END_ROUTINE
  END_PROGRAM

  TASK TaskName (Type := CONTINUOUS, Rate := 10, Priority := 10)
    ProgramName;
  END_TASK
END_CONTROLLER
```

### Tag Declaration Syntax
```
Name : DataType (Attributes) := InitialValue ;
```

| Component | Examples | Notes |
|-----------|----------|-------|
| Name | `Motor_Start`, `Line1_Speed` | Alphanumeric + underscore |
| DataType | `BOOL`, `DINT`, `TIMER`, `MyUDT`, `DINT[10]` | Includes array dims |
| Attributes | `Description := "text"`, `ExternalAccess := "Read/Write"` | Optional, parenthesized |
| InitialValue | `0`, `1.5`, `[0,5000,0]` (for TIMER) | Optional, after `:=` |

### Rung Expression Grammar

This is the critical format for ladder logic. Syntax:

```
rung_line    = "N:" expression ";"
comment_line = "RC:=" quoted_string ";"

expression   = element (" " element)*
element      = instruction | branch
branch       = "[" path ("," path)* "]"
path         = element (" " element)*
instruction  = mnemonic "(" operand ("," operand)* ")"
mnemonic     = letter (letter | digit | "_")*
operand      = tag_ref | integer | float | "?"
tag_ref      = identifier ("." identifier | "[" index "]")*
```

**Key rules:**
- **Space** = series (AND) — power flows left to right
- **Comma inside `[...]`** = parallel (OR) — multiple paths
- `?` = don't-care operand (use current accumulator value)
- No spaces inside instruction parentheses
- Branches can nest arbitrarily deep

### Rung Examples (Annotated)

```
(* Simple: Start PB energizes motor *)
N: XIC(Start_PB) OTE(Motor_Run) ;

(* Seal-in circuit: Start OR already running -> Latch *)
N: [XIC(Start_PB),XIC(Motor_Run)] OTL(Motor_Run) ;

(* Series AND: Both conditions must be true *)
N: XIC(Sensor_1) XIC(Sensor_2) OTE(Output) ;

(* Nested branch: A AND (B OR C) -> Y *)
N: XIC(A) [XIC(B),XIC(C)] OTE(Y) ;

(* Complex: A AND ((B AND C) OR D) -> Y *)
N: XIC(A) [XIC(B) XIC(C),XIC(D)] OTE(Y) ;

(* Timer: enable condition -> TON with tag, preset, accum *)
N: XIC(Enable) TON(My_Timer,5000,0) ;

(* Compare + Math: if Speed > 100 then multiply *)
N: GRT(Line_Speed,100) MUL(Line_Speed,Factor,Result) ;

(* Timer done bit used as contact *)
N: XIC(My_Timer.DN) OTE(Delayed_Output) ;

(* Array element access *)
N: XIC(MyArray[Index]) OTE(Output) ;
```

---

## 2. L5X Format (XML Export)

### Overview
L5X is Rockwell's XML-based export format. It carries the same information as L5K
but in a structured XML tree. **Critically, the rung expression syntax inside
`<Text>` elements is identical to L5K.**

### XML Structure
```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<RSLogix5000Content SchemaRevision="1.0" SoftwareRevision="34.00"
                     TargetType="Controller" ContainsContext="true">
  <Controller Name="Name" ProcessorType="1769-L33ER"
              MajorRev="34" MinorRev="11">

    <DataTypes>
      <DataType Name="UdtName" Family="NoFamily">
        <Members>
          <Member Name="Field" DataType="DINT" Dimension="0" Radix="Decimal"/>
        </Members>
      </DataType>
    </DataTypes>

    <Tags>
      <Tag Name="TagName" TagType="Base" DataType="BOOL" Radix="Decimal"
           ExternalAccess="Read/Write">
        <Description><![CDATA[Description text]]></Description>
        <Data Format="Decorated">
          <DataValue DataType="BOOL" Value="0"/>
        </Data>
      </Tag>
    </Tags>

    <Programs>
      <Program Name="ProgramName" Type="Normal">
        <Tags><!-- Program-scoped tags --></Tags>
        <Routines>
          <Routine Name="RoutineName" Type="RLL">
            <RLLContent>
              <Rung Number="0" Type="N">
                <Comment><![CDATA[Rung comment]]></Comment>
                <Text><![CDATA[XIC(A) OTE(B) ;]]></Text>
              </Rung>
            </RLLContent>
          </Routine>
        </Routines>
      </Program>
    </Programs>

    <Tasks>
      <Task Name="TaskName" Type="CONTINUOUS" Rate="10" Priority="10"
            Watchdog="500">
        <ScheduledPrograms>
          <ScheduledProgram Name="ProgramName"/>
        </ScheduledPrograms>
      </Task>
    </Tasks>

    <!-- Also: Modules, Trends, AddOnInstructionDefinitions -->
  </Controller>
</RSLogix5000Content>
```

### Key XML Elements

| Element | Parent | Key Attributes | Notes |
|---------|--------|----------------|-------|
| `Controller` | `RSLogix5000Content` | Name, ProcessorType, MajorRev, MinorRev | Root of project data |
| `Tag` | `Tags` | Name, TagType, DataType, Dimensions, Radix, ExternalAccess | Self-closing for simple tags |
| `DataType` | `DataTypes` | Name, Family | UDT definitions |
| `Program` | `Programs` | Name, Type | "Normal" for standard programs |
| `Routine` | `Routines` | Name, Type | "RLL" for ladder, "ST" for structured text |
| `Rung` | `RLLContent` | Number, Type | Type="N" for normal rung |
| `Text` | `Rung` | — | Contains L5K rung expression in CDATA |
| `Comment` | `Rung` | — | Rung comment in CDATA |
| `Task` | `Tasks` | Name, Type, Rate, Priority, Watchdog | CONTINUOUS or PERIODIC |

### Structured Data Types in L5X
```xml
<Tag Name="MyTimer" TagType="Base" DataType="TIMER">
  <Data Format="Decorated">
    <Structure DataType="TIMER">
      <DataValueMember Name="PRE" DataType="DINT" Value="5000"/>
      <DataValueMember Name="ACC" DataType="DINT" Value="0"/>
      <DataValueMember Name="EN" DataType="BOOL" Value="0"/>
      <DataValueMember Name="TT" DataType="BOOL" Value="0"/>
      <DataValueMember Name="DN" DataType="BOOL" Value="0"/>
    </Structure>
  </Data>
</Tag>
```

---

## 3. AST Mapping Table

| L5K/L5X Construct | Our AST Node | Status |
|---|---|---|
| `CONTROLLER` | `PlcProject` + `Controller` | **Supported** |
| `TAG` section | `TagDatabase` + `Tag` | **Supported** |
| `DATATYPE` (UDT) | `DataType::Udt { name }` | **Partial** — stored by name, not structure |
| `PROGRAM` | `Program` | **Supported** |
| `ROUTINE (Type=RLL)` | `Routine` with `Rung` list | **Supported** |
| `ROUTINE (Type=ST)` | — | **Skipped** (v1: ladder only) |
| `ROUTINE (Type=FBD)` | — | **Skipped** |
| `ROUTINE (Type=SFC)` | — | **Skipped** |
| `TASK` | `Task` | **Supported** |
| Rung expression | `RungElement` tree | **Supported** — recursive Series/Parallel/Instruction |
| `XIC`, `XIO`, `OTE`, `OTL`, `OTU`, `ONS` | Bit instructions | **Supported** |
| `TON`, `TOF`, `RTO` | Timer instructions | **Supported** |
| `CTU`, `CTD`, `RES` | Counter instructions | **Supported** |
| `EQU`..`GEQ` | Compare instructions | **Supported** |
| `ADD`..`MOD`, `NEG` | Math instructions | **Supported** |
| `MOV`, `COP` | Move instructions | **Supported** |
| `JMP`, `LBL`, `JSR`, `RET`, `SBR` | Program control | **Supported** |
| `MSG`, `GSV`, `SSV`, other | `InstructionType::Unknown` | **Preserved** for round-trip |
| `AddOnInstruction` | — | **Skipped** (v1) |
| `Modules` (I/O config) | — | **Skipped** (v1) |
| `Trends` | — | **Skipped** (v1) |
| `Motion` instructions | `InstructionType::Unknown` | **Preserved** but not rendered |
| `Safety` tags/programs | — | **Skipped** (v1) |

---

## 4. Hard Problems & Known Issues

### P0: Two Rung Text Syntaxes (CRITICAL)
The AB ecosystem has **two different text representations** for ladder logic:

**Neutral Text** (used in L5X `<Rung><Text>` elements + modern Studio 5000 L5K exports):
```
[XIC(Start_PB),XIC(Motor_Run)] OTL(Motor_Run) ;
XIC(Enable) TON(MyTimer,5000,0) ;
```
- Brackets `[ ]` for parallel branches, commas for OR paths
- Parentheses around operands: `XIC(tag)`
- Semicolons at end of rungs

**Legacy ASCII Text** (used in L5X `<Data Format="L5K">` blocks, older RSLogix versions):
```
BST XIC Start_PB NXB XIC Motor_Run BND OTL Motor_Run
XIC Enable TON MyTimer ? ?
```
- Stack-based branch mnemonics: `BST` (branch start), `NXB` (next branch), `BND` (branch end)
- No parentheses: `XIC tag` not `XIC(tag)`
- No semicolons

**Our parser handles Neutral Text**, which covers:
- All L5X `<Rung><Text>` elements (our primary import path)
- Modern Studio 5000 L5K exports (v20+)

**Phase 3 TODO:** Add a BST/NXB/BND parser for legacy format if customers need it.
This is a risk-managed deferral — L5X import is the primary path.

### P1: Rung Expression Ambiguity
The L5K rung expression grammar is mostly clean, but edge cases exist:
- **Nested array indices**: `Tag[OtherTag[i]]` — bracket nesting in operands
- **Expression operands**: Some AB instructions accept expressions like `Tag + 5` as operands
- **String literals in operands**: Rarely used but possible

**Mitigation:** Our parser handles simple nesting. Complex expression operands will be stored as raw strings in `Operand::TagRef` and flagged during validation.

### P2: UDT Member Access Depth
Real projects use deep UDT access: `Station[5].Conveyor.Motor.Speed`. Our tag name parser handles unlimited dot/bracket chaining, which covers this.

### P3: Version Differences (v32–v36)
Differences between Studio 5000 versions are minimal for ladder logic:
- **v33+**: Added `LINT` (64-bit integer) data type
- **v34+**: New motion instructions (irrelevant for v1)
- **v35+**: Minor XML schema additions (new attributes on existing elements)
- **v36+**: Added some safety features

**Impact:** Low. Our parser handles unknown instructions gracefully and ignores unknown XML attributes.

### P4: Partial Import Strategy
When a project contains unsupported constructs:
1. **ST/FBD/SFC routines**: Silently skipped. User warned in output panel.
2. **Unknown instructions**: Parsed as `InstructionType::Unknown` — displayed as gray boxes in editor, preserved on export.
3. **AOIs (Add-On Instructions)**: Treated as unknown instructions. Call site preserved; definition skipped.
4. **Motion/Safety**: Skipped entirely with warning.

### P5: UDT BOOL Members Use Hidden Backing SINTs
In L5X, BOOL members inside UDTs are stored as `DataType="BIT"` with a hidden
backing `SINT` member. The naming convention:
- Hidden member: `ZZZZZZZZZZ<UDTName><N>` (prefix ensures last-sort)
- BOOL member: `Target="ZZZZZZZZZZMotorData0"` `BitNumber="3"`

```xml
<Member Name="ZZZZZZZZZZMotorData0" DataType="SINT" Hidden="true"/>
<Member Name="Running" DataType="BIT" Target="ZZZZZZZZZZMotorData0" BitNumber="0"/>
<Member Name="Faulted" DataType="BIT" Target="ZZZZZZZZZZMotorData0" BitNumber="1"/>
```

**Mitigation:** When parsing UDTs in Phase 3, skip `Hidden="true"` members and
map BIT members to BOOL. Store the bit-packing info for export fidelity.

### P6: Comments and Whitespace Round-Trip
L5K files have specific whitespace patterns and comment styles that may not survive a parse→modify→export cycle perfectly. For v1, we accept imperfect whitespace round-tripping.

### P6: Large File Performance
Industrial projects can have:
- 5,000+ tags
- 200+ routines
- 1,000+ rungs per routine

Our winnow-based parser is zero-copy where possible. The XML parser (quick-xml) is SAX-style (streaming), not DOM, so memory stays bounded. No performance concerns for v1.
