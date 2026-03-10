# macOS PLC IDE Development Plan
## Allen-Bradley Integration | Ladder Logic | AI-Assisted Controls

---

## Executive Summary

This document outlines a phased development plan for a native macOS PLC programming IDE focused on Allen-Bradley ControlLogix/CompactLogix platforms. The application will feature:

- Native macOS experience (Swift/SwiftUI)
- Full ladder logic editor with intuitive UX
- L5K/L5X file format compatibility (Studio 5000 interoperability)
- AI-assisted ladder generation and debugging
- EtherNet/IP hardware communication
- Online monitoring and tag inspection

**Target Market:** Controls engineers, system integrators, and OEMs frustrated with Windows-only tools, VM overhead, and slow legacy IDEs.

**Competitive Advantage:** First serious macOS-native PLC IDE with modern UX and AI assistance for the Allen-Bradley ecosystem.

---

## Phase 0: Architecture & Scope Definition
**Duration:** 1–2 weeks  
**Goal:** Establish technical foundation and v1 boundaries

### Key Decisions

#### File Format Strategy
- **Primary format:** L5K/L5X (text/XML exports from Studio 5000)
  - L5K: Legacy ASCII format, human-readable, used for version control
  - L5X: XML format, structured, used for imports/exports and scripting
  - Both are documented and used by third-party tools
- **Why not .ACD?**
  - Binary archive format, proprietary, undocumented
  - Only Rockwell tools natively support it
  - Strategy: Users convert .ACD → L5K/L5X in Studio 5000 if needed

#### Hardware Target (v1 Scope)
- **ControlLogix family** (1756 series)
- **CompactLogix family** (1769 series)
- Communication: **EtherNet/IP** explicit messaging
- Exclude: SLC 500, MicroLogix, other legacy platforms (Phase 2+)

#### Software Architecture

```
┌─────────────────────────────────────────────┐
│         macOS App (Swift/SwiftUI)           │
│  - UI Layer (editors, inspectors, views)   │
│  - Project orchestration                    │
└──────────────┬──────────────────────────────┘
               │
┌──────────────┴──────────────────────────────┐
│         Core Engine (Swift + Rust/C++)      │
│  - Ladder logic AST (data model)           │
│  - L5K/L5X parser & serializer             │
│  - Validation & type checking              │
│  - Code generation & simulation            │
└──────────────┬──────────────────────────────┘
               │
       ┌───────┴────────┐
       │                │
┌──────▼─────┐  ┌──────▼──────────┐
│  Comms     │  │   AI Service    │
│  Module    │  │   Integration   │
│            │  │                 │
│ EtherNet/  │  │ - NL → Ladder   │
│    IP      │  │ - Explain rung  │
│  Client    │  │ - Suggestions   │
└────────────┘  └─────────────────┘
```

### Deliverables
- Architecture diagram (detailed)
- Feature scope document (must-have vs. future)
- Technology stack decisions
- Risk assessment (file format compatibility, ODVA compliance, etc.)

---

## Phase 1: Core Project System & Ladder Model
**Duration:** 4–6 weeks  
**Goal:** Native macOS app that can create and manage ladder projects

### 1.1 Project File System

**Custom project format (.plcproj or similar):**
- Controller metadata
  - Family (ControlLogix, CompactLogix)
  - Model/catalog number
  - IP address and slot
  - Firmware version
- Program organization
  - Tasks (continuous, periodic, event)
  - Programs (main, fault, etc.)
  - Routines (ladder, ST, FBD - ladder only in Phase 1)
- Tag database
  - Base tags (BOOL, INT, DINT, REAL, etc.)
  - Array and UDT support
  - Scope (controller, program, local)
- File references
  - Imported L5K/L5X (if any)
  - Internal intermediate representation

**Project operations:**
- New project wizard
- Open/save/save-as
- Auto-save and crash recovery
- Git-friendly structure (avoid binary blobs where possible)

### 1.2 Ladder Logic Data Model (AST)

**Core structures:**

```
Project
├── Controller
├── Tasks[]
│   └── Programs[]
│       └── Routines[]
│           └── Rungs[]
│               └── Instructions[]
│                   ├── Contacts (XIC, XIO)
│                   ├── Coils (OTE, OTL, OTU, ONS)
│                   ├── Timers (TON, TOF, RTO)
│                   ├── Counters (CTU, CTD, RES)
│                   ├── Math (ADD, SUB, MUL, DIV, etc.)
│                   ├── Compare (EQU, NEQ, LES, GRT, etc.)
│                   ├── Move (MOV, COP)
│                   └── Branches (series/parallel logic)
└── Tags[]
    ├── Name, Type, Scope, Initial Value
    └── Aliases
```

**Validation rules (basic):**
- Tag existence and type checking
- Rung continuity (left power rail to right power rail)
- Instruction operand compatibility
- Nested branch depth limits

### 1.3 macOS UI Shell (SwiftUI)

**Window layout:**
- **Left sidebar:** Project navigator
  - Controller node
  - Tasks/Programs/Routines tree
  - Tags folder
  - I/O configuration (future)
- **Main area:** Ladder editor canvas (initially basic)
- **Right inspector:** Properties panel
  - Tag properties
  - Instruction parameters
  - Rung comments
- **Bottom panel:** Errors/warnings, output log

**Basic interactions:**
- Create/delete programs and routines
- Rename items
- Drag-and-drop reordering (basic)

### Milestone Checklist
- [ ] Create new project with one program and routine
- [ ] Define 5–10 BOOL/INT tags in tag browser
- [ ] Add 3–5 rungs to a ladder routine (programmatically)
- [ ] Display ladder rungs in a scrollable canvas
- [ ] Save/load project from disk
- [ ] Show validation errors in output panel

---

## Phase 2: Ladder Editor UX
**Duration:** 6–10 weeks  
**Goal:** Usable, intuitive ladder editor that controls engineers don't hate

### 2.1 Canvas & Rendering

**Visual fidelity:**
- Horizontal rungs with power rails (left/right)
- Proper spacing for instructions
- Branch rendering (series and parallel logic)
- Highlight selected elements
- Zoom and pan

**Drawing approach:**
- Custom SwiftUI shapes or Core Graphics for ladder elements
- Consistent styling matching AB conventions (optional: user themes)

### 2.2 Instruction Palette & Drag-Drop

**Instruction library (Phase 2 subset):**
- Bit: XIC, XIO, OTE, OTL, OTU, ONS
- Timer: TON, TOF, RTO
- Counter: CTU, CTD, RES
- Math: ADD, SUB, MUL, DIV, MOD
- Compare: EQU, NEQ, GRT, GEQ, LES, LEQ
- Move/Copy: MOV, COP
- Basic program control: JMP, LBL, JSR, RET

**Editing interactions:**
- Drag instruction from palette onto rung
- Drop zones: in-series, in-parallel, output
- Click instruction to edit tag bindings
- Right-click context menu: delete, copy, paste
- Keyboard shortcuts: Insert rung (Ctrl+R), Insert contact (Ctrl+I), etc.

### 2.3 Tag Integration

**Tag browser/picker:**
- Filterable by type (BOOL, INT, DINT, REAL, etc.)
- Search/autocomplete
- Show tag scope (controller, program, routine)
- Quick-create tags from editor

**Tag binding in instructions:**
- Type-ahead when editing operands
- Validation: type mismatch errors highlighted
- Support for array indexing (e.g., `MyArray[5]`)
- Bit addressing (e.g., `MyDINT.2`)

### 2.4 Rung Operations

**Basic editing:**
- Insert rung (above/below)
- Delete rung
- Cut/copy/paste rung
- Duplicate rung
- Rung comments (descriptive text)

**Branch editing:**
- Add parallel branch
- Add nested branch
- Delete branch
- Branch validation (proper structure)

### 2.5 Local Simulation

**Simple scan simulator:**
- Execute ladder logic against internal I/O table
- Step-through mode: run one rung at a time
- Continuous mode: scan at adjustable rate (e.g., 10–100 ms)
- Watch window: live tag values during simulation
- Force I/O: manually set input tags to test logic

**Purpose:**
- Test logic offline before connecting to hardware
- Great for demos and customer validation

### Milestone Checklist
- [ ] Drag 10+ different instructions onto canvas
- [ ] Create branches (parallel and series logic)
- [ ] Bind tags to instruction operands with autocomplete
- [ ] Copy/paste rungs between routines
- [ ] Add rung comments
- [ ] Run local simulation and watch tags change
- [ ] Validate typical ladder patterns (seal-in, timers, counters)

---

## Phase 3: L5K/L5X Integration
**Duration:** 8–12 weeks (overlaps with Phase 2)  
**Goal:** Import/export Allen-Bradley Studio 5000 projects

### 3.1 File Format Background

**L5K Format (Legacy ASCII):**
- Line-oriented text format
- Sections: CONTROLLER, TASK, PROGRAM, ROUTINE, TAG, MODULE, etc.
- Ladder represented as structured text-like syntax
- Version-specific quirks across Studio 5000 versions

**L5X Format (XML):**
- Structured XML with defined schema
- Better for partial imports/exports
- Used by Studio 5000 for import/export and Add-On Instructions
- More verbose but easier to parse

**Key references:**
- Rockwell Automation documentation on L5X schema
- Community tools: `hutcheb/acd` for ACD inspection (optional)

### 3.2 L5K Parser Implementation

**Parser goals:**
- Extract controller, tasks, programs, routines
- Parse tag definitions (base types, arrays, UDTs)
- Convert ladder syntax to internal AST
- Handle version differences gracefully (warn on unknown constructs)

**Parsing strategy:**
- Lexer + recursive descent parser, or
- Use existing parser generators (ANTLR, PEG, etc.)

**Error handling:**
- Warn on unsupported instructions (mark as "unknown" in AST)
- Report parse errors with line numbers
- Allow partial imports (e.g., import only certain programs)

### 3.3 L5X Parser Implementation

**Focus areas:**
- `<Controller>`, `<Tasks>`, `<Programs>`, `<Routines>`, `<Tags>`
- Ladder rungs in `<RLLContent>` or `<Rung>` elements
- Instruction operands and addressing

**Data type mapping:**
- Map AB types (BOOL, SINT, INT, DINT, REAL, STRING, etc.) to internal types
- Support arrays and structures
- Handle ALIAS tags

### 3.4 Import Workflow (UX)

**User flow:**
1. File → Import → Choose L5K or L5X
2. Preview dialog:
   - Show controller name, version
   - List tasks, programs, routines
   - Checkboxes to select what to import
3. Import:
   - Parse selected items
   - Populate internal project
   - Show summary (X rungs imported, Y warnings)

**Warnings/notes:**
- Highlight unsupported instructions
- Note version mismatches
- Suggest manual review for complex logic

### 3.5 Export Workflow

**User flow:**
1. File → Export → L5K or L5X
2. Options dialog:
   - Full export or partial (selected programs/routines)
   - Target Studio 5000 version
3. Export:
   - Serialize internal AST to L5K/L5X format
   - Validate structure
   - Save file

**Round-trip goal:**
- Import L5K → Edit in your tool → Export L5K → Re-import in Studio 5000 with minimal or no errors

### 3.6 Studio 5000 Compatibility Testing

**Test matrix:**
- Studio 5000 versions: v32, v33, v34, v35, v36 (latest as of 2026)
- Controller families: ControlLogix, CompactLogix
- Sample projects:
  - Simple (10–20 rungs)
  - Medium (100–200 rungs, timers, counters, math)
  - Complex (multiple programs, UDTs, arrays)

**Validation:**
- Export from Studio 5000 as L5K/L5X
- Import into your tool
- Verify all rungs/tags present
- Export back to L5K/L5X
- Re-import into Studio 5000
- Compare: no loss of logic or metadata

### Milestone Checklist
- [ ] Parse basic L5K file (controller, 1 program, 1 routine, tags)
- [ ] Parse basic L5X file (same scope)
- [ ] Import a real Studio 5000 project (50+ rungs)
- [ ] Display imported ladder in editor
- [ ] Export project back to L5K
- [ ] Re-import exported L5K into Studio 5000 successfully
- [ ] Handle at least 3 different Studio 5000 versions

---

## Phase 4: Hardware Communication
**Duration:** 6–10 weeks  
**Goal:** Connect to real Allen-Bradley PLCs for monitoring and testing

### 4.1 Realistic v1 Strategy

**Phased approach:**
- **Phase 4a (v1):** Online monitoring and tag read/write (no code download yet)
- **Phase 4b (future):** Explore cooperative workflows with Studio 5000 for code changes
- **Phase 4c (future):** Direct download (requires deeper reverse engineering or ODVA cooperation)

**Why this approach?**
- Downloading code to AB PLCs requires understanding proprietary protocols beyond basic EtherNet/IP
- Many third-party tools (HMIs, data loggers) successfully read/write tags without full download capability
- Provides immediate value: online debugging, tag forcing, live monitoring

### 4.2 EtherNet/IP Implementation

**Protocol layers:**
- **CIP (Common Industrial Protocol):** Application layer
- **EtherNet/IP:** CIP over Ethernet/IP
- Explicit messaging for tag services

**Operations needed:**
- **ForwardOpen:** Establish connection to PLC
- **Read Tag Service:** Read tag values by name or address
- **Write Tag Service:** Write tag values
- **ForwardClose:** Close connection

**Libraries/resources:**
- Open-source EtherNet/IP stacks (e.g., `libplctag`, others)
- ODVA specifications (membership may be required for full docs)
- Community implementations as reference

### 4.3 Connection Manager (UI)

**Connection dialog:**
- Enter PLC IP address
- Slot number (for ControlLogix chassis)
- Connection timeout
- Test connection button

**Connection state:**
- Disconnected / Connecting / Connected / Error
- Display controller name, firmware version on successful connection

### 4.4 Online Monitoring Features

**Tag watch window:**
- Add tags to watch list
- Poll tag values at adjustable rate (100ms–1s)
- Display current values with type formatting
- Edit/write values (with confirmation)

**Live ladder view:**
- Overlay real-time tag states on ladder rungs
- Highlight active paths (energized logic)
- Show timer/counter accumulator values inline
- Scroll to follow scan (optional)

**Force table:**
- Force inputs/outputs for testing
- Enable/disable forces with safety prompts

### 4.5 Download Strategy (Future Phase)

**Short-term (v1):**
- Treat your tool as an **offline editor** with monitoring capability
- Users edit in your tool, export L5K/L5X, download via Studio 5000

**Mid-term (v2):**
- Explore cooperative workflows:
  - Export partial changes as L5X
  - Use Studio 5000 automation interface (if available) to push changes
  - Or prompt user to open in Studio 5000 for download

**Long-term (v3+):**
- Investigate safe, direct download for specific controller families
- Requires deep protocol knowledge, extensive testing, and possibly ODVA partnership

### Milestone Checklist
- [ ] Establish EtherNet/IP connection to ControlLogix PLC
- [ ] Read 10+ tags from live PLC
- [ ] Write tag values and confirm changes on PLC
- [ ] Display live tag states in watch window
- [ ] Overlay live tag states on ladder editor
- [ ] Force I/O and verify behavior on hardware
- [ ] Gracefully handle connection loss and reconnection

---

## Phase 5: AI Ladder Assistant
**Duration:** 6–10 weeks (can start earlier as experiments)  
**Goal:** Intuitive, controls-focused AI to speed up ladder development

### 5.1 AI Use Cases

**Primary features:**
1. **Natural language → Ladder generation**
   - User describes logic in plain English
   - AI generates ladder rungs (or ST, then convert to ladder)
   
2. **Explain rung/routine**
   - User selects rung(s)
   - AI produces plain-English description
   
3. **Suggest improvements**
   - AI reviews logic and suggests optimizations, safety checks, or best practices
   
4. **Debugging help**
   - User describes unexpected behavior
   - AI analyzes ladder and suggests potential issues

### 5.2 Technical Approach

**LLM backend:**
- Use API-based models (OpenAI, Anthropic, local models)
- Fine-tune prompts for PLC/ladder domain

**Domain-specific prompts:**
- Include ladder semantics (scan cycle, XIC/XIO/OTE, seal-in patterns)
- Provide examples of common patterns (motor control, safety interlocks, sequencing)
- Emphasize safety and industrial best practices

**Data flow:**
```
User input (NL text)
    ↓
AI service (prompt + LLM)
    ↓
Structured output (JSON with ladder instructions)
    ↓
Parse into internal AST
    ↓
Insert into ladder editor as draft
    ↓
User reviews, edits, accepts
```

### 5.3 UI Integration

**AI panel (sidebar or popup):**
- Text input: "Describe the logic you want"
- Generate button
- Output preview: generated rungs shown in mini-view
- Accept / Edit / Regenerate buttons

**Contextual AI:**
- Right-click on rung → "Explain this rung"
- Right-click on routine → "Suggest optimizations"
- Inline suggestions as you type tag names

### 5.4 Human-in-the-Loop Philosophy

**Critical principle:**
- AI generates **drafts and suggestions**, not production code
- Engineer **always reviews and approves** changes
- Clear visual distinction between AI-generated and human-verified logic

**Safety considerations:**
- Add warnings for safety-critical applications
- Encourage testing in simulation before deploying to hardware
- Log AI-generated code for audit trails

### 5.5 Domain Training & Iteration

**Improvement loop:**
- Collect anonymized ladder patterns from users (with permission)
- Refine prompts based on failure cases
- Build library of validated patterns (e.g., "three-wire control", "conveyor sequencing")

**Quality metrics:**
- Success rate: % of AI-generated rungs that compile without errors
- Acceptance rate: % of suggestions users keep
- User feedback: thumbs up/down on AI outputs

### Milestone Checklist
- [ ] Generate simple ladder rung from NL description (e.g., "start motor when button pressed")
- [ ] Generate complex logic (timers, counters, interlocks)
- [ ] Explain existing rung in plain English
- [ ] Suggest optimization for a routine
- [ ] Integrate AI panel into main UI
- [ ] Collect feedback from 3–5 beta users on AI quality

---

## Phase 6: Hardening, Packaging & Design Partners
**Duration:** Ongoing after Phase 3–4  
**Goal:** Production-ready software for pilot customers

### 6.1 Performance & Reliability

**Performance targets:**
- Open 1,000-rung project in < 2 seconds
- Smooth ladder editing (no lag when dragging/inserting)
- Fast L5K import (10,000 lines in < 5 seconds)
- Low memory footprint (< 500 MB for typical projects)

**Reliability:**
- Crash recovery: auto-save every 2 minutes
- Graceful error handling (no silent failures)
- Comprehensive logging for debugging

### 6.2 Packaging & Distribution

**macOS app bundle:**
- Notarized and signed (Apple Developer ID)
- Universal binary (Intel + Apple Silicon)
- Drag-to-install DMG

**Licensing:**
- Time-limited trial (30 days, full features)
- Per-seat license keys
- Simple activation flow (email + key)

**Updates:**
- In-app update notifications
- Auto-download and install (with user permission)

### 6.3 Documentation & Training

**Essential docs:**
- Quick start guide (5-minute walkthrough)
- Tutorial: Import L5K, edit ladder, export, test on hardware
- Reference: keyboard shortcuts, instruction library
- Troubleshooting: common issues and solutions

**Video content:**
- 3–5 minute demo: "macOS PLC IDE in action"
- Tutorial series: importing, editing, AI features, hardware testing

### 6.4 Design Partner Program

**Target partners:**
- 3–5 system integrators or OEMs
- Mix of small (1–5 engineers) and medium (10–20 engineers)
- Active AB users frustrated with Studio 5000

**Engagement model:**
- Free or heavily discounted licenses
- Weekly check-ins for first month
- Structured feedback: surveys, bug reports, feature requests
- Co-develop case studies for marketing

**Success metrics:**
- Partner completes real project using your tool
- Partner exports to L5K, downloads via Studio 5000, deploys to production hardware
- Partner willing to provide testimonial and reference

### Milestone Checklist
- [ ] Pass Apple notarization
- [ ] Ship v1.0 DMG to 3 design partners
- [ ] Collect structured feedback from all partners
- [ ] Fix critical bugs within 48 hours
- [ ] Document 2–3 real-world use cases
- [ ] Achieve 80%+ satisfaction rating from partners

---

## Technical Risks & Mitigations

### Risk 1: L5K/L5X Compatibility
**Risk:** AB changes formats across Studio 5000 versions; partial/broken imports  
**Mitigation:**
- Test against multiple versions (v32–v36+)
- Build version detection and graceful degradation
- Maintain compatibility matrix in docs

### Risk 2: EtherNet/IP Complexity
**Risk:** Hardware comms harder than expected; protocol edge cases  
**Mitigation:**
- Start with well-tested libraries (libplctag, etc.)
- Limit v1 scope to read/write tags, not full download
- Partner with ODVA or experienced integrators for guidance

### Risk 3: AI Quality
**Risk:** AI generates incorrect or unsafe ladder logic  
**Mitigation:**
- Human-in-the-loop: AI is assistant, not autopilot
- Extensive prompt engineering and testing
- Validate AI outputs against known-good patterns
- Clear disclaimers about testing before production use

### Risk 4: Market Adoption
**Risk:** Engineers resist switching from Studio 5000  
**Mitigation:**
- Focus on pain points: macOS support, speed, modern UX
- Ensure seamless L5K/L5X round-tripping (low switching cost)
- Leverage design partners for testimonials and case studies

### Risk 5: Legal/IP Issues
**Risk:** Rockwell claims IP infringement or protocol violations  
**Mitigation:**
- Use only documented formats (L5K/L5X) and public protocols (EtherNet/IP via ODVA)
- Avoid reverse-engineering proprietary binaries
- Consult IP attorney before launch
- Position as "interoperable tool" not "Studio 5000 replacement"

---

## MVP Definition (for Funding Pitch)

**What investors/customers will see in 9–12 months:**

### Core Features
✅ Native macOS app (Swift/SwiftUI)  
✅ Full ladder logic editor (drag-drop, branches, 20+ instructions)  
✅ Import/export L5K and L5X (Studio 5000 compatibility)  
✅ Local simulation with tag watch window  
✅ EtherNet/IP connection to ControlLogix/CompactLogix  
✅ Online tag monitoring and forcing  
✅ AI-assisted ladder generation (NL → ladder)  
✅ AI rung explanation and optimization suggestions  

### Proven with Design Partners
✅ 3–5 real integrator/OEM projects completed  
✅ Round-trip: import AB project → edit → export → download via Studio 5000 → deploy to hardware  
✅ Case studies showing time savings and UX improvements  

### Not in MVP (Phase 2+)
❌ Direct code download (still uses Studio 5000 for download)  
❌ HMI development (separate product later)  
❌ Full structured text (ST) or function block (FBD) editors  
❌ SLC 500, MicroLogix, or non-AB platform support  
❌ Advanced features: motion control, safety, process control instructions  

---

## Resource Requirements

### Team (assumes $1M, 18 months)

**Founder (You):**
- Role: Product vision, eng lead, some coding, technical marketing
- Time: Full-time (80+ hrs/week initially)
- Comp: ~$110k/year

**Engineer 1 (Senior Backend/PLC):**
- Role: L5K/L5X parsers, EtherNet/IP, core engine
- Skills: Rust/C++, protocols, industrial automation background
- Comp: ~$120k/year + 1–1.5% equity

**Engineer 2 (Product/macOS):**
- Role: SwiftUI ladder editor, UX, project system
- Skills: Swift, SwiftUI, native macOS development
- Comp: ~$100k/year + 0.5–1% equity

**Business Ops/Sales Lead:**
- Role: Customer development, sales, ops, partner with founder on GTM
- Skills: B2B sales, industrial/automation market knowledge
- Comp: ~$150k/year + 2% equity

**Total comp over 18 months:** ~$720k  
**Remaining for ops:** ~$280k (cloud, hardware, legal, travel, etc.)

### Infrastructure & Tools

**Development:**
- Xcode, Instruments (profiling)
- Test PLC hardware: 1–2 CompactLogix units (~$3–5k)
- EtherNet/IP test setup (switches, cables)

**Cloud/AI:**
- LLM API costs (OpenAI, Anthropic): ~$500–2k/month in heavy dev/testing
- Backend services (if any): minimal (mostly local app)

**Legal/Admin:**
- IP attorney consultation: ~$5–10k
- Business formation, accounting: ~$5k/year
- Apple Developer Program: ~$100/year

**Marketing/Sales:**
- Website, domain, hosting: ~$2k/year
- Conference booth/sponsorships: ~$10–20k/year
- Travel to integrators/OEMs: ~$10k/year

---

## Success Metrics

### Product Milestones
- **Month 3:** Internal alpha (basic ladder editor + simulation)
- **Month 6:** L5K import/export working, first design partner pilot
- **Month 9:** Hardware connectivity, AI features live, 3 design partners
- **Month 12:** v1.0 shipped, 5–10 paying accounts
- **Month 18:** 50+ seats, expanding PLC family support, HMI roadmap

### Business Metrics
- **Revenue (18 months):** $25–50k ARR from design partners and early adopters
- **Pipeline:** 20+ qualified leads (integrators/OEMs interested)
- **NPS:** 50+ from design partners (would recommend to peers)

### Technical Metrics
- **Compatibility:** 95%+ successful L5K/L5X round-trips with Studio 5000
- **Performance:** < 2s load time for 1,000-rung projects
- **Uptime:** < 5 critical bugs per month in production use

---

## Conclusion

This plan provides a realistic, phased path from concept to production-ready macOS PLC IDE. By focusing first on Allen-Bradley (the dominant North American platform), ladder logic (the most widely used language), and L5K/L5X interoperability (the documented, supported formats), the project minimizes technical risk while maximizing market impact.

The AI-assisted features differentiate from legacy tools, the macOS-native experience solves a major pain point, and the phased approach to hardware communication ensures early value (monitoring, testing) without requiring full reverse-engineering of proprietary download protocols.

With a small, focused team and $1M over 18 months, this plan is achievable and positions the product for a follow-on seed round based on proven design partner traction and early revenue.

---

## Appendices

### Appendix A: Instruction Reference (Phase 1 Subset)

| Category | Instructions | Notes |
|----------|--------------|-------|
| **Bit** | XIC, XIO, OTE, OTL, OTU, ONS | Core ladder logic |
| **Timer** | TON, TOF, RTO | Basic timing |
| **Counter** | CTU, CTD, RES | Up/down counting |
| **Math** | ADD, SUB, MUL, DIV, MOD, SQR, NEG | Arithmetic |
| **Compare** | EQU, NEQ, LES, LEQ, GRT, GEQ, LIM | Comparisons |
| **Move** | MOV, COP | Data movement |
| **Program Control** | JMP, LBL, JSR, RET, SBR, MCR | Flow control (subset) |

### Appendix B: Studio 5000 Version Compatibility Target

| Version | Release Year | Priority | Notes |
|---------|--------------|----------|-------|
| v36 | 2024 | High | Latest as of 2026 |
| v35 | 2023 | High | Widely adopted |
| v34 | 2022 | Medium | Still in use |
| v33 | 2021 | Medium | Legacy support |
| v32 | 2020 | Low | Older, less common |

### Appendix C: Recommended Reading & Resources

**File Formats:**
- Rockwell Automation: "Logix5000 Import/Export Reference"
- Community tool: `hutcheb/acd` (GitHub)

**EtherNet/IP:**
- ODVA: "EtherNet/IP Specification" (membership required for full access)
- `libplctag` documentation (open-source library)

**Ladder Logic:**
- "Ladder Logic Basics" (LadderLogicWorld.com)
- IEC 61131-3 standard (ladder logic semantics)

**AI for Industrial:**
- Research: "AI Allows Modeling PLC Programs at the Component Level" (Design News, 2025)
- "AI in CODESYS and PLC Programming" (LinkedIn article, 2025)

---

**Document Version:** 1.0  
**Date:** March 10, 2026  
**Author:** Development Plan for macOS PLC IDE (Allen-Bradley Focus)
