# Tech Stack Decisions — Phase 0A

**Date:** March 2026
**Status:** Locked for Phase 1

---

## 1. Languages

| Layer | Language | Rationale |
|-------|----------|-----------|
| **UI / App Shell** | Swift 5.10+ | Native macOS development, SwiftUI for chrome, AppKit for canvas |
| **Core Engine** | Rust | Memory safety, performance for parsers and protocol handling, excellent serde/serialization |
| **Parsers (L5K/L5X)** | Rust | Zero-copy parsing with winnow, XML with quick-xml |
| **EtherNet/IP Comms** | Rust | Async networking with tokio, byte-level protocol control |

## 2. Swift ↔ Rust Interop

**Choice:** UniFFI 0.29 (Mozilla)

**Why UniFFI over manual C FFI:**
- Auto-generates Swift bindings from Rust type annotations (`#[uniffi::Record]`, `#[uniffi::Enum]`, `#[uniffi::export]`)
- Handles String, Vec, Option, Result, enums with data, structs — all types we need
- No manual bridging headers or unsafe pointer management
- Battle-tested (Firefox, other Mozilla projects)

**Limitations accepted:**
- No `Box<T>` support (recursive types need flattening — solved via string references)
- Small runtime overhead vs raw C FFI (irrelevant for our use case)
- Generated Swift code is verbose (never edited by hand, so acceptable)

## 3. UI Framework Split

| Component | Framework | Rationale |
|-----------|-----------|-----------|
| **Ladder editor canvas** | AppKit + Core Graphics | Full control over custom drawing, hit-testing, drag-drop. Critical for performance with 1000+ rungs. |
| **Sidebar, inspectors, panels** | SwiftUI | Rapid iteration on standard UI components, native macOS look and feel |
| **Window management** | SwiftUI `WindowGroup` | Modern lifecycle, toolbar support |
| **Dialogs (import/export/new)** | SwiftUI + NSOpenPanel | Standard macOS file dialogs |

**Integration:** SwiftUI hosts AppKit views via `NSViewRepresentable`. This is a well-established pattern.

## 4. Rust Crate Structure

```
rust/
├── Cargo.toml          # Workspace root
├── plc-core/           # Core data model, AST, project, tags, validation
│   └── UniFFI bindings (exposed to Swift)
├── plc-parser/         # L5K + L5X parsers (Phase 3)
│   └── Depends on plc-core
└── plc-comms/          # EtherNet/IP client (Phase 4)
    └── Depends on plc-core
```

**Why separate crates:**
- Clean dependency boundaries
- Parser and comms can be developed/tested independently
- Only plc-core needs UniFFI annotations (parser/comms accessed through core)
- Faster incremental compilation

## 5. Key Dependencies

### Rust
| Crate | Version | Purpose |
|-------|---------|---------|
| `serde` + `serde_json` | 1.x | Serialization for .plcproj files and data exchange |
| `uniffi` | 0.29 | Swift binding generation |
| `uuid` | 1.x | Unique IDs for AST nodes |
| `thiserror` | 2.x | Error type definitions |
| `winnow` | 0.6 | L5K parser combinator (Phase 3) |
| `quick-xml` | 0.37 | L5X XML parser (Phase 3) |
| `tokio` | 1.x | Async runtime for EtherNet/IP (Phase 4) |
| `bytes` | 1.x | Binary protocol buffers (Phase 4) |

### macOS
| Tool | Purpose |
|------|---------|
| Xcode 16+ | Build system, signing, packaging |
| XcodeGen | Generate .xcodeproj from project.yml |
| Swift 5.10+ | Language version |
| macOS 14+ SDK | Deployment target |

## 6. Serialization Format (.plcproj)

**Choice:** JSON via Serde

**Why JSON over TOML or custom binary:**
- Human-readable (critical for debugging during development)
- Git-friendly diffs
- Serde makes Rust ↔ JSON trivial
- Easy to inspect and manually edit if needed
- Can always add binary cache format later for performance

## 7. Build System

- **Rust:** Cargo workspace, standard `cargo build`
- **Swift:** Xcode project generated via XcodeGen (`project.yml`)
- **Integration:** Xcode pre-build script calls `build-macos.sh` which:
  1. Builds Rust crates as static library (`libplc_core.a`)
  2. Runs UniFFI bindgen to generate Swift source
  3. Copies artifacts to known paths for Xcode linking

## 8. Decisions Deferred

| Decision | Deferred To | Reason |
|----------|-------------|--------|
| L5K parser strategy (PEG vs. hand-rolled) | Phase 0C/3 | Need to study real files first |
| EtherNet/IP library (libplctag wrapper vs. custom) | Phase 4 | Don't need it for 3+ months |
| AI model provider (Anthropic vs. OpenAI vs. local) | Phase 5 | Market will evolve; keep options open |
| CI/CD pipeline | Phase 1 end | Local dev is fine for now |
| Licensing / DRM approach | Phase 6 | Business decision, not technical |
