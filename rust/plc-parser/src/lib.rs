#![allow(deprecated)] // winnow 0.6 API renames (recognize->take, PResult->ModalResult)
//! PLC Parser — L5K (ASCII) and L5X (XML) file format parsers.
//!
//! Both L5K and L5X use the same rung expression syntax for ladder logic.
//! The L5K parser handles the overall file structure and rung expressions;
//! the L5X parser handles XML structure and delegates rung parsing to L5K.

pub mod l5k;
pub mod l5x;

// Re-export the main entry points
pub use l5k::{parse_rung_expression, parse_tag_declaration, L5kError};
pub use l5x::{parse_l5x, L5xError};
