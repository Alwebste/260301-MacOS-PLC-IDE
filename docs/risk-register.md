# Risk Register

**Phase 0D deliverable — March 2026**

---

## Risk Matrix

| # | Risk | Likelihood | Impact | Phase | Status | Mitigation |
|---|------|-----------|--------|-------|--------|------------|
| R1 | UniFFI can't handle data model complexity | **Low** | High | 0A | **Mitigated** | Proved in Phase 0A — all types compile, recursive enums handled via flattening |
| R2 | L5K grammar too irregular for clean parsing | **Low** | High | 0C | **Mitigated** | Winnow parser handles all tested patterns including nested branches, 16 tests passing |
| R3 | AppKit ladder rendering too slow for 1000+ rungs | Medium | Medium | 2 | Open | Phase 2: implement virtualized drawing (only render visible rungs). CG is GPU-accelerated on macOS. |
| R4 | Branch representation doesn't map between L5K ↔ AST ↔ rendering | **Low** | High | 0B/0C | **Mitigated** | Recursive RungElement tree maps cleanly to both L5K syntax and visual layout |
| R5 | Studio 5000 version differences break parser | **Low** | Medium | 0C | **Mitigated** | Differences are minor (new data types, new attributes). Unknown elements preserved, not rejected. |
| R6 | Large real-world L5K/L5X files have undocumented syntax | Medium | Medium | 3 | Open | Parser preserves unknown instructions as `InstructionType::Unknown`. Test against real customer files in Phase 3. |
| R7 | EtherNet/IP protocol complexity | Medium | Medium | 4 | Deferred | Evaluate libplctag (C library with Rust bindings) vs. custom implementation. Spike in Phase 4 week 1. |
| R8 | AI integration latency affects UX | Low | Low | 5 | Deferred | Use streaming responses, background processing. AI is advisory only — never blocks editing. |
| R9 | macOS Sonnet deprecates AppKit APIs we rely on | Low | Medium | Ongoing | Monitor | Using stable, long-lived APIs (NSView, Core Graphics). No deprecated API usage. |
| R10 | User expects RSLogix-exact layout fidelity | Medium | Medium | 2 | Open | We aim for "functionally equivalent" not "pixel-identical". Document differences in user guide. |

---

## Detailed Risk Analysis

### R1: UniFFI Complexity (MITIGATED)
**What we proved:** UniFFI 0.29 proc-macro mode handles:
- Nested enums with associated data (`RungElement::Parallel { branches: Vec<RungElement> }`)
- Structs with Option fields, Vec fields, String fields
- Exported functions returning `Result<T, String>`
- Record types, enum types, all AB data types

**Limitation found:** `Box<T>` not supported. Workaround: use `String` references for recursive types (e.g., array element types). Acceptable trade-off.

### R3: Rendering Performance (OPEN)
**Concern:** A routine with 500+ rungs could have 10,000+ CG draw calls.

**Mitigations planned for Phase 2:**
1. Only draw rungs in the visible scroll region (virtualization)
2. Cache rung layout calculations (recalculate only on edit)
3. Use `setNeedsDisplay(in:)` to invalidate only changed rungs
4. Core Graphics is hardware-accelerated on Apple Silicon — benchmark before optimizing

### R6: Undocumented Syntax (OPEN)
**Concern:** Real industrial files may contain edge cases we haven't seen.

**Mitigations:**
1. Parser falls back to `InstructionType::Unknown` for unrecognized instructions
2. L5X parser skips unknown XML elements without failing
3. Phase 3: test against 5+ real customer files before calling parser "done"
4. Export preserves unknown elements for round-trip safety

### R7: EtherNet/IP Protocol (DEFERRED)
**Options:**
- **libplctag:** Battle-tested C library, handles CIP/PCCC. Rust FFI via `libplctag-rs` crate.
- **Custom implementation:** Full control, no C dependency. Significant effort.
- **Hybrid:** Use libplctag for read/write, custom for discovery.

Decision deferred to Phase 4 spike week.

---

## Phase 0 Risk Resolution Summary

| Risk | Phase 0 Action | Result |
|------|---------------|--------|
| R1 (UniFFI) | Built full data model with UniFFI annotations | All types compile and pass through FFI |
| R2 (L5K grammar) | Built winnow parser with 16 expression tests | Grammar is tractable, parser handles all patterns |
| R4 (Branch mapping) | Tested L5K → AST → JSON → AST round-trip | Clean mapping in all tested cases |
| R5 (Version diffs) | Researched v32-v36 changes | Minor differences, no showstoppers |

**No showstoppers identified. Clear to proceed to Phase 1.**
