# Phase 0: Architecture & Scope Definition — Detailed Breakdown

**Duration:** 1–2 weeks
**Approach:** Spike-to-learn (throwaway prototypes to validate assumptions, then clean implementation in Phase 1)

---

## Phase 0A: Tech Stack Lock-Down (Days 1–3)

### Decisions to Finalize
- [x] **Core engine language:** Swift (UI) + Rust (parsers, comms, simulation)
- [x] **Swift↔Rust interop:** UniFFI (Mozilla) — auto-generated Swift bindings from Rust
- [x] **Ladder editor rendering:** AppKit + Core Graphics (custom drawing, not SwiftUI Canvas)
- [ ] **UI framework split:** SwiftUI for chrome (sidebar, inspectors, panels) + AppKit/Core Graphics for ladder canvas
- [ ] **Rust crate structure:** Decide on workspace layout (monorepo crate vs. multiple crates)
- [ ] **XML parsing in Rust:** Evaluate `quick-xml` vs. `roxmltree` for L5X parsing
- [ ] **L5K parser approach in Rust:** Hand-rolled recursive descent vs. parser combinator (nom/winnow) vs. pest/PEG
- [ ] **Serialization format for .plcproj:** JSON, TOML, or custom? (Recommend: JSON with Serde for Rust ↔ Swift round-trips)
- [ ] **Build system:** Xcode project + `cargo` with build phase script, or SwiftPM + cargo via build plugin?

### Deliverables
- [ ] Project directory structure scaffolded (Xcode + Cargo workspace)
- [ ] "Hello World" round-trip: Swift calls Rust function via UniFFI, gets result back
- [ ] Tech stack decision document (1 page — what we chose and why)

### Spike Tasks
1. **UniFFI spike (2–4 hrs):** Create minimal Rust crate, define `.udl`, generate Swift bindings, call from macOS app
2. **Build integration spike (2–4 hrs):** Wire up Xcode build phase to compile Rust and link UniFFI output

---

## Phase 0B: Data Model Spike (Days 3–5)

### Decisions to Finalize
- [ ] **Tag type system:** How to represent BOOL, SINT, INT, DINT, REAL, STRING, UDTs, Arrays
- [ ] **Branch representation:** How to model parallel/series branches in the AST (tree of nodes? graph?)
- [ ] **Instruction operand model:** Typed vs. untyped operands, how to handle bit-level addressing (e.g., `MyDINT.5`)
- [ ] **Scope model:** Controller-scope vs. Program-scope vs. Routine-local tags
- [ ] **ID strategy:** How elements reference each other (UUIDs? hierarchical paths? indices?)

### Deliverables
- [ ] Rust structs/enums for: `Project`, `Controller`, `Task`, `Program`, `Routine`, `Rung`, `Instruction`, `Branch`, `Tag`
- [ ] Serde serialization round-trip test (serialize → deserialize → compare)
- [ ] Simple test: programmatically build a 5-rung routine with branches, serialize to JSON, read it back
- [ ] Data model decision document (what the structs look like and why)

### Spike Tasks
1. **AST design spike (4–6 hrs):** Model a real AB program structure in Rust. Represent:
   - A continuous task with one program, one routine
   - 5 rungs: simple XIC/OTE, branch with two parallel paths, timer, counter, math
   - 10 tags of mixed types (BOOL, DINT, TIMER, COUNTER)
2. **Branch modeling spike (2–3 hrs):** Try 2–3 different branch representations, pick the one that makes rendering easiest
3. **Tag database spike (2–3 hrs):** Model scoped tags with aliasing and array indexing

---

## Phase 0C: File Format Reconnaissance (Days 5–8)

### Decisions to Finalize
- [ ] **L5K structure map:** Document every section type and which ones we parse in v1
- [ ] **L5X schema map:** Document the XML structure and which elements map to our AST
- [ ] **Version differences:** Catalog known differences between Studio 5000 v32–v36
- [ ] **Unsupported constructs:** List what we'll skip in v1 (ST routines, FBD, motion, safety, AOIs)
- [ ] **Partial import strategy:** How do we handle projects with things we don't support?

### Deliverables
- [ ] L5K format analysis document with annotated examples from real files
- [ ] L5X format analysis document with annotated XML structure
- [ ] Mapping table: L5K/L5X construct → internal AST node (or "unsupported — skip with warning")
- [ ] List of "hard problems" to solve in Phase 3 (e.g., nested branch syntax in L5K, version-specific tags)

### Spike Tasks
1. **L5K manual study (3–4 hrs):** Open 2–3 real L5K files, annotate the structure by hand. Identify the grammar rules for rung expressions.
2. **L5X manual study (3–4 hrs):** Open 2–3 real L5X files, walk the XML tree. Identify key elements and attributes.
3. **Quick parse test (2–3 hrs):** In Rust, try parsing just the TAG section of an L5K file to prove the grammar is tractable.
4. **Version diff (2 hrs):** Compare same project exported as L5K from two different Studio 5000 versions. Document differences.

---

## Phase 0D: Architecture Document & Risk Register (Days 8–10)

### Decisions to Finalize
- [ ] **Module boundaries:** Define the exact Rust crates and their public APIs
- [ ] **Error handling strategy:** How errors flow from Rust → Swift (Result types, error enums)
- [ ] **Threading model:** Which operations run on background threads? How does Rust async interact with Swift concurrency?
- [ ] **Testing strategy:** Unit tests in Rust, UI tests in Xcode, integration tests crossing the FFI boundary?
- [ ] **CI/CD:** GitHub Actions? Local-only for now?

### Deliverables
- [ ] **Architecture diagram v2:** Not boxes — real module names, real interfaces, real data flow arrows
- [ ] **API surface document:** The Rust functions exposed via UniFFI (at least the Phase 1 subset)
- [ ] **Risk register:** Each risk with likelihood, impact, owner, mitigation, and acceptance criteria
- [ ] **Phase 1 kickoff checklist:** Everything that must be true before Phase 1 starts

### Key Risks to Assess in Phase 0
| # | Risk | Phase 0 Action |
|---|------|---------------|
| 1 | UniFFI can't handle our data model complexity (nested enums, optional fields, callbacks) | Spike in 0A — prove it works with realistic types |
| 2 | L5K grammar is too irregular for clean parsing | Study real files in 0C — identify edge cases early |
| 3 | AppKit + Core Graphics ladder rendering is too slow for 1000+ rungs | Quick render benchmark in 0D (optional spike) |
| 4 | Branch representation doesn't map cleanly between L5K ↔ AST ↔ rendering | Spike in 0B with real branch patterns from sample files |
| 5 | Studio 5000 version differences are larger than expected | Version comparison in 0C |

---

## Phase 0 Exit Criteria

Before starting Phase 1, ALL of these must be true:

- [ ] Swift↔Rust round-trip works (UniFFI proven)
- [ ] Ladder AST can represent real AB programs (validated against sample L5K/L5X)
- [ ] L5K and L5X file structures are understood and documented
- [ ] Architecture diagram shows real modules with real interfaces
- [ ] Risk register is complete and no showstoppers identified
- [ ] Project directory structure is scaffolded and builds cleanly
- [ ] All tech stack decisions are locked and documented

---

## Time Budget Summary

| Sub-Phase | Duration | Focus |
|-----------|----------|-------|
| 0A: Tech Stack Lock-Down | Days 1–3 | Build system, UniFFI, project scaffold |
| 0B: Data Model Spike | Days 3–5 | Rust AST, tag database, serialization |
| 0C: File Format Recon | Days 5–8 | L5K/L5X study, mapping, version analysis |
| 0D: Architecture Doc | Days 8–10 | Formalize, risk register, Phase 1 prep |

**Total: ~10 working days (2 weeks)**

*Note: Sub-phases overlap — e.g., insights from 0C will feed back into 0B's data model design. This is intentional.*
