# Architecture Document v1

**Phase 0D deliverable — March 2026**

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS Application                         │
│                                                                   │
│  ┌──────────┐  ┌──────────────────┐  ┌────────────────────────┐  │
│  │ SwiftUI  │  │  AppKit/CoreGfx  │  │      SwiftUI           │  │
│  │ Sidebar  │  │  Ladder Canvas   │  │  Inspector + Panels    │  │
│  │          │  │  (NSView)        │  │                        │  │
│  └────┬─────┘  └───────┬──────────┘  └──────────┬─────────────┘  │
│       │                │                         │                │
│  ┌────┴────────────────┴─────────────────────────┴─────────────┐  │
│  │              ProjectManager (Swift ObservableObject)         │  │
│  │  - Owns PlcProject state                                    │  │
│  │  - Drives all UI updates via @Published                     │  │
│  │  - Calls UniFFI functions for all data operations           │  │
│  └──────────────────────────┬──────────────────────────────────┘  │
│                              │ UniFFI (auto-generated Swift)      │
├──────────────────────────────┼────────────────────────────────────┤
│                              │ C ABI boundary                     │
│  ┌───────────────────────────┴──────────────────────────────────┐  │
│  │                       plc-core (Rust)                        │  │
│  │                                                               │  │
│  │  ┌─────────┐  ┌──────────┐  ┌────────────┐  ┌────────────┐  │  │
│  │  │ ast.rs  │  │ tags.rs  │  │ project.rs │  │validation.rs│  │  │
│  │  │         │  │          │  │            │  │            │  │  │
│  │  │ Rung    │  │ Tag      │  │ PlcProject │  │ validate   │  │  │
│  │  │ Element │  │ Database │  │ to/from    │  │ _project() │  │  │
│  │  │ tree    │  │ + lookup │  │ JSON       │  │            │  │  │
│  │  └─────────┘  └──────────┘  └────────────┘  └────────────┘  │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                   │
│  ┌──────────────────────┐  ┌──────────────────────────────────┐  │
│  │   plc-parser (Rust)  │  │      plc-comms (Rust)            │  │
│  │                      │  │                                  │  │
│  │  ┌────────┐ ┌──────┐ │  │  ┌─────────────┐ ┌───────────┐  │  │
│  │  │ L5K    │ │ L5X  │ │  │  │ EtherNet/IP │ │ Tag Read/ │  │  │
│  │  │ parser │ │parser│ │  │  │ client      │ │ Write     │  │  │
│  │  │(winnow)│ │(qxml)│ │  │  │ (tokio)     │ │           │  │  │
│  │  └────────┘ └──────┘ │  │  └─────────────┘ └───────────┘  │  │
│  └──────────────────────┘  └──────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Module Interfaces

### plc-core — UniFFI-Exported API Surface (Phase 1)

```rust
// === Project lifecycle ===
fn create_project(name: String, family: ControllerFamily) -> PlcProject;
fn save_project_to_json(project: PlcProject) -> Result<String, String>;
fn load_project_from_json(json: String) -> Result<PlcProject, String>;

// === Validation ===
fn validate_project(project: PlcProject) -> Vec<ValidationIssue>;

// === Planned for Phase 2+ ===
// fn add_rung(project: PlcProject, ...) -> PlcProject;
// fn delete_rung(project: PlcProject, ...) -> PlcProject;
// fn move_rung(project: PlcProject, ...) -> PlcProject;
// fn add_tag(project: PlcProject, ...) -> PlcProject;
// fn import_l5k(content: String) -> Result<PlcProject, String>;
// fn import_l5x(content: String) -> Result<PlcProject, String>;
// fn export_l5k(project: PlcProject) -> Result<String, String>;
// fn export_l5x(project: PlcProject) -> Result<String, String>;
```

### Data Types Exposed to Swift

All types use `uniffi::Record` (structs) or `uniffi::Enum`:

| Rust Type | Swift Type | Usage |
|-----------|-----------|-------|
| `PlcProject` | `PlcProject` | Full project state |
| `Controller` | `Controller` | Controller metadata |
| `Task` | `Task` | Execution task |
| `Program` | `Program` | Program container |
| `Routine` | `Routine` | Ladder routine with rungs |
| `Rung` | `Rung` | Single rung (id, number, element, comment) |
| `RungElement` | `RungElement` | Recursive tree: Instruction/Series/Parallel |
| `Instruction` | `Instruction` | Mnemonic + operands |
| `InstructionType` | `InstructionType` | Enum of all AB instructions |
| `Operand` | `Operand` | TagRef/IntLiteral/RealLiteral |
| `Tag` | `Tag` | Tag definition |
| `TagDatabase` | `TagDatabase` | All tags |
| `DataType` | `DataType` | AB data types |
| `TagScope` | `TagScope` | Controller/Program scope |
| `ValidationIssue` | `ValidationIssue` | Error/Warning with location |

### plc-parser — Internal API (not exposed via UniFFI)

```rust
// Called by plc-core (or future UniFFI wrappers)
fn parse_rung_expression(input: &str) -> Result<RungElement, L5kError>;
fn parse_tag_declaration(input: &str, scope: TagScope) -> Result<Tag, L5kError>;
fn parse_l5x(xml_content: &str) -> Result<PlcProject, L5xError>;
```

### plc-comms — Internal API (Phase 4)

```rust
// Planned — not yet implemented
async fn connect(ip: &str, slot: u8) -> Result<Connection, CommsError>;
async fn read_tag(conn: &Connection, name: &str) -> Result<TagValue, CommsError>;
async fn write_tag(conn: &Connection, name: &str, value: TagValue) -> Result<(), CommsError>;
async fn discover_controllers() -> Result<Vec<ControllerInfo>, CommsError>;
```

---

## Data Flow

### Open Project
```
User clicks "Open" → NSOpenPanel → file URL
  → Swift reads file bytes
  → UniFFI: load_project_from_json(json)
  → Rust: serde_json::from_str → PlcProject
  → UniFFI: returns PlcProject to Swift
  → ProjectManager updates @Published properties
  → SwiftUI re-renders sidebar, inspector
  → LadderNSView.needsDisplay = true → Core Graphics redraws
```

### Edit Rung (Phase 2)
```
User drags instruction onto rung
  → LadderNSView hit-test identifies drop target
  → Swift creates new Instruction/RungElement
  → UniFFI: modify routine (add instruction to rung)
  → Rust: returns updated PlcProject
  → ProjectManager marks project as dirty
  → LadderNSView redraws affected rungs
  → Validation runs in background → issues updated
```

### Import L5X (Phase 3)
```
User clicks "Import L5X" → NSOpenPanel → file URL
  → Swift reads file bytes
  → UniFFI: import_l5x(xml_string)
  → Rust: plc-parser::parse_l5x() → PlcProject
  → (skips ST/FBD routines, flags unknown instructions)
  → UniFFI: returns PlcProject + warnings
  → ProjectManager loads project, displays warnings in output panel
```

---

## Threading Model

| Operation | Thread | Mechanism |
|-----------|--------|-----------|
| UI rendering | Main thread | SwiftUI + AppKit |
| Ladder canvas drawing | Main thread | Core Graphics in `draw(_:)` |
| Project create/open/save | Main thread (fast) | UniFFI sync call |
| Validation | Background | Swift `Task { }` → UniFFI call |
| L5K/L5X import | Background | Swift `Task { }` → UniFFI call |
| EtherNet/IP comms (Phase 4) | Background | Tokio runtime in Rust, bridged via UniFFI async |
| AI suggestions (Phase 5) | Background | HTTP client, results posted to main thread |

**Key rule:** All UniFFI calls that might take >50ms run on a background thread.
The Rust side is single-threaded per call (no internal async for Phase 1-3).
Phase 4 introduces a Tokio runtime for EtherNet/IP, managed inside plc-comms.

---

## Error Handling

Errors flow from Rust → Swift as `Result<T, String>`:

```
Rust: thiserror enum → .to_string() → UniFFI Result<T, String>
Swift: catches as String, displays in output panel or alert
```

For Phase 2+, we may introduce a structured error enum via UniFFI:
```rust
#[uniffi::Enum]
enum PlcError {
    ParseError { message: String, location: String },
    ValidationError { issues: Vec<ValidationIssue> },
    IoError { message: String },
    CommsError { message: String },
}
```

---

## Testing Strategy

| Layer | Framework | What |
|-------|-----------|------|
| Rust unit tests | `cargo test` | AST construction, serialization, parsing, validation |
| Rust integration tests | `cargo test` | Full L5X parse → project → JSON → project round-trip |
| Swift unit tests (Phase 1+) | XCTest | ProjectManager state management |
| UI tests (Phase 2+) | XCUITest | Ladder canvas interactions |
| Cross-FFI tests | Manual + CI | Swift calls UniFFI → Rust → Swift, verify data integrity |

Current test count: **32 tests** across plc-core (9) and plc-parser (23).
