use std::net::Ipv4Addr;

use octets::{Octets, OctetsMut};
use quiche::h3;
use rand::RngExt;
use tokio::sync::mpsc;

use crate::consts;
use crate::error::{OryvexCoreError, Result};

pub const CAPSULE_ADDRESS_ASSIGN: u64 = 0x01;
pub const CAPSULE_ADDRESS_REQUEST: u64 = 0x02;
pub const CAPSULE_ROUTE_ADVERTISEMENT: u64 = 0x03;
pub const CAPSULE_DATAGRAM: u64 = 0x00;

#[derive(Debug, Clone)]
pub struct AssignedAddress {
    pub request_id: u64,
    pub ip_version: u8,
    pub address: Vec<u8>,
    pub prefix_len: u8,
}

#[derive(Debug, Clone)]
pub struct RouteAdvertisement {
    pub ip_version: u8,
    pub start: Vec<u8>,
    pub end: Vec<u8>,
    pub protocol: u8,
}

#[derive(Debug, Clone)]
pub enum Capsule {
    AddressAssign(Vec<AssignedAddress>),
    AddressRequest,
    Datagram(Vec<u8>),
    RouteAdvertisement(Vec<RouteAdvertisement>),
    Unknown { kind: u64, payload: Vec<u8> },
}

pub fn connect_ip_request(authority: &str, path: &str) -> Vec<h3::Header> {
    vec![
        h3::Header::new(b":method", b"CONNECT"),
        h3::Header::new(b":protocol", consts::CF_CONNECT_PROTOCOL.as_bytes()),
        h3::Header::new(b":scheme", b"https"),
        h3::Header::new(b":authority", authority.as_bytes()),
        h3::Header::new(b":path", path.as_bytes()),
        h3::Header::new(b"user-agent", b""),
        h3::Header::new(b"capsule-protocol", b"?1"),
    ]
}

pub fn quarter_stream_id(stream_id: u64) -> u64 {
    stream_id / 4
}

pub fn encode_ip_datagram(stream_id: u64, ip_packet: &[u8]) -> Result<Vec<u8>> {
    let qsid = quarter_stream_id(stream_id);
    let ctx = consts::CONNECT_IP_CONTEXT_ID;

    let cap = varint_len(qsid) + varint_len(ctx) + ip_packet.len();
    let mut out = vec![0u8; cap];

    {
        let mut b = OctetsMut::with_slice(&mut out);
        b.put_varint(qsid).map_err(oct)?;
        b.put_varint(ctx).map_err(oct)?;
        b.put_bytes(ip_packet).map_err(oct)?;
    }

    Ok(out)
}

pub fn decode_ip_datagram(datagram: &[u8], expect_stream_id: u64) -> Result<Option<Vec<u8>>> {
    let mut b = Octets::with_slice(datagram);

    let qsid = b.get_varint().map_err(oct)?;
    if qsid != quarter_stream_id(expect_stream_id) {
        return Ok(None);
    }

    let ctx = b.get_varint().map_err(oct)?;
    if ctx != consts::CONNECT_IP_CONTEXT_ID {
        return Ok(None);
    }

    let rest = b.cap();
    let payload = b.get_bytes(rest).map_err(oct)?;
    Ok(Some(payload.to_vec()))
}

pub fn encode_capsule(kind: u64, value: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(capsule_len(kind, value));
    append_capsule(&mut out, kind, value);
    out
}

fn capsule_len(kind: u64, value: &[u8]) -> usize {
    varint_len(kind) + varint_len(value.len() as u64) + value.len()
}

/// Writes a capsule onto the end of `out` instead of into a buffer of its own,
/// so a caller with several packets in hand can put them all in one frame.
pub fn append_capsule(out: &mut Vec<u8>, kind: u64, value: &[u8]) {
    let start = out.len();
    out.resize(start + capsule_len(kind, value), 0);

    let mut b = OctetsMut::with_slice(&mut out[start..]);
    let _ = b.put_varint(kind);
    let _ = b.put_varint(value.len() as u64);
    let _ = b.put_bytes(value);
}

pub fn encode_address_request(request_id: u64, ip_version: u8, prefix_len: u8) -> Vec<u8> {
    let value_len = varint_len(request_id) + 1 + 1;
    let mut value = vec![0u8; value_len];
    {
        let mut b = OctetsMut::with_slice(&mut value);
        let _ = b.put_varint(request_id);
        let _ = b.put_u8(ip_version);
        let _ = b.put_u8(prefix_len);
    }
    encode_capsule(CAPSULE_ADDRESS_REQUEST, &value)
}

pub fn encode_datagram_capsule(ip_packet: &[u8]) -> Vec<u8> {
    encode_capsule(CAPSULE_DATAGRAM, ip_packet)
}

pub fn append_datagram_capsule(out: &mut Vec<u8>, ip_packet: &[u8]) {
    append_capsule(out, CAPSULE_DATAGRAM, ip_packet)
}

pub fn strip_datagram_context(payload: &[u8]) -> Option<Vec<u8>> {
    if payload.is_empty() {
        return None;
    }

    let mut b = Octets::with_slice(payload);
    if let Ok(ctx) = b.get_varint() {
        if ctx == consts::CONNECT_IP_CONTEXT_ID {
            let rest = b.cap();
            let consumed = payload.len() - rest;
            let inner = &payload[consumed..];
            if looks_like_ip_packet(inner) {
                return Some(inner.to_vec());
            }
        }
    }

    if looks_like_ip_packet(payload) {
        return Some(payload.to_vec());
    }

    None
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InboundQueueResult {
    Enqueued,
    Full,
    Closed,
}

pub(crate) fn enqueue_inbound_packet(
    sender: &mpsc::Sender<Vec<u8>>,
    packet: Vec<u8>,
) -> InboundQueueResult {
    match sender.try_send(packet) {
        Ok(()) => InboundQueueResult::Enqueued,
        Err(mpsc::error::TrySendError::Full(_)) => InboundQueueResult::Full,
        Err(mpsc::error::TrySendError::Closed(_)) => InboundQueueResult::Closed,
    }
}

#[derive(Debug, PartialEq, Eq)]
struct DnsQuestion {
    id: u16,
    opcode: u16,
    name: Vec<u8>,
    qtype: u16,
    qclass: u16,
}

struct Ipv4UdpPacket<'a> {
    source: [u8; 4],
    destination: [u8; 4],
    source_port: u16,
    destination_port: u16,
    payload: &'a [u8],
}

fn ipv4_udp_packet(packet: &[u8]) -> Option<Ipv4UdpPacket<'_>> {
    if packet.len() < 20 || packet[0] >> 4 != 4 || packet[9] != 17 {
        return None;
    }
    let header_len = ((packet[0] & 0x0f) as usize).checked_mul(4)?;
    if header_len < 20 || header_len > packet.len() {
        return None;
    }
    let total_len = u16::from_be_bytes(packet.get(2..4)?.try_into().ok()?) as usize;
    if total_len < header_len + 8 || total_len > packet.len() {
        return None;
    }
    let fragment = u16::from_be_bytes(packet.get(6..8)?.try_into().ok()?);
    if fragment & 0x3fff != 0 {
        return None;
    }

    let udp = packet.get(header_len..total_len)?;
    let udp_len = u16::from_be_bytes(udp.get(4..6)?.try_into().ok()?) as usize;
    if udp_len < 8 || udp_len != udp.len() {
        return None;
    }

    Some(Ipv4UdpPacket {
        source: packet.get(12..16)?.try_into().ok()?,
        destination: packet.get(16..20)?.try_into().ok()?,
        source_port: u16::from_be_bytes(udp.get(0..2)?.try_into().ok()?),
        destination_port: u16::from_be_bytes(udp.get(2..4)?.try_into().ok()?),
        payload: udp.get(8..)?,
    })
}

fn dns_name(message: &[u8], start: usize) -> Option<(Vec<u8>, usize)> {
    let mut name = Vec::new();
    let mut position = start;
    let mut consumed = None;

    for _ in 0..128 {
        let length = *message.get(position)?;
        if length & 0xc0 == 0xc0 {
            let second = *message.get(position + 1)?;
            let pointer = (((length & 0x3f) as usize) << 8) | second as usize;
            if pointer >= message.len() {
                return None;
            }
            consumed.get_or_insert(position + 2);
            position = pointer;
            continue;
        }
        if length & 0xc0 != 0 {
            return None;
        }
        position += 1;
        if length == 0 {
            return Some((name, consumed.unwrap_or(position)));
        }

        let label_len = length as usize;
        let label = message.get(position..position.checked_add(label_len)?)?;
        name.push(length);
        name.extend(label.iter().map(u8::to_ascii_lowercase));
        position += label_len;
    }

    None
}

fn dns_question(message: &[u8], expect_response: bool) -> Option<DnsQuestion> {
    if message.len() < 12 {
        return None;
    }
    let flags = u16::from_be_bytes(message.get(2..4)?.try_into().ok()?);
    if (flags & 0x8000 != 0) != expect_response
        || u16::from_be_bytes(message.get(4..6)?.try_into().ok()?) != 1
    {
        return None;
    }

    let (name, end) = dns_name(message, 12)?;
    let qtype = u16::from_be_bytes(message.get(end..end.checked_add(2)?)?.try_into().ok()?);
    let qclass = u16::from_be_bytes(message.get(end + 2..end + 4)?.try_into().ok()?);
    Some(DnsQuestion {
        id: u16::from_be_bytes(message.get(0..2)?.try_into().ok()?),
        opcode: flags & 0x7800,
        name,
        qtype,
        qclass,
    })
}

/// True only when a DNS response matches the probe's IPv4/UDP endpoints and DNS question.
/// Header fields that legitimately vary in a response (TTL, IP ID, checksums and DNS flags) are
/// deliberately not compared byte-for-byte.
pub(crate) fn is_correlated_dns_probe_response(probe: &[u8], response: &[u8]) -> bool {
    let (Some(query_packet), Some(response_packet)) =
        (ipv4_udp_packet(probe), ipv4_udp_packet(response))
    else {
        return false;
    };
    if response_packet.source != query_packet.destination
        || response_packet.destination != query_packet.source
        || response_packet.source_port != query_packet.destination_port
        || response_packet.destination_port != query_packet.source_port
    {
        return false;
    }

    let (Some(query), Some(answer)) = (
        dns_question(query_packet.payload, false),
        dns_question(response_packet.payload, true),
    ) else {
        return false;
    };
    query.id == answer.id
        && query.opcode == answer.opcode
        && query.name == answer.name
        && query.qtype == answer.qtype
        && query.qclass == answer.qclass
}

fn looks_like_ip_packet(data: &[u8]) -> bool {
    match data.first() {
        Some(first) => matches!(first >> 4, 4 | 6) && data.len() >= 20,
        None => false,
    }
}

pub struct CapsuleParser {
    buf: Vec<u8>,
}

const MAX_CAPSULE_BUF: usize = 256 * 1024;

impl CapsuleParser {
    pub fn new() -> Self {
        Self { buf: Vec::new() }
    }

    pub fn push(&mut self, data: &[u8]) {
        if self.buf.len().saturating_add(data.len()) > MAX_CAPSULE_BUF {
            log::warn!("capsule parser buffer exceeded {MAX_CAPSULE_BUF} bytes; resetting");
            self.buf.clear();
            return;
        }
        self.buf.extend_from_slice(data);
    }

    pub fn next(&mut self) -> Result<Option<Capsule>> {
        let mut b = Octets::with_slice(&self.buf);

        let kind = match b.get_varint() {
            Ok(v) => v,
            Err(_) => return Ok(None),
        };
        let len = match b.get_varint() {
            Ok(v) => v as usize,
            Err(_) => return Ok(None),
        };
        if b.cap() < len {
            return Ok(None);
        }

        let value = b.get_bytes(len).map_err(oct)?.to_vec();
        let consumed = b.off();
        self.buf.drain(0..consumed);

        let capsule = match kind {
            CAPSULE_ADDRESS_ASSIGN => Capsule::AddressAssign(parse_address_assign(&value)?),
            CAPSULE_ADDRESS_REQUEST => Capsule::AddressRequest,
            CAPSULE_ROUTE_ADVERTISEMENT => {
                Capsule::RouteAdvertisement(parse_route_advertisement(&value)?)
            }
            CAPSULE_DATAGRAM => Capsule::Datagram(value),
            other => Capsule::Unknown {
                kind: other,
                payload: value,
            },
        };

        Ok(Some(capsule))
    }
}

impl Default for CapsuleParser {
    fn default() -> Self {
        Self::new()
    }
}

fn parse_address_assign(value: &[u8]) -> Result<Vec<AssignedAddress>> {
    let mut b = Octets::with_slice(value);
    let mut out = Vec::new();

    while b.cap() > 0 {
        let request_id = b.get_varint().map_err(oct)?;
        let ip_version = b.get_u8().map_err(oct)?;
        let addr_len = match ip_version {
            4 => 4,
            6 => 16,
            _ => return Err(OryvexCoreError::Capsule(format!("bad ip version {ip_version}"))),
        };
        let address = b.get_bytes(addr_len).map_err(oct)?.to_vec();
        let prefix_len = b.get_u8().map_err(oct)?;

        out.push(AssignedAddress {
            request_id,
            ip_version,
            address,
            prefix_len,
        });
    }

    Ok(out)
}

fn parse_route_advertisement(value: &[u8]) -> Result<Vec<RouteAdvertisement>> {
    let mut b = Octets::with_slice(value);
    let mut out = Vec::new();

    while b.cap() > 0 {
        let ip_version = b.get_u8().map_err(oct)?;
        let addr_len = match ip_version {
            4 => 4,
            6 => 16,
            _ => return Err(OryvexCoreError::Capsule(format!("bad ip version {ip_version}"))),
        };
        let start = b.get_bytes(addr_len).map_err(oct)?.to_vec();
        let end = b.get_bytes(addr_len).map_err(oct)?.to_vec();
        let protocol = b.get_u8().map_err(oct)?;

        out.push(RouteAdvertisement {
            ip_version,
            start,
            end,
            protocol,
        });
    }

    Ok(out)
}

fn varint_len(v: u64) -> usize {
    if v < 64 {
        1
    } else if v < 16384 {
        2
    } else if v < 1_073_741_824 {
        4
    } else {
        8
    }
}

fn oct(e: octets::BufferTooShortError) -> OryvexCoreError {
    OryvexCoreError::Capsule(e.to_string())
}

pub fn build_dns_probe_packet(src: Ipv4Addr) -> Vec<u8> {
    let dns = probe_dns_query();
    let udp_len = 8 + dns.len();
    let total_len = 20 + udp_len;

    let mut pkt = Vec::with_capacity(total_len);

    pkt.push(0x45);
    pkt.push(0x00);
    pkt.extend_from_slice(&(total_len as u16).to_be_bytes());
    let id: u16 = rand::random();
    pkt.extend_from_slice(&id.to_be_bytes());
    pkt.extend_from_slice(&[0x00, 0x00]);
    pkt.push(64);
    pkt.push(17);
    pkt.extend_from_slice(&[0x00, 0x00]);
    pkt.extend_from_slice(&src.octets());
    pkt.extend_from_slice(&Ipv4Addr::new(8, 8, 8, 8).octets());
    let csum = ipv4_header_checksum(&pkt[0..20]);
    pkt[10..12].copy_from_slice(&csum.to_be_bytes());

    let sport: u16 = rand::rng().random_range(20000..60000);
    pkt.extend_from_slice(&sport.to_be_bytes());
    pkt.extend_from_slice(&53u16.to_be_bytes());
    pkt.extend_from_slice(&(udp_len as u16).to_be_bytes());
    pkt.extend_from_slice(&[0x00, 0x00]);

    pkt.extend_from_slice(&dns);
    pkt
}

fn probe_dns_query() -> Vec<u8> {
    let id: u16 = rand::random();
    let mut q = Vec::with_capacity(32);
    q.extend_from_slice(&id.to_be_bytes());
    q.extend_from_slice(&[0x01, 0x00]);
    q.extend_from_slice(&[0x00, 0x01]);
    q.extend_from_slice(&[0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
    for label in ["cloudflare", "com"] {
        q.push(label.len() as u8);
        q.extend_from_slice(label.as_bytes());
    }
    q.push(0x00);
    q.extend_from_slice(&[0x00, 0x01]);
    q.extend_from_slice(&[0x00, 0x01]);
    q
}

fn ipv4_header_checksum(header: &[u8]) -> u16 {
    let mut sum: u32 = 0;
    let mut i = 0;
    while i + 1 < header.len() {
        sum += u16::from_be_bytes([header[i], header[i + 1]]) as u32;
        i += 2;
    }
    if i < header.len() {
        sum += (header[i] as u32) << 8;
    }
    while (sum >> 16) != 0 {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    !(sum as u16)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dns_probe_response(probe: &[u8]) -> Vec<u8> {
        let mut response = probe.to_vec();
        let source = response[12..16].to_vec();
        let destination = response[16..20].to_vec();
        response[12..16].copy_from_slice(&destination);
        response[16..20].copy_from_slice(&source);

        let source_port = response[20..22].to_vec();
        let destination_port = response[22..24].to_vec();
        response[20..22].copy_from_slice(&destination_port);
        response[22..24].copy_from_slice(&source_port);

        let dns = 20 + 8;
        response[dns + 2..dns + 4].copy_from_slice(&0x8180u16.to_be_bytes());
        response
    }

    fn ip_packet() -> Vec<u8> {
        let mut pkt = vec![0u8; 24];
        pkt[0] = 0x45;
        pkt[9] = 17;
        pkt[12..16].copy_from_slice(&[198, 18, 0, 1]);
        pkt[16..20].copy_from_slice(&[1, 1, 1, 1]);
        pkt
    }

    fn capsule_value(capsule: &[u8]) -> Vec<u8> {
        let mut b = Octets::with_slice(capsule);
        assert_eq!(b.get_varint().unwrap(), CAPSULE_DATAGRAM);
        let length = b.get_varint().unwrap() as usize;
        b.get_bytes(length).unwrap().to_vec()
    }

    #[test]
    fn the_h2_capsule_carries_the_bare_packet_that_the_cloudflare_edge_expects() {
        let packet = ip_packet();
        assert_eq!(capsule_value(&encode_datagram_capsule(&packet)), packet);
    }

    #[test]
    fn several_packets_appended_in_a_row_stay_separable() {
        let first = ip_packet();
        let mut second = ip_packet();
        second[19] = 9;

        let mut batch = Vec::new();
        append_datagram_capsule(&mut batch, &first);
        append_datagram_capsule(&mut batch, &second);

        assert_eq!(
            batch,
            [
                encode_datagram_capsule(&first),
                encode_datagram_capsule(&second)
            ]
            .concat(),
            "appending has to lay the capsules down exactly as encoding each one would"
        );

        let mut parser = CapsuleParser::new();
        parser.push(&batch);

        let mut seen = Vec::new();
        while let Ok(Some(capsule)) = parser.next() {
            if let Capsule::Datagram(payload) = capsule {
                seen.push(strip_datagram_context(&payload).expect("an ip packet"));
            }
        }

        assert_eq!(
            seen,
            vec![first, second],
            "both packets should come back out"
        );
    }

    #[test]
    fn a_capsule_round_trips_through_the_receive_path() {
        let packet = ip_packet();
        let value = capsule_value(&encode_datagram_capsule(&packet));
        assert_eq!(strip_datagram_context(&value), Some(packet));
    }

    #[test]
    fn a_payload_that_does_carry_a_context_id_is_also_accepted() {
        let packet = ip_packet();
        let mut framed = vec![0u8];
        framed.extend_from_slice(&packet);
        assert_eq!(strip_datagram_context(&framed), Some(packet));
    }

    #[test]
    fn a_payload_that_is_not_an_ip_packet_is_rejected() {
        assert_eq!(strip_datagram_context(&[]), None);
        assert_eq!(strip_datagram_context(&[0x00, 0x01, 0x02]), None);
        assert_eq!(strip_datagram_context(&[0xff; 40]), None);
    }

    #[test]
    fn the_h3_path_still_carries_the_context_id() {
        let packet = ip_packet();
        let h3 = encode_ip_datagram(8, &packet).expect("h3 encoding");
        let decoded = decode_ip_datagram(&h3, 8)
            .expect("h3 decoding")
            .expect("payload");
        assert_eq!(decoded, packet);
    }

    #[test]
    fn inbound_queue_reports_only_successful_enqueues_as_delivered() {
        let (tx, mut rx) = mpsc::channel(1);
        assert_eq!(
            enqueue_inbound_packet(&tx, vec![1]),
            InboundQueueResult::Enqueued
        );
        assert_eq!(rx.try_recv().expect("queued packet"), vec![1]);

        let (tx, _rx) = mpsc::channel(1);
        tx.try_send(vec![0]).expect("fill queue");
        assert_eq!(
            enqueue_inbound_packet(&tx, vec![2]),
            InboundQueueResult::Full
        );

        let (tx, rx) = mpsc::channel(1);
        drop(rx);
        assert_eq!(
            enqueue_inbound_packet(&tx, vec![3]),
            InboundQueueResult::Closed
        );
    }

    #[test]
    fn probe_success_requires_matching_framing_endpoints_and_dns_correlation() {
        let probe = build_dns_probe_packet(Ipv4Addr::new(192, 0, 2, 2));
        let response = dns_probe_response(&probe);
        assert!(is_correlated_dns_probe_response(&probe, &response));

        let mut wrong_id = response.clone();
        wrong_id[28] ^= 0x01;
        assert!(!is_correlated_dns_probe_response(&probe, &wrong_id));

        let mut wrong_question = response.clone();
        wrong_question[41] ^= 0x01;
        assert!(!is_correlated_dns_probe_response(&probe, &wrong_question));

        let mut wrong_port = response.clone();
        wrong_port[22] ^= 0x01;
        assert!(!is_correlated_dns_probe_response(&probe, &wrong_port));

        let mut unrelated = response.clone();
        unrelated[9] = 6;
        assert!(!is_correlated_dns_probe_response(&probe, &unrelated));
    }

    #[test]
    fn probe_framing_rejects_unrelated_h3_and_h2_contexts() {
        let probe = build_dns_probe_packet(Ipv4Addr::new(192, 0, 2, 2));
        let response = dns_probe_response(&probe);
        let valid = encode_ip_datagram(8, &response).expect("h3 framing");
        let decoded = decode_ip_datagram(&valid, 8)
            .expect("decode")
            .expect("matching stream and context");
        assert!(is_correlated_dns_probe_response(&probe, &decoded));

        let wrong_stream = encode_ip_datagram(12, &response).expect("h3 framing");
        assert_eq!(decode_ip_datagram(&wrong_stream, 8).unwrap(), None);

        let wrong_context = [1u8].into_iter().chain(response).collect::<Vec<_>>();
        assert_eq!(strip_datagram_context(&wrong_context), None);
    }
}
