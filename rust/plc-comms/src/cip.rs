//! CIP (Common Industrial Protocol) services for Allen-Bradley tag operations.
//!
//! CIP is the application layer that runs on top of EtherNet/IP.
//! AB controllers use symbolic tag addressing (by name) rather than numeric addresses.
//!
//! # Message structure
//!
//! ```text
//! CIP Request:
//!   Service code (u8)
//!   Request path (variable length)
//!   Service-specific data
//!
//! CIP Reply:
//!   Service code | 0x80 (u8)  ← reply flag
//!   Reserved (u8 = 0)
//!   Status (u8, 0 = success)
//!   Additional status size (u8, in 16-bit words)
//!   [Additional status words]
//!   Service-specific data
//! ```

use bytes::BufMut;

// ─── CIP Service Codes ───────────────────────────────────────────────────────

/// CIP service codes used for AB tag operations.
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u8)]
pub enum Service {
    /// Multiple Service Packet
    MultipleService = 0x0A,
    /// Get Attribute All
    GetAttributeAll = 0x01,
    /// Read Tag Service — reads a single tag by symbolic name
    ReadTag = 0x4C,
    /// Write Tag Service — writes a single tag by symbolic name
    WriteTag = 0x4D,
    /// Read Tag Fragmented — reads large tags in fragments
    ReadTagFragmented = 0x52,
    /// Write Tag Fragmented — writes large tags in fragments
    WriteTagFragmented = 0x53,
    /// Forward Open — establish a CIP connection
    ForwardOpen = 0x54,
    /// Large Forward Open — for large connection parameters
    LargeForwardOpen = 0x5B,
    /// Forward Close — close a CIP connection
    ForwardClose = 0x4E,
    /// Get Instance Attribute List
    GetInstanceAttributeList = 0x55,
}

// ─── CIP Data Types ──────────────────────────────────────────────────────────

/// CIP data type codes for AB controllers.
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u16)]
pub enum CipType {
    Bool = 0x00C1,
    Sint = 0x00C2,
    Int = 0x00C3,
    Dint = 0x00C4,
    Lint = 0x00C5,
    Usint = 0x00C6,
    Uint = 0x00C7,
    Udint = 0x00C8,
    Real = 0x00CA,
    Lreal = 0x00CB,
    String = 0x00DA,
    /// Structure — bit 15 set, lower bits = template instance
    Structure = 0x02A0,
}

impl CipType {
    pub fn from_u16(val: u16) -> Option<Self> {
        match val {
            0x00C1 => Some(CipType::Bool),
            0x00C2 => Some(CipType::Sint),
            0x00C3 => Some(CipType::Int),
            0x00C4 => Some(CipType::Dint),
            0x00C5 => Some(CipType::Lint),
            0x00C6 => Some(CipType::Usint),
            0x00C7 => Some(CipType::Uint),
            0x00C8 => Some(CipType::Udint),
            0x00CA => Some(CipType::Real),
            0x00CB => Some(CipType::Lreal),
            0x00DA => Some(CipType::String),
            _ => {
                if val & 0x0FFF == 0x02A0 {
                    Some(CipType::Structure)
                } else {
                    None
                }
            }
        }
    }

    /// Size of the data type in bytes.
    pub fn size(&self) -> usize {
        match self {
            CipType::Bool | CipType::Sint | CipType::Usint => 1,
            CipType::Int | CipType::Uint => 2,
            CipType::Dint | CipType::Udint | CipType::Real => 4,
            CipType::Lint | CipType::Lreal => 8,
            CipType::String => 88, // AB STRING: 4-byte len + 82 chars + 2 padding
            CipType::Structure => 0, // variable
        }
    }
}

// ─── Tag Path Encoding ───────────────────────────────────────────────────────

/// Encode a symbolic tag name into a CIP EPATH (padded ANSI extended symbol segment).
///
/// Format:
///   0x91 (ANSI extended symbol segment)
///   length (u8)
///   name bytes (ASCII)
///   [pad byte if length is odd]
///
/// For array elements like "MyTag[5]", the array index is encoded as:
///   0x28 element_index (for 8-bit index)
///   0x29 0x00 element_index_16 (for 16-bit index)
pub fn encode_tag_path(tag_name: &str) -> Vec<u8> {
    let mut path = Vec::new();

    // Check for array index
    let (base_name, array_index) = if let Some(bracket_pos) = tag_name.find('[') {
        let name = &tag_name[..bracket_pos];
        let idx_str = &tag_name[bracket_pos + 1..tag_name.len() - 1];
        let idx: u32 = idx_str.parse().unwrap_or(0);
        (name, Some(idx))
    } else {
        (tag_name, None)
    };

    // Split on '.' for member access
    let parts: Vec<&str> = base_name.split('.').collect();

    for (i, part) in parts.iter().enumerate() {
        if i > 0 {
            // Check if it's a numeric bit index (e.g., "MyDINT.5")
            if let Ok(bit) = part.parse::<u32>() {
                // Bit index segment: 0x28 index (8-bit) or 0x29 0x00 index (16-bit)
                if bit <= 255 {
                    path.push(0x28);
                    path.push(bit as u8);
                } else {
                    path.push(0x29);
                    path.push(0x00);
                    path.push((bit & 0xFF) as u8);
                    path.push(((bit >> 8) & 0xFF) as u8);
                }
                continue;
            }
        }

        let name_bytes = part.as_bytes();
        path.push(0x91); // ANSI extended symbol segment
        path.push(name_bytes.len() as u8);
        path.extend_from_slice(name_bytes);
        if name_bytes.len() % 2 != 0 {
            path.push(0x00); // pad to even
        }
    }

    // Array element index
    if let Some(idx) = array_index {
        if idx <= 0xFF {
            path.push(0x28);
            path.push(idx as u8);
        } else {
            path.push(0x29);
            path.push(0x00);
            path.push((idx & 0xFF) as u8);
            path.push(((idx >> 8) & 0xFF) as u8);
        }
    }

    path
}

/// Encode a connection path for routing through the backplane.
///
/// For ControlLogix: backplane port 1, slot N, then CPU port 2, address 1
/// Path: [01 slot 02 01] (1 = backplane, slot, 2 = Ethernet port)
///
/// For CompactLogix direct connection: empty path (connect directly).
pub fn encode_connection_path(slot: u8) -> Vec<u8> {
    // Backplane, slot, then message router
    vec![0x01, slot, 0x20, 0x02, 0x24, 0x01]
}

// ─── CIP Message Builders ────────────────────────────────────────────────────

/// Build a CIP Read Tag request.
///
/// Returns the CIP message bytes (to be wrapped in SendRRData or SendUnitData).
pub fn build_read_tag(tag_name: &str, element_count: u16) -> Vec<u8> {
    let path = encode_tag_path(tag_name);
    let path_words = (path.len() / 2) as u8; // path size in 16-bit words

    let mut msg = Vec::new();
    msg.push(Service::ReadTag as u8);
    msg.push(path_words);
    msg.extend_from_slice(&path);
    msg.push((element_count & 0xFF) as u8);
    msg.push(((element_count >> 8) & 0xFF) as u8);
    msg
}

/// Build a CIP Write Tag request.
pub fn build_write_tag(tag_name: &str, data_type: CipType, data: &[u8]) -> Vec<u8> {
    let path = encode_tag_path(tag_name);
    let path_words = (path.len() / 2) as u8;
    let element_count: u16 = 1;

    let mut msg = Vec::new();
    msg.push(Service::WriteTag as u8);
    msg.push(path_words);
    msg.extend_from_slice(&path);
    msg.push((data_type as u16 & 0xFF) as u8);
    msg.push(((data_type as u16 >> 8) & 0xFF) as u8);
    msg.push((element_count & 0xFF) as u8);
    msg.push(((element_count >> 8) & 0xFF) as u8);
    msg.extend_from_slice(data);
    msg
}

/// Build a CIP Forward Open request for establishing a connection.
///
/// This creates an explicit messaging connection to the PLC for tag operations.
pub fn build_forward_open(
    ot_connection_id: u32,
    to_connection_id: u32,
    connection_serial: u16,
    slot: u8,
    rpi_microseconds: u32,
) -> Vec<u8> {
    let route_path = encode_connection_path(slot);
    let route_path_words = (route_path.len() / 2) as u8;

    let mut msg = Vec::new();

    // Unconnected Send wrapper: service 0x52, path to Connection Manager
    msg.push(0x52); // Unconnected Send
    msg.push(0x02); // path size: 2 words
    msg.push(0x20); // class segment (8-bit)
    msg.push(0x06); // Connection Manager class (0x06)
    msg.push(0x24); // instance segment (8-bit)
    msg.push(0x01); // instance 1

    // Priority + tick time
    msg.push(0x0A); // priority/tick = 10
    msg.push(0x05); // timeout ticks = 5

    // Embedded message length (will fill later)
    let embedded_len_pos = msg.len();
    msg.push(0x00);
    msg.push(0x00);

    let embedded_start = msg.len();

    // Forward Open service
    msg.push(Service::ForwardOpen as u8);
    msg.push(0x02); // path size: 2 words (class 0x06, instance 1)
    msg.push(0x20);
    msg.push(0x06);
    msg.push(0x24);
    msg.push(0x01);

    // Connection timing
    msg.push(0x0A); // priority/tick
    msg.push(0x05); // timeout ticks

    // O->T Connection ID
    msg.extend_from_slice(&ot_connection_id.to_le_bytes());
    // T->O Connection ID
    msg.extend_from_slice(&to_connection_id.to_le_bytes());
    // Connection serial number
    msg.extend_from_slice(&connection_serial.to_le_bytes());
    // Originator vendor ID
    msg.put_u16_le(0x0001);
    // Originator serial number
    msg.put_u32_le(0x12345678);
    // Connection timeout multiplier
    msg.push(0x03);
    // Reserved
    msg.push(0x00);
    msg.push(0x00);
    msg.push(0x00);

    // O->T RPI (microseconds)
    msg.extend_from_slice(&rpi_microseconds.to_le_bytes());
    // O->T Network connection parameters (0x43F4 = point-to-point, 500 byte max)
    msg.put_u16_le(0x43F4);

    // T->O RPI
    msg.extend_from_slice(&rpi_microseconds.to_le_bytes());
    // T->O Network connection parameters
    msg.put_u16_le(0x43F4);

    // Transport type/trigger (0xA3 = class 3, application trigger, server)
    msg.push(0xA3);

    // Connection path
    msg.push(route_path_words);
    msg.extend_from_slice(&route_path);

    // Fill in embedded message length
    let embedded_len = (msg.len() - embedded_start) as u16;
    msg[embedded_len_pos] = (embedded_len & 0xFF) as u8;
    msg[embedded_len_pos + 1] = ((embedded_len >> 8) & 0xFF) as u8;

    // Route path (after embedded message)
    msg.push(route_path_words);
    msg.push(0x00); // reserved
    msg.extend_from_slice(&route_path);

    msg
}

/// Build a CIP Forward Close request.
pub fn build_forward_close(connection_serial: u16, slot: u8) -> Vec<u8> {
    let route_path = encode_connection_path(slot);
    let route_path_words = (route_path.len() / 2) as u8;

    let mut msg = Vec::new();

    // Unconnected Send wrapper
    msg.push(0x52); // Unconnected Send
    msg.push(0x02);
    msg.push(0x20);
    msg.push(0x06);
    msg.push(0x24);
    msg.push(0x01);

    msg.push(0x0A); // priority/tick
    msg.push(0x05); // timeout ticks

    let embedded_len_pos = msg.len();
    msg.push(0x00);
    msg.push(0x00);

    let embedded_start = msg.len();

    // Forward Close
    msg.push(Service::ForwardClose as u8);
    msg.push(0x02);
    msg.push(0x20);
    msg.push(0x06);
    msg.push(0x24);
    msg.push(0x01);

    msg.push(0x0A); // priority/tick
    msg.push(0x05); // timeout ticks

    // Connection serial
    msg.extend_from_slice(&connection_serial.to_le_bytes());
    // Originator vendor ID
    msg.put_u16_le(0x0001);
    // Originator serial
    msg.put_u32_le(0x12345678);

    // Connection path
    msg.push(route_path_words);
    msg.push(0x00); // reserved
    msg.extend_from_slice(&route_path);

    let embedded_len = (msg.len() - embedded_start) as u16;
    msg[embedded_len_pos] = (embedded_len & 0xFF) as u8;
    msg[embedded_len_pos + 1] = ((embedded_len >> 8) & 0xFF) as u8;

    // Route path
    msg.push(route_path_words);
    msg.push(0x00);
    msg.extend_from_slice(&route_path);

    msg
}

/// Build a CIP Multiple Service Packet for batching multiple reads/writes.
pub fn build_multiple_service_packet(services: &[Vec<u8>]) -> Vec<u8> {
    let mut msg = Vec::new();
    msg.push(Service::MultipleService as u8);
    msg.push(0x02); // path size: 2 words
    msg.push(0x20); // class segment
    msg.push(0x02); // Message Router class
    msg.push(0x24); // instance segment
    msg.push(0x01); // instance 1

    // Service count
    let count = services.len() as u16;
    msg.push((count & 0xFF) as u8);
    msg.push(((count >> 8) & 0xFF) as u8);

    // Offset table: offsets from start of data after offset table
    let offset_table_size = count as usize * 2;
    let mut offset = offset_table_size as u16;
    for svc in services {
        msg.push((offset & 0xFF) as u8);
        msg.push(((offset >> 8) & 0xFF) as u8);
        offset += svc.len() as u16;
    }

    // Service data
    for svc in services {
        msg.extend_from_slice(svc);
    }

    msg
}

// ─── CIP Response Parsing ────────────────────────────────────────────────────

/// Parsed CIP response.
#[derive(Debug, Clone)]
pub struct CipResponse {
    pub service: u8,
    pub status: u8,
    pub additional_status: Vec<u16>,
    pub data: Vec<u8>,
}

impl CipResponse {
    /// Parse a CIP response from raw bytes.
    pub fn parse(data: &[u8]) -> Option<Self> {
        if data.len() < 4 {
            return None;
        }

        let service = data[0]; // service | 0x80
        let _reserved = data[1];
        let status = data[2];
        let additional_status_words = data[3] as usize;

        let header_end = 4 + additional_status_words * 2;
        if data.len() < header_end {
            return None;
        }

        let mut additional_status = Vec::new();
        for i in 0..additional_status_words {
            let offset = 4 + i * 2;
            let word = u16::from_le_bytes([data[offset], data[offset + 1]]);
            additional_status.push(word);
        }

        let response_data = data[header_end..].to_vec();

        Some(Self {
            service,
            status,
            additional_status,
            data: response_data,
        })
    }

    /// Check if the response indicates success.
    pub fn is_success(&self) -> bool {
        self.status == 0x00
    }
}

/// CIP status codes.
pub mod status {
    pub const SUCCESS: u8 = 0x00;
    pub const PATH_SEGMENT_ERROR: u8 = 0x04;
    pub const PATH_DESTINATION_UNKNOWN: u8 = 0x05;
    pub const PARTIAL_TRANSFER: u8 = 0x06;
    pub const SERVICE_NOT_SUPPORTED: u8 = 0x08;
    pub const INVALID_ATTRIBUTE_VALUE: u8 = 0x09;
    pub const ATTRIBUTE_NOT_SETTABLE: u8 = 0x0E;
    pub const PRIVILEGE_VIOLATION: u8 = 0x0F;
    pub const NOT_ENOUGH_DATA: u8 = 0x13;
    pub const ATTRIBUTE_NOT_SUPPORTED: u8 = 0x14;
    pub const TOO_MUCH_DATA: u8 = 0x15;
    pub const KEY_FAILURE: u8 = 0x1C;
    pub const INVALID_MEMBER: u8 = 0x1E;
    pub const GENERAL_ERROR: u8 = 0xFF;
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encode_simple_tag_path() {
        let path = encode_tag_path("Motor_Run");
        // 0x91, len=9, "Motor_Run", pad
        assert_eq!(path[0], 0x91);
        assert_eq!(path[1], 9);
        assert_eq!(&path[2..11], b"Motor_Run");
        assert_eq!(path[11], 0x00); // pad to even
        assert_eq!(path.len(), 12);
    }

    #[test]
    fn encode_even_length_tag() {
        let path = encode_tag_path("AB");
        assert_eq!(path[0], 0x91);
        assert_eq!(path[1], 2);
        assert_eq!(&path[2..4], b"AB");
        assert_eq!(path.len(), 4); // no padding needed
    }

    #[test]
    fn encode_array_tag_path() {
        let path = encode_tag_path("MyArray[5]");
        // 0x91, len=7, "MyArray", pad, 0x28, 5
        assert_eq!(path[0], 0x91);
        assert_eq!(path[1], 7);
        assert_eq!(&path[2..9], b"MyArray");
        assert_eq!(path[9], 0x00); // pad
        assert_eq!(path[10], 0x28); // element segment (8-bit)
        assert_eq!(path[11], 5);   // index
    }

    #[test]
    fn encode_dotted_tag_path() {
        let path = encode_tag_path("Timer1.DN");
        // First segment: "Timer1"
        assert_eq!(path[0], 0x91);
        assert_eq!(path[1], 6);
        assert_eq!(&path[2..8], b"Timer1");
        // Second segment: "DN"
        assert_eq!(path[8], 0x91);
        assert_eq!(path[9], 2);
        assert_eq!(&path[10..12], b"DN");
    }

    #[test]
    fn encode_bit_access_path() {
        let path = encode_tag_path("MyDINT.5");
        // First segment: "MyDINT"
        assert_eq!(path[0], 0x91);
        assert_eq!(path[1], 6);
        // Second: bit index 5
        assert_eq!(path[8], 0x28);
        assert_eq!(path[9], 5);
    }

    #[test]
    fn build_read_tag_message() {
        let msg = build_read_tag("Motor_Run", 1);
        assert_eq!(msg[0], Service::ReadTag as u8); // 0x4C
        assert_eq!(msg[1], 6); // path size in words (12 bytes / 2)
        // Last 2 bytes: element count = 1
        let len = msg.len();
        assert_eq!(msg[len - 2], 1);
        assert_eq!(msg[len - 1], 0);
    }

    #[test]
    fn build_write_tag_message() {
        let data = 1i32.to_le_bytes();
        let msg = build_write_tag("Motor_Run", CipType::Dint, &data);
        assert_eq!(msg[0], Service::WriteTag as u8); // 0x4D
        // Data type bytes after path
        let path_end = 2 + 12; // service + path_words + 12-byte path
        assert_eq!(msg[path_end], (CipType::Dint as u16 & 0xFF) as u8);
    }

    #[test]
    fn parse_cip_response_success() {
        let data = vec![0xCC, 0x00, 0x00, 0x00, 0xC4, 0x00, 0x42, 0x00, 0x00, 0x00];
        let resp = CipResponse::parse(&data).unwrap();
        assert_eq!(resp.service, 0xCC); // ReadTag reply
        assert!(resp.is_success());
        assert_eq!(resp.data.len(), 6); // type(2) + value(4)
    }

    #[test]
    fn parse_cip_response_error() {
        let data = vec![0xCC, 0x00, 0x04, 0x00]; // PATH_SEGMENT_ERROR
        let resp = CipResponse::parse(&data).unwrap();
        assert_eq!(resp.status, status::PATH_SEGMENT_ERROR);
        assert!(!resp.is_success());
    }

    #[test]
    fn multiple_service_packet() {
        let svc1 = build_read_tag("TagA", 1);
        let svc2 = build_read_tag("TagB", 1);
        let multi = build_multiple_service_packet(&[svc1.clone(), svc2.clone()]);

        assert_eq!(multi[0], Service::MultipleService as u8);
        // Service count at offset 6-7
        assert_eq!(multi[6], 2); // 2 services
        assert_eq!(multi[7], 0);
    }
}
