//! Tag database — models Allen-Bradley tag types, scoping, and aliasing.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// AB data types supported in v1.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum DataType {
    /// 1-bit boolean
    Bool,
    /// 8-bit signed integer
    Sint,
    /// 16-bit signed integer
    Int,
    /// 32-bit signed integer
    Dint,
    /// 64-bit signed integer
    Lint,
    /// 32-bit float
    Real,
    /// AB STRING type (82-char max by default)
    StringType,
    /// Timer structure (TON/TOF/RTO)
    Timer,
    /// Counter structure (CTU/CTD)
    Counter,
    /// Fixed-length array — element type stored as string name since UniFFI
    /// doesn't support recursive types via Box. Resolved at validation time.
    /// e.g., element_type_name = "DINT", dimensions = [10] for DINT[10]
    Array {
        element_type_name: String,
        dimensions: Vec<u32>,
    },
    /// User-Defined Type reference (by name)
    Udt { name: String },
}

/// Where a tag lives in the project hierarchy.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum TagScope {
    /// Visible to entire controller
    Controller,
    /// Visible within a specific program
    Program { program_name: String },
}

/// External access level for a tag.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, uniffi::Enum)]
pub enum ExternalAccess {
    ReadWrite,
    ReadOnly,
    None,
}

/// A single tag definition.
#[derive(Debug, Clone, Serialize, Deserialize, uniffi::Record)]
pub struct Tag {
    /// Unique identifier
    pub id: String,
    /// Tag name (e.g., "Motor_Start", "Line1_Speed")
    pub name: String,
    /// Data type
    pub data_type: DataType,
    /// Scope
    pub scope: TagScope,
    /// Optional description / comment
    pub description: String,
    /// Initial value as string representation (e.g., "0", "1.5", "")
    pub initial_value: String,
    /// If this tag is an alias, the target tag name
    pub alias_for: Option<String>,
    /// External access level
    pub external_access: ExternalAccess,
}

impl Tag {
    pub fn new_bool(name: &str, scope: TagScope) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            data_type: DataType::Bool,
            scope,
            description: String::new(),
            initial_value: "0".to_string(),
            alias_for: None,
            external_access: ExternalAccess::ReadWrite,
        }
    }

    pub fn new_dint(name: &str, scope: TagScope) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            data_type: DataType::Dint,
            scope,
            description: String::new(),
            initial_value: "0".to_string(),
            alias_for: None,
            external_access: ExternalAccess::ReadWrite,
        }
    }

    pub fn new_timer(name: &str, scope: TagScope) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            data_type: DataType::Timer,
            scope,
            description: String::new(),
            initial_value: String::new(),
            alias_for: None,
            external_access: ExternalAccess::ReadWrite,
        }
    }

    pub fn new_counter(name: &str, scope: TagScope) -> Self {
        Self {
            id: Uuid::new_v4().to_string(),
            name: name.to_string(),
            data_type: DataType::Counter,
            scope,
            description: String::new(),
            initial_value: String::new(),
            alias_for: None,
            external_access: ExternalAccess::ReadWrite,
        }
    }
}

/// The tag database — holds all tags for a project, provides lookup.
#[derive(Debug, Clone, Default, Serialize, Deserialize, uniffi::Record)]
pub struct TagDatabase {
    pub tags: Vec<Tag>,
}

impl TagDatabase {
    pub fn new() -> Self {
        Self { tags: Vec::new() }
    }

    pub fn add_tag(&mut self, tag: Tag) {
        self.tags.push(tag);
    }

    pub fn find_by_name(&self, name: &str) -> Option<&Tag> {
        self.tags.iter().find(|t| t.name == name)
    }

    pub fn find_by_scope(&self, scope: &TagScope) -> Vec<&Tag> {
        self.tags.iter().filter(|t| &t.scope == scope).collect()
    }

    pub fn controller_tags(&self) -> Vec<&Tag> {
        self.find_by_scope(&TagScope::Controller)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn tag_creation_and_lookup() {
        let mut db = TagDatabase::new();
        db.add_tag(Tag::new_bool("Motor_Start", TagScope::Controller));
        db.add_tag(Tag::new_bool("Motor_Running", TagScope::Controller));
        db.add_tag(Tag::new_dint("Line_Speed", TagScope::Controller));
        db.add_tag(Tag::new_timer("Delay_Timer", TagScope::Program {
            program_name: "MainProgram".to_string(),
        }));

        assert_eq!(db.tags.len(), 4);
        assert!(db.find_by_name("Motor_Start").is_some());
        assert!(db.find_by_name("Nonexistent").is_none());
        assert_eq!(db.controller_tags().len(), 3);
    }

    #[test]
    fn tag_serialization_roundtrip() {
        let mut db = TagDatabase::new();
        db.add_tag(Tag::new_bool("Test_Tag", TagScope::Controller));
        db.add_tag(Tag::new_dint("Counter_Val", TagScope::Program {
            program_name: "Prog1".to_string(),
        }));

        let json = serde_json::to_string_pretty(&db).unwrap();
        let deserialized: TagDatabase = serde_json::from_str(&json).unwrap();
        assert_eq!(db.tags.len(), deserialized.tags.len());
        assert_eq!(db.tags[0].name, deserialized.tags[0].name);
        assert_eq!(db.tags[1].data_type, deserialized.tags[1].data_type);
    }
}
