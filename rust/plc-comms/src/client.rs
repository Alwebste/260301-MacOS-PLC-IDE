//! Async EtherNet/IP client for Allen-Bradley PLC communication.
//!
//! Handles TCP connection, session management, and CIP message exchange.

use bytes::Buf;
use std::sync::atomic::{AtomicU16, Ordering};
use std::sync::Arc;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpStream;
use tokio::sync::Mutex;

use crate::cip::{self, CipResponse};
use crate::eip::{self, EncapHeader, ENCAP_HEADER_SIZE, EIP_TCP_PORT};
use crate::tags::TagValue;

/// Connection state for the EtherNet/IP client.
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum ConnectionState {
    Disconnected,
    Connecting,
    /// Session registered (unconnected messaging available)
    Registered,
    /// CIP connection established (connected messaging available)
    Connected,
    Error,
}

/// Configuration for connecting to a PLC.
#[derive(Debug, Clone)]
pub struct PlcConfig {
    /// PLC IP address
    pub ip_address: String,
    /// TCP port (default 44818)
    pub port: u16,
    /// Slot number for ControlLogix (0 for CompactLogix)
    pub slot: u8,
    /// Connection timeout in milliseconds
    pub timeout_ms: u64,
}

impl Default for PlcConfig {
    fn default() -> Self {
        Self {
            ip_address: "192.168.1.1".into(),
            port: EIP_TCP_PORT,
            slot: 0,
            timeout_ms: 5000,
        }
    }
}

/// Async EtherNet/IP client for communicating with AB PLCs.
pub struct EipClient {
    config: PlcConfig,
    stream: Option<Arc<Mutex<TcpStream>>>,
    session_handle: u32,
    state: ConnectionState,
    sequence: AtomicU16,
    /// O->T connection ID (assigned by us)
    ot_connection_id: u32,
    /// T->O connection ID (assigned by PLC)
    to_connection_id: u32,
    connection_serial: u16,
}

impl EipClient {
    /// Create a new client with the given configuration.
    pub fn new(config: PlcConfig) -> Self {
        Self {
            config,
            stream: None,
            session_handle: 0,
            state: ConnectionState::Disconnected,
            sequence: AtomicU16::new(1),
            ot_connection_id: 0,
            to_connection_id: 0,
            connection_serial: 0,
        }
    }

    /// Get the current connection state.
    pub fn state(&self) -> ConnectionState {
        self.state
    }

    /// Connect to the PLC and register an EtherNet/IP session.
    pub async fn connect(&mut self) -> Result<(), CommError> {
        self.state = ConnectionState::Connecting;

        // TCP connect
        let addr = format!("{}:{}", self.config.ip_address, self.config.port);
        let stream = tokio::time::timeout(
            std::time::Duration::from_millis(self.config.timeout_ms),
            TcpStream::connect(&addr),
        )
        .await
        .map_err(|_| CommError::Timeout)?
        .map_err(|e| CommError::TcpConnect(e.to_string()))?;

        stream
            .set_nodelay(true)
            .map_err(|e| CommError::TcpConnect(e.to_string()))?;

        self.stream = Some(Arc::new(Mutex::new(stream)));

        // Register session
        self.register_session().await?;
        self.state = ConnectionState::Registered;
        Ok(())
    }

    /// Register an EtherNet/IP session.
    async fn register_session(&mut self) -> Result<(), CommError> {
        let request = eip::build_register_session();
        let response = self.send_receive(&request).await?;

        let mut slice = &response[..];
        let header = EncapHeader::decode(&mut slice).ok_or(CommError::InvalidResponse)?;

        if header.status != 0 {
            return Err(CommError::SessionRegistration(header.status));
        }

        self.session_handle = header.session_handle;
        Ok(())
    }

    /// Disconnect from the PLC.
    pub async fn disconnect(&mut self) -> Result<(), CommError> {
        if self.state == ConnectionState::Connected {
            // Close CIP connection first
            let _ = self.forward_close().await;
        }

        if self.session_handle != 0 {
            let request = eip::build_unregister_session(self.session_handle);
            let stream = self.stream.as_ref().ok_or(CommError::NotConnected)?;
            let mut stream = stream.lock().await;
            let _ = stream.write_all(&request).await;
        }

        self.stream = None;
        self.session_handle = 0;
        self.state = ConnectionState::Disconnected;
        Ok(())
    }

    /// Establish a CIP connection (Forward Open) for connected messaging.
    ///
    /// Connected messaging is faster for repeated tag reads but requires setup.
    /// For occasional reads, unconnected messaging (read_tag) works fine.
    pub async fn forward_open(&mut self) -> Result<(), CommError> {
        if self.state != ConnectionState::Registered {
            return Err(CommError::NotConnected);
        }

        self.ot_connection_id = rand_u32();
        self.connection_serial = rand_u16();
        let to_connection_id = rand_u32();

        let cip_msg = cip::build_forward_open(
            self.ot_connection_id,
            to_connection_id,
            self.connection_serial,
            self.config.slot,
            10_000, // 10ms RPI
        );

        let request = eip::build_send_rr_data(self.session_handle, &cip_msg);
        let response = self.send_receive(&request).await?;

        let mut slice = &response[..];
        let header = EncapHeader::decode(&mut slice).ok_or(CommError::InvalidResponse)?;
        if header.status != 0 {
            return Err(CommError::EipError(header.status));
        }

        let cip_data =
            eip::parse_send_rr_data_response(slice).ok_or(CommError::InvalidResponse)?;
        let cip_resp = CipResponse::parse(&cip_data).ok_or(CommError::InvalidResponse)?;

        if !cip_resp.is_success() {
            return Err(CommError::CipError {
                status: cip_resp.status,
                extended: cip_resp.additional_status.first().copied().unwrap_or(0),
            });
        }

        // Parse Forward Open response: first 4 bytes = O->T connection ID, next 4 = T->O
        if cip_resp.data.len() >= 8 {
            self.ot_connection_id =
                u32::from_le_bytes(cip_resp.data[0..4].try_into().unwrap());
            self.to_connection_id =
                u32::from_le_bytes(cip_resp.data[4..8].try_into().unwrap());
        }

        self.state = ConnectionState::Connected;
        Ok(())
    }

    /// Close the CIP connection (Forward Close).
    pub async fn forward_close(&mut self) -> Result<(), CommError> {
        let cip_msg = cip::build_forward_close(self.connection_serial, self.config.slot);
        let request = eip::build_send_rr_data(self.session_handle, &cip_msg);
        let _ = self.send_receive(&request).await;

        self.state = ConnectionState::Registered;
        self.ot_connection_id = 0;
        self.to_connection_id = 0;
        Ok(())
    }

    /// Read a single tag by name. Returns the decoded value.
    ///
    /// Uses unconnected messaging (SendRRData).
    pub async fn read_tag(&self, tag_name: &str) -> Result<TagValue, CommError> {
        let cip_msg = cip::build_read_tag(tag_name, 1);
        let cip_resp = self.send_cip_unconnected(&cip_msg).await?;

        if !cip_resp.is_success() {
            return Err(CommError::CipError {
                status: cip_resp.status,
                extended: cip_resp.additional_status.first().copied().unwrap_or(0),
            });
        }

        TagValue::from_cip_response(&cip_resp.data).ok_or(CommError::InvalidResponse)
    }

    /// Write a value to a tag by name.
    pub async fn write_tag(&self, tag_name: &str, value: &TagValue) -> Result<(), CommError> {
        let cip_msg =
            cip::build_write_tag(tag_name, value.cip_type(), &value.to_cip_bytes());
        let cip_resp = self.send_cip_unconnected(&cip_msg).await?;

        if !cip_resp.is_success() {
            return Err(CommError::CipError {
                status: cip_resp.status,
                extended: cip_resp.additional_status.first().copied().unwrap_or(0),
            });
        }
        Ok(())
    }

    /// Read multiple tags in a single request using Multiple Service Packet.
    pub async fn read_tags(&self, tag_names: &[&str]) -> Result<Vec<Result<TagValue, CommError>>, CommError> {
        let services: Vec<Vec<u8>> = tag_names
            .iter()
            .map(|name| cip::build_read_tag(name, 1))
            .collect();

        let cip_msg = cip::build_multiple_service_packet(&services);
        let cip_resp = self.send_cip_unconnected(&cip_msg).await?;

        if !cip_resp.is_success() && cip_resp.status != cip::status::PARTIAL_TRANSFER {
            return Err(CommError::CipError {
                status: cip_resp.status,
                extended: cip_resp.additional_status.first().copied().unwrap_or(0),
            });
        }

        // Parse Multiple Service response
        parse_multiple_service_response(&cip_resp.data, tag_names.len())
    }

    /// Read a tag using connected messaging (requires forward_open first).
    pub async fn read_tag_connected(&self, tag_name: &str) -> Result<TagValue, CommError> {
        if self.state != ConnectionState::Connected {
            return Err(CommError::NotConnected);
        }

        let cip_msg = cip::build_read_tag(tag_name, 1);
        let seq = self.sequence.fetch_add(1, Ordering::Relaxed);

        let request = eip::build_send_unit_data(
            self.session_handle,
            self.ot_connection_id,
            seq,
            &cip_msg,
        );

        let response = self.send_receive(&request).await?;
        let mut slice = &response[..];
        let header = EncapHeader::decode(&mut slice).ok_or(CommError::InvalidResponse)?;
        if header.status != 0 {
            return Err(CommError::EipError(header.status));
        }

        // Parse SendUnitData CPF: skip interface(4) + timeout(2) + count(2)
        if slice.remaining() < 8 {
            return Err(CommError::InvalidResponse);
        }
        let _ = slice.get_u32_le(); // interface
        let _ = slice.get_u16_le(); // timeout
        let item_count = slice.get_u16_le();
        if item_count < 2 {
            return Err(CommError::InvalidResponse);
        }

        // Skip item 1 (Connected Address)
        if slice.remaining() < 4 {
            return Err(CommError::InvalidResponse);
        }
        let _ = slice.get_u16_le(); // type
        let len1 = slice.get_u16_le();
        if slice.remaining() < len1 as usize {
            return Err(CommError::InvalidResponse);
        }
        slice.advance(len1 as usize);

        // Item 2 (Connected Data)
        if slice.remaining() < 4 {
            return Err(CommError::InvalidResponse);
        }
        let _ = slice.get_u16_le(); // type
        let len2 = slice.get_u16_le();
        if slice.remaining() < len2 as usize {
            return Err(CommError::InvalidResponse);
        }
        // Skip sequence count (2 bytes)
        let _ = slice.get_u16_le();

        let cip_data = &slice[..len2 as usize - 2];
        let cip_resp = CipResponse::parse(cip_data).ok_or(CommError::InvalidResponse)?;

        if !cip_resp.is_success() {
            return Err(CommError::CipError {
                status: cip_resp.status,
                extended: cip_resp.additional_status.first().copied().unwrap_or(0),
            });
        }

        TagValue::from_cip_response(&cip_resp.data).ok_or(CommError::InvalidResponse)
    }

    /// Send a CIP message using unconnected messaging and return the CIP response.
    async fn send_cip_unconnected(&self, cip_data: &[u8]) -> Result<CipResponse, CommError> {
        let request = eip::build_send_rr_data(self.session_handle, cip_data);
        let response = self.send_receive(&request).await?;

        let mut slice = &response[..];
        let header = EncapHeader::decode(&mut slice).ok_or(CommError::InvalidResponse)?;

        if header.status != 0 {
            return Err(CommError::EipError(header.status));
        }

        let cip_payload =
            eip::parse_send_rr_data_response(slice).ok_or(CommError::InvalidResponse)?;
        CipResponse::parse(&cip_payload).ok_or(CommError::InvalidResponse)
    }

    /// Low-level send/receive: send bytes and read back the full EtherNet/IP response.
    async fn send_receive(&self, data: &[u8]) -> Result<Vec<u8>, CommError> {
        let stream = self.stream.as_ref().ok_or(CommError::NotConnected)?;
        let mut stream = stream.lock().await;

        // Send
        stream
            .write_all(data)
            .await
            .map_err(|e| CommError::IoError(e.to_string()))?;

        // Read header
        let mut header_buf = [0u8; ENCAP_HEADER_SIZE];
        stream
            .read_exact(&mut header_buf)
            .await
            .map_err(|e| CommError::IoError(e.to_string()))?;

        // Parse data length from header (bytes 2-3)
        let data_len = u16::from_le_bytes([header_buf[2], header_buf[3]]) as usize;

        // Read data
        let mut full_response = Vec::with_capacity(ENCAP_HEADER_SIZE + data_len);
        full_response.extend_from_slice(&header_buf);

        if data_len > 0 {
            let mut data_buf = vec![0u8; data_len];
            stream
                .read_exact(&mut data_buf)
                .await
                .map_err(|e| CommError::IoError(e.to_string()))?;
            full_response.extend_from_slice(&data_buf);
        }

        Ok(full_response)
    }
}

/// Parse a Multiple Service Packet response into individual tag values.
fn parse_multiple_service_response(
    data: &[u8],
    expected_count: usize,
) -> Result<Vec<Result<TagValue, CommError>>, CommError> {
    if data.len() < 2 {
        return Err(CommError::InvalidResponse);
    }

    let count = u16::from_le_bytes([data[0], data[1]]) as usize;
    if count != expected_count || data.len() < 2 + count * 2 {
        return Err(CommError::InvalidResponse);
    }

    // Read offset table
    let mut offsets = Vec::with_capacity(count);
    for i in 0..count {
        let off = u16::from_le_bytes([data[2 + i * 2], data[3 + i * 2]]) as usize;
        offsets.push(off);
    }

    let service_data_start = 2 + count * 2;
    let mut results = Vec::with_capacity(count);

    for i in 0..count {
        let start = service_data_start + offsets[i];
        let end = if i + 1 < count {
            service_data_start + offsets[i + 1]
        } else {
            data.len()
        };

        if start >= data.len() || end > data.len() {
            results.push(Err(CommError::InvalidResponse));
            continue;
        }

        let svc_data = &data[start..end];
        match CipResponse::parse(svc_data) {
            Some(resp) if resp.is_success() => {
                match TagValue::from_cip_response(&resp.data) {
                    Some(val) => results.push(Ok(val)),
                    None => results.push(Err(CommError::InvalidResponse)),
                }
            }
            Some(resp) => {
                results.push(Err(CommError::CipError {
                    status: resp.status,
                    extended: resp.additional_status.first().copied().unwrap_or(0),
                }));
            }
            None => results.push(Err(CommError::InvalidResponse)),
        }
    }

    Ok(results)
}

/// Communication errors.
#[derive(Debug, Clone)]
pub enum CommError {
    /// TCP connection failed
    TcpConnect(String),
    /// Connection timeout
    Timeout,
    /// Not connected to PLC
    NotConnected,
    /// Session registration failed
    SessionRegistration(u32),
    /// EtherNet/IP error status
    EipError(u32),
    /// CIP service error
    CipError { status: u8, extended: u16 },
    /// Invalid or unexpected response
    InvalidResponse,
    /// I/O error
    IoError(String),
}

impl std::fmt::Display for CommError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CommError::TcpConnect(e) => write!(f, "TCP connection failed: {}", e),
            CommError::Timeout => write!(f, "Connection timed out"),
            CommError::NotConnected => write!(f, "Not connected to PLC"),
            CommError::SessionRegistration(s) => write!(f, "Session registration failed (status: 0x{:08X})", s),
            CommError::EipError(s) => write!(f, "EtherNet/IP error (status: 0x{:08X})", s),
            CommError::CipError { status, extended } => {
                write!(f, "CIP error (status: 0x{:02X}, extended: 0x{:04X})", status, extended)
            }
            CommError::InvalidResponse => write!(f, "Invalid response from PLC"),
            CommError::IoError(e) => write!(f, "I/O error: {}", e),
        }
    }
}

impl std::error::Error for CommError {}

/// Simple pseudo-random u32 (not crypto-secure, fine for connection IDs).
fn rand_u32() -> u32 {
    use std::time::SystemTime;
    let t = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap_or_default();
    (t.as_nanos() as u32) ^ 0xDEAD_BEEF
}

fn rand_u16() -> u16 {
    (rand_u32() & 0xFFFF) as u16
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn default_config() {
        let cfg = PlcConfig::default();
        assert_eq!(cfg.port, 44818);
        assert_eq!(cfg.slot, 0);
    }

    #[test]
    fn client_initial_state() {
        let client = EipClient::new(PlcConfig::default());
        assert_eq!(client.state(), ConnectionState::Disconnected);
    }

    #[test]
    fn comm_error_display() {
        let e = CommError::CipError {
            status: 0x04,
            extended: 0x0000,
        };
        assert!(e.to_string().contains("CIP error"));
        assert!(e.to_string().contains("0x04"));
    }

    #[test]
    fn parse_multiple_service_response_two_dints() {
        // Simulate a Multiple Service response with 2 DINT values
        let mut data = Vec::new();

        // Service count
        data.extend_from_slice(&2u16.to_le_bytes());

        // Offset table (relative to after offset table)
        // Each CIP response: service(1) + reserved(1) + status(1) + addl_size(1) + type(2) + value(4) = 10 bytes
        data.extend_from_slice(&0u16.to_le_bytes());  // offset to first service
        data.extend_from_slice(&10u16.to_le_bytes()); // offset to second service

        // Service 1 response: ReadTag reply, success, DINT = 42
        data.push(0xCC); // service | 0x80
        data.push(0x00); // reserved
        data.push(0x00); // status = success
        data.push(0x00); // additional status size
        data.extend_from_slice(&0x00C4u16.to_le_bytes()); // DINT type
        data.extend_from_slice(&42i32.to_le_bytes());     // value

        // Service 2 response: ReadTag reply, success, DINT = 99
        data.push(0xCC);
        data.push(0x00);
        data.push(0x00);
        data.push(0x00);
        data.extend_from_slice(&0x00C4u16.to_le_bytes());
        data.extend_from_slice(&99i32.to_le_bytes());

        let results = parse_multiple_service_response(&data, 2).unwrap();
        assert_eq!(results.len(), 2);
        assert_eq!(results[0].as_ref().unwrap(), &TagValue::Dint(42));
        assert_eq!(results[1].as_ref().unwrap(), &TagValue::Dint(99));
    }
}
