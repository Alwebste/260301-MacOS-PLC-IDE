# Phase 1 Kickoff Checklist

All items must be true before starting Phase 1.

---

## Tech Stack (Phase 0A)

- [x] Swift ↔ Rust round-trip works via UniFFI
- [x] Project directory structure scaffolded (Xcode + Cargo workspace)
- [x] Build system wired: Xcode pre-build script → Rust compile → UniFFI bindgen
- [x] All tech stack decisions locked and documented (`docs/tech-stack-decisions.md`)

## Data Model (Phase 0B)

- [x] Ladder AST represents real AB programs (validated with 5-rung routine test)
- [x] Tag database supports all v1 types (BOOL through UDT, arrays)
- [x] Serde JSON round-trip works for full project (create → serialize → deserialize → compare)
- [x] UniFFI exports compile: `create_project`, `save_project_to_json`, `load_project_from_json`, `validate_project`
- [x] 9 tests passing in plc-core

## File Format Recon (Phase 0C)

- [x] L5K format documented with annotated examples
- [x] L5X format documented with XML structure
- [x] Rung expression parser working (16 tests: simple, branches, nesting, timers, math, dotted refs, arrays)
- [x] Tag declaration parser working (5 tests: BOOL, DINT, TIMER, arrays, UDTs)
- [x] L5X parser working (5 tests: full parse, tags, structure, rungs, ST-skip)
- [x] L5X → PlcProject → JSON round-trip tested
- [x] AST mapping table complete — all constructs classified as supported/partial/skipped
- [x] Hard problems cataloged with mitigations
- [x] 23 tests passing in plc-parser

## Architecture (Phase 0D)

- [x] Architecture diagram shows real modules with real interfaces
- [x] UniFFI API surface defined (Phase 1 subset)
- [x] Threading model documented
- [x] Error handling strategy defined
- [x] Testing strategy documented
- [x] Risk register complete — no showstoppers identified

## Totals

- **32 tests** passing across the workspace
- **3 Rust crates** scaffolded (plc-core, plc-parser, plc-comms)
- **6 Swift source files** in the macOS app scaffold
- **4 documentation files** (tech-stack, file-formats, architecture, risks)

---

## Phase 1 Goals

Phase 1 focuses on the **static project viewer** — open an L5X file and see its content:

1. **Wire UniFFI bindings** into the Xcode project (build script integration on Mac)
2. **Project open/save** — load .plcproj (JSON) and display in sidebar
3. **L5X import** — import real L5X files, display programs/routines/tags
4. **Sidebar navigation** — browse tasks → programs → routines in the tree
5. **Tag inspector** — select a tag, see its properties in the right panel
6. **Basic ladder display** — render rungs as text/simple layout (not full graphical yet)
7. **Validation output** — run `validate_project()` and display issues in the bottom panel

**Phase 1 is NOT:**
- Graphical ladder editor (that's Phase 2)
- Drag-and-drop rung editing (Phase 2)
- L5K export (Phase 3)
- Online connectivity (Phase 4)
