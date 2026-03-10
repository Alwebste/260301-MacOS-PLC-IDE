//! PLC Core Engine
//!
//! Core data model for Allen-Bradley ControlLogix/CompactLogix ladder logic.
//! Exposes types to Swift via UniFFI.

pub mod ast;
pub mod project;
pub mod simulator;
pub mod tags;
pub mod validation;

uniffi::setup_scaffolding!();
