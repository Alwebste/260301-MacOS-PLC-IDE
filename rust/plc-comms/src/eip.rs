//! EtherNet/IP encapsulation layer.
//!
//! All EtherNet/IP messages share a common 24-byte encapsulation header:
//!
//! ```text
//! Offset  Size  Field
//! 0       2     Command (LE)
//! 2       2     Length of data following header (LE)
//! 4       4     Session handle (LE)
//! 8       4     Status (LE, 0 = success)
//! 12      8     Sender context (echoed back by target)
//! 20      4     Options (0)
//! 24      *     Command-specific data
//! ```

use bytes::{Buf, BufMut, BytesMut};

/// EtherNet/IP default TCP port.
pub const EIP_TCP_PORT: u16 = 44818;

/// Encapsulation header size in bytes.
pub const ENCAP_HEADER_SIZE: usize = 24;

// ─── Commands ────────────────────────────────────────────────────────────────

/// EtherNet/IP encapsulation commands.
#[derive(Debug, Clone, Copy, PartialEq)]
#[repr(u16)]
pub enum Command {
    /// No operation
    Nop = 0x0000,
    /// List available targets
    ListServices = 0x0004,
    /// List all CIP interfaces
    ListIdentity = 0x0063,
    /// List all available CIP interfaces
    ListInterfaces = 0x0064,
    /// Register a session
    RegisterSession = 0x0065,
    /// Unregister a session
    UnregisterSession = 0x0066,
    /// Send RR (Request/Reply) Data — unconnected messaging
    SendRRData = 0x006F,
    /// Send Unit Data — connected messaging
    SendUnitData = 0x0070,
}

impl Command {
    pub fn from_u16(val: u16) -> Option<Self> {
        match val {
            0x0000 => Some(Command::Nop),
            0x0004 => Some(Command::ListServices),
            0x0063 => Some(Command::ListIdentity),
            0x0064 => Some(Command::ListInterfaces),
            0x0065 => Some(Command::RegisterSession),
            0x0066 => Some(Command::UnregisterSession),
            0x006F => Some(Command::SendRRData),
            0x0070 => Some(Command::SendUnitData),
            _ => None,
        }
    }
}

// ─── Encapsulation Header ────────────────────────────────────────────────────

/// Parsed EtherNet/IP encapsulation header.
#[derive(Debug, Clone)]
pub struct EncapHeader {
    pub command: u16,
    pub length: u16,
    pub session_handle: u32,
    pub status: u32,
    pub sender_context: [u8; 8],
    pub options: u32,
}

impl EncapHeader {
    /// Encode header into bytes.
    pub fn encode(&self, buf: &mut BytesMut) {
        buf.put_u16_le(self.command);
        buf.put_u16_le(self.length);
        buf.put_u32_le(self.session_handle);
        buf.put_u32_le(self.status);
        buf.put_slice(&self.sender_context);
        buf.put_u32_le(self.options);
    }

    /// Decode header from bytes. Requires at least ENCAP_HEADER_SIZE bytes.
    pub fn decode(buf: &mut &[u8]) -> Option<Self> {
        if buf.len() < ENCAP_HEADER_SIZE {
            return None;
        }
        let command = buf.get_u16_le();
        let length = buf.get_u16_le();
        let session_handle = buf.get_u32_le();
        let status = buf.get_u32_le();
        let mut sender_context = [0u8; 8];
        buf.copy_to_slice(&mut sender_context);
        let options = buf.get_u32_le();

        Some(Self {
            command,
            length,
            session_handle,
            status,
            sender_context,
            options,
        })
    }
}

// ─── Message Builders ────────────────────────────────────────────────────────

/// Build a RegisterSession request.
///
/// Data payload: protocol_version (u16 LE = 1) + options_flags (u16 LE = 0) = 4 bytes.
pub fn build_register_session() -> BytesMut {
    let mut buf = BytesMut::with_capacity(ENCAP_HEADER_SIZE + 4);
    let header = EncapHeader {
        command: Command::RegisterSession as u16,
        length: 4,
        session_handle: 0,
        status: 0,
        sender_context: [0; 8],
        options: 0,
    };
    header.encode(&mut buf);
    buf.put_u16_le(1); // protocol version
    buf.put_u16_le(0); // options flags
    buf
}

/// Build an UnregisterSession request.
pub fn build_unregister_session(session_handle: u32) -> BytesMut {
    let mut buf = BytesMut::with_capacity(ENCAP_HEADER_SIZE);
    let header = EncapHeader {
        command: Command::UnregisterSession as u16,
        length: 0,
        session_handle,
        status: 0,
        sender_context: [0; 8],
        options: 0,
    };
    header.encode(&mut buf);
    buf
}

/// Build a SendRRData request wrapping a CIP message.
///
/// SendRRData format:
/// - Interface handle: u32 = 0 (CIP)
/// - Timeout: u16 = 10 (seconds)
/// - Item count: u16 = 2
/// - Item 1: Null Address (type=0x0000, length=0)
/// - Item 2: Unconnected Data (type=0x00B2, length=N, data=CIP message)
pub fn build_send_rr_data(session_handle: u32, cip_data: &[u8]) -> BytesMut {
    // CPF (Common Packet Format) overhead: interface(4) + timeout(2) + count(2) + item1(4) + item2_header(4)
    let cpf_overhead = 16;
    let data_len = cpf_overhead + cip_data.len();

    let mut buf = BytesMut::with_capacity(ENCAP_HEADER_SIZE + data_len);
    let header = EncapHeader {
        command: Command::SendRRData as u16,
        length: data_len as u16,
        session_handle,
        status: 0,
        sender_context: [0; 8],
        options: 0,
    };
    header.encode(&mut buf);

    // Common Packet Format
    buf.put_u32_le(0); // interface handle (CIP)
    buf.put_u16_le(10); // timeout (seconds)
    buf.put_u16_le(2);  // item count

    // Item 1: Null Address
    buf.put_u16_le(0x0000); // type: Null
    buf.put_u16_le(0);      // length: 0

    // Item 2: Unconnected Data Item
    buf.put_u16_le(0x00B2); // type: Unconnected Data
    buf.put_u16_le(cip_data.len() as u16);
    buf.put_slice(cip_data);

    buf
}

/// Build a SendUnitData request wrapping a CIP message (connected messaging).
pub fn build_send_unit_data(session_handle: u32, connection_id: u32, sequence: u16, cip_data: &[u8]) -> BytesMut {
    let cpf_overhead = 16; // interface(4) + timeout(2) + count(2) + item1(8) + item2_header(4)
    let data_len = cpf_overhead + cip_data.len();

    let mut buf = BytesMut::with_capacity(ENCAP_HEADER_SIZE + data_len);
    let header = EncapHeader {
        command: Command::SendUnitData as u16,
        length: data_len as u16,
        session_handle,
        status: 0,
        sender_context: [0; 8],
        options: 0,
    };
    header.encode(&mut buf);

    // Common Packet Format
    buf.put_u32_le(0); // interface handle
    buf.put_u16_le(0); // timeout (0 for connected)
    buf.put_u16_le(2); // item count

    // Item 1: Connected Address (OT connection ID)
    buf.put_u16_le(0x00A1); // type: Connected Address
    buf.put_u16_le(4);      // length
    buf.put_u32_le(connection_id);

    // Item 2: Connected Data
    buf.put_u16_le(0x00B1); // type: Connected Data
    buf.put_u16_le((cip_data.len() + 2) as u16); // +2 for sequence count
    buf.put_u16_le(sequence);
    buf.put_slice(cip_data);

    buf
}

/// Parse a SendRRData response, returning the CIP data payload.
pub fn parse_send_rr_data_response(data: &[u8]) -> Option<Vec<u8>> {
    let mut buf = data;

    if buf.remaining() < 16 {
        return None;
    }

    let _interface_handle = buf.get_u32_le();
    let _timeout = buf.get_u16_le();
    let item_count = buf.get_u16_le();

    if item_count < 2 {
        return None;
    }

    // Item 1: skip (Null Address)
    if buf.remaining() < 4 { return None; }
    let _type1 = buf.get_u16_le();
    let len1 = buf.get_u16_le();
    if buf.remaining() < len1 as usize { return None; }
    buf.advance(len1 as usize);

    // Item 2: Unconnected Data
    if buf.remaining() < 4 { return None; }
    let _type2 = buf.get_u16_le();
    let len2 = buf.get_u16_le();
    if buf.remaining() < len2 as usize { return None; }

    let cip_data = buf[..len2 as usize].to_vec();
    Some(cip_data)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn register_session_encoding() {
        let msg = build_register_session();
        assert_eq!(msg.len(), ENCAP_HEADER_SIZE + 4);

        let mut slice = &msg[..];
        let header = EncapHeader::decode(&mut slice).unwrap();
        assert_eq!(header.command, Command::RegisterSession as u16);
        assert_eq!(header.length, 4);
        assert_eq!(header.session_handle, 0);

        // Data payload
        assert_eq!(slice.get_u16_le(), 1); // protocol version
        assert_eq!(slice.get_u16_le(), 0); // options
    }

    #[test]
    fn send_rr_data_encoding() {
        let cip_data = vec![0x4C, 0x02, 0x91, 0x05]; // sample CIP read tag
        let msg = build_send_rr_data(0x12345678, &cip_data);

        let mut slice = &msg[..];
        let header = EncapHeader::decode(&mut slice).unwrap();
        assert_eq!(header.command, Command::SendRRData as u16);
        assert_eq!(header.session_handle, 0x12345678);

        // CPF
        let _interface = slice.get_u32_le();
        let _timeout = slice.get_u16_le();
        let item_count = slice.get_u16_le();
        assert_eq!(item_count, 2);

        // Item 1: Null Address
        let type1 = slice.get_u16_le();
        let len1 = slice.get_u16_le();
        assert_eq!(type1, 0x0000);
        assert_eq!(len1, 0);

        // Item 2: Unconnected Data
        let type2 = slice.get_u16_le();
        let len2 = slice.get_u16_le();
        assert_eq!(type2, 0x00B2);
        assert_eq!(len2, 4);
    }

    #[test]
    fn unregister_session_encoding() {
        let msg = build_unregister_session(0xABCD);
        assert_eq!(msg.len(), ENCAP_HEADER_SIZE);

        let mut slice = &msg[..];
        let header = EncapHeader::decode(&mut slice).unwrap();
        assert_eq!(header.command, Command::UnregisterSession as u16);
        assert_eq!(header.session_handle, 0xABCD);
        assert_eq!(header.length, 0);
    }
}
