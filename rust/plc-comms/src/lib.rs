//! PLC Communications — EtherNet/IP client for Allen-Bradley controllers.
//!
//! Implements the EtherNet/IP encapsulation protocol and CIP (Common Industrial Protocol)
//! services for reading/writing tags on ControlLogix and CompactLogix PLCs.
//!
//! # Architecture
//!
//! ```text
//! ┌─────────────┐     ┌──────────────┐     ┌─────────────┐
//! │  Swift UI    │────▶│  plc-comms   │────▶│   PLC       │
//! │  (Watch/     │     │  (EtherNet/  │     │  (CLX/CPLX) │
//! │   Force)     │◀────│   IP + CIP)  │◀────│             │
//! └─────────────┘     └──────────────┘     └─────────────┘
//! ```
//!
//! # Protocol Stack
//!
//! - **TCP/IP** — Port 44818
//! - **EtherNet/IP** — Encapsulation layer (RegisterSession, SendRRData, SendUnitData)
//! - **CIP** — Application layer (Read Tag, Write Tag, ForwardOpen/Close)

pub mod cip;
pub mod client;
pub mod eip;
pub mod tags;
