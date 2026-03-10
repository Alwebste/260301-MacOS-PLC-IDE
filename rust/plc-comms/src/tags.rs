//! High-level tag value types and CIP wire format conversion.
//!
//! Bridges between plc-core `DataType`/`Tag` types and CIP wire bytes.

use crate::cip::CipType;
use plc_core::tags::DataType;

/// A concrete tag value read from or to be written to a PLC.
#[derive(Debug, Clone, PartialEq)]
pub enum TagValue {
    Bool(bool),
    Sint(i8),
    Int(i16),
    Dint(i32),
    Lint(i64),
    Real(f32),
    Lreal(f64),
    StringVal(String),
    /// Raw bytes for UDT/structure types
    Raw { type_code: u16, data: Vec<u8> },
}

impl TagValue {
    /// Decode a tag value from CIP response data.
    ///
    /// The response data starts with 2 bytes of type code, followed by the value.
    pub fn from_cip_response(data: &[u8]) -> Option<Self> {
        if data.len() < 2 {
            return None;
        }
        let type_code = u16::from_le_bytes([data[0], data[1]]);
        let value_data = &data[2..];

        match CipType::from_u16(type_code) {
            Some(CipType::Bool) => {
                if value_data.is_empty() { return None; }
                Some(TagValue::Bool(value_data[0] != 0))
            }
            Some(CipType::Sint) => {
                if value_data.is_empty() { return None; }
                Some(TagValue::Sint(value_data[0] as i8))
            }
            Some(CipType::Int) => {
                if value_data.len() < 2 { return None; }
                Some(TagValue::Int(i16::from_le_bytes([value_data[0], value_data[1]])))
            }
            Some(CipType::Dint) => {
                if value_data.len() < 4 { return None; }
                Some(TagValue::Dint(i32::from_le_bytes(value_data[..4].try_into().ok()?)))
            }
            Some(CipType::Lint) => {
                if value_data.len() < 8 { return None; }
                Some(TagValue::Lint(i64::from_le_bytes(value_data[..8].try_into().ok()?)))
            }
            Some(CipType::Real) => {
                if value_data.len() < 4 { return None; }
                Some(TagValue::Real(f32::from_le_bytes(value_data[..4].try_into().ok()?)))
            }
            Some(CipType::Lreal) => {
                if value_data.len() < 8 { return None; }
                Some(TagValue::Lreal(f64::from_le_bytes(value_data[..8].try_into().ok()?)))
            }
            Some(CipType::String) => {
                // AB STRING: 4-byte length prefix, then chars
                if value_data.len() < 4 { return None; }
                let str_len = u32::from_le_bytes(value_data[..4].try_into().ok()?) as usize;
                let str_len = str_len.min(value_data.len() - 4);
                let s = String::from_utf8_lossy(&value_data[4..4 + str_len]).into_owned();
                Some(TagValue::StringVal(s))
            }
            _ => {
                Some(TagValue::Raw {
                    type_code,
                    data: value_data.to_vec(),
                })
            }
        }
    }

    /// Encode a tag value to CIP wire format (value bytes only, no type prefix).
    pub fn to_cip_bytes(&self) -> Vec<u8> {
        match self {
            TagValue::Bool(v) => vec![if *v { 0xFF } else { 0x00 }],
            TagValue::Sint(v) => vec![*v as u8],
            TagValue::Int(v) => v.to_le_bytes().to_vec(),
            TagValue::Dint(v) => v.to_le_bytes().to_vec(),
            TagValue::Lint(v) => v.to_le_bytes().to_vec(),
            TagValue::Real(v) => v.to_le_bytes().to_vec(),
            TagValue::Lreal(v) => v.to_le_bytes().to_vec(),
            TagValue::StringVal(s) => {
                let bytes = s.as_bytes();
                let len = bytes.len().min(82) as u32; // AB STRING max 82 chars
                let mut out = len.to_le_bytes().to_vec();
                out.extend_from_slice(&bytes[..len as usize]);
                // Pad to even
                if out.len() % 2 != 0 {
                    out.push(0);
                }
                out
            }
            TagValue::Raw { data, .. } => data.clone(),
        }
    }

    /// Get the CIP type code for this value.
    pub fn cip_type(&self) -> CipType {
        match self {
            TagValue::Bool(_) => CipType::Bool,
            TagValue::Sint(_) => CipType::Sint,
            TagValue::Int(_) => CipType::Int,
            TagValue::Dint(_) => CipType::Dint,
            TagValue::Lint(_) => CipType::Lint,
            TagValue::Real(_) => CipType::Real,
            TagValue::Lreal(_) => CipType::Lreal,
            TagValue::StringVal(_) => CipType::String,
            TagValue::Raw { .. } => CipType::Structure,
        }
    }

    /// Display-friendly string representation of the value.
    pub fn display_string(&self) -> String {
        match self {
            TagValue::Bool(v) => if *v { "1".into() } else { "0".into() },
            TagValue::Sint(v) => format!("{}", v),
            TagValue::Int(v) => format!("{}", v),
            TagValue::Dint(v) => format!("{}", v),
            TagValue::Lint(v) => format!("{}", v),
            TagValue::Real(v) => format!("{:.4}", v),
            TagValue::Lreal(v) => format!("{:.6}", v),
            TagValue::StringVal(v) => format!("'{}'", v),
            TagValue::Raw { data, .. } => format!("[{} bytes]", data.len()),
        }
    }

    /// Try to parse a user-entered string into a TagValue of the given type.
    pub fn parse_for_type(input: &str, data_type: &DataType) -> Option<Self> {
        let trimmed = input.trim();
        match data_type {
            DataType::Bool => {
                match trimmed {
                    "1" | "true" | "TRUE" => Some(TagValue::Bool(true)),
                    "0" | "false" | "FALSE" => Some(TagValue::Bool(false)),
                    _ => None,
                }
            }
            DataType::Sint => trimmed.parse::<i8>().ok().map(TagValue::Sint),
            DataType::Int => trimmed.parse::<i16>().ok().map(TagValue::Int),
            DataType::Dint => trimmed.parse::<i32>().ok().map(TagValue::Dint),
            DataType::Lint => trimmed.parse::<i64>().ok().map(TagValue::Lint),
            DataType::Real => trimmed.parse::<f32>().ok().map(TagValue::Real),
            DataType::StringType => Some(TagValue::StringVal(trimmed.to_string())),
            _ => None,
        }
    }

    /// Convert a plc-core DataType to the corresponding CipType.
    pub fn data_type_to_cip(dt: &DataType) -> Option<CipType> {
        match dt {
            DataType::Bool => Some(CipType::Bool),
            DataType::Sint => Some(CipType::Sint),
            DataType::Int => Some(CipType::Int),
            DataType::Dint => Some(CipType::Dint),
            DataType::Lint => Some(CipType::Lint),
            DataType::Real => Some(CipType::Real),
            DataType::StringType => Some(CipType::String),
            DataType::Timer | DataType::Counter => Some(CipType::Structure),
            DataType::Udt { .. } => Some(CipType::Structure),
            DataType::Array { .. } => None, // arrays need element type
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_dint_from_cip_response() {
        // Type: DINT (0x00C4), Value: 42
        let data = vec![0xC4, 0x00, 42, 0, 0, 0];
        let val = TagValue::from_cip_response(&data).unwrap();
        assert_eq!(val, TagValue::Dint(42));
    }

    #[test]
    fn decode_real_from_cip_response() {
        let f: f32 = 3.14;
        let mut data = vec![0xCA, 0x00];
        data.extend_from_slice(&f.to_le_bytes());
        let val = TagValue::from_cip_response(&data).unwrap();
        assert_eq!(val, TagValue::Real(3.14));
    }

    #[test]
    fn decode_bool_from_cip_response() {
        let data = vec![0xC1, 0x00, 0x01];
        let val = TagValue::from_cip_response(&data).unwrap();
        assert_eq!(val, TagValue::Bool(true));

        let data = vec![0xC1, 0x00, 0x00];
        let val = TagValue::from_cip_response(&data).unwrap();
        assert_eq!(val, TagValue::Bool(false));
    }

    #[test]
    fn decode_string_from_cip_response() {
        let mut data = vec![0xDA, 0x00];
        let s = "Hello";
        data.extend_from_slice(&(s.len() as u32).to_le_bytes());
        data.extend_from_slice(s.as_bytes());
        let val = TagValue::from_cip_response(&data).unwrap();
        assert_eq!(val, TagValue::StringVal("Hello".into()));
    }

    #[test]
    fn roundtrip_dint() {
        let val = TagValue::Dint(12345);
        let bytes = val.to_cip_bytes();
        assert_eq!(bytes, 12345i32.to_le_bytes().to_vec());

        // Simulate full CIP response with type prefix
        let mut response = vec![0xC4, 0x00];
        response.extend_from_slice(&bytes);
        let decoded = TagValue::from_cip_response(&response).unwrap();
        assert_eq!(decoded, val);
    }

    #[test]
    fn roundtrip_real() {
        let val = TagValue::Real(99.5);
        let bytes = val.to_cip_bytes();
        let mut response = vec![0xCA, 0x00];
        response.extend_from_slice(&bytes);
        let decoded = TagValue::from_cip_response(&response).unwrap();
        assert_eq!(decoded, val);
    }

    #[test]
    fn parse_user_input_dint() {
        let val = TagValue::parse_for_type("42", &DataType::Dint).unwrap();
        assert_eq!(val, TagValue::Dint(42));
    }

    #[test]
    fn parse_user_input_bool() {
        assert_eq!(TagValue::parse_for_type("1", &DataType::Bool), Some(TagValue::Bool(true)));
        assert_eq!(TagValue::parse_for_type("0", &DataType::Bool), Some(TagValue::Bool(false)));
        assert_eq!(TagValue::parse_for_type("true", &DataType::Bool), Some(TagValue::Bool(true)));
    }

    #[test]
    fn display_values() {
        assert_eq!(TagValue::Bool(true).display_string(), "1");
        assert_eq!(TagValue::Dint(-100).display_string(), "-100");
        assert_eq!(TagValue::StringVal("test".into()).display_string(), "'test'");
    }
}
