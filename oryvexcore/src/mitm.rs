//! The MITM route (domain fronting, on this device only). No tunnel, no account, no outside
//! server: oryvexcore itself is the proxy, and it does what the Xray "MITM-DomainFronting"
//! config of patterniha does, natively, so nothing has to be set up in v2ray.
//!
//! How it works, for a site on the list (Google/YouTube, Meta, Fastly-hosted sites):
//!   1. The app connects through the SOCKS5 / HTTP proxy asking for `www.youtube.com:443`.
//!   2. oryvexcore answers the TLS handshake itself, with a certificate for that name signed by
//!      a CA that was generated on THIS device (`oryvex-mitm-ca.crt`) and that you installed as
//!      trusted. The browser therefore hands over its request unencrypted to oryvexcore.
//!   3. oryvexcore opens a new TLS connection to the real server's address, but names a
//!      different, unblocked site in the handshake (the SNI, which is what a filter reads), for
//!      example `www.google.com`, and checks the certificate that comes back against the real
//!      name. The bytes are relayed between the two connections.
//!   4. Names are looked up through DNS-over-HTTPS to 1.1.1.1 that is itself fronted, so DNS
//!      poisoning does not matter.
//!
//! The CA key never leaves the device. Anything not on the list goes out directly, untouched.
//! What it does not do: it is not a tunnel (the address does not change), it only reaches
//! services whose edge accepts a different SNI, and apps that ignore user-installed CAs (most
//! non-browser apps on Android) cannot use it.

use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use base64::Engine;
use rand::Rng;
use boring::asn1::{Asn1Integer, Asn1Time};
use boring::bn::{BigNum, MsbOption};
use boring::ec::{EcGroup, EcKey};
use boring::hash::MessageDigest;
use boring::nid::Nid;
use boring::pkey::{PKey, Private};
use boring::ssl::{
    select_next_proto, AlpnError, NameType, SniError, SslAcceptor, SslConnector, SslMethod,
    SslRef, SslVerifyMode,
};
use boring::stack::Stack;
use boring::x509::extension::{BasicConstraints, ExtendedKeyUsage, KeyUsage, SubjectAlternativeName};
use boring::x509::store::{X509Store, X509StoreBuilder};
use boring::x509::{X509Name, X509StoreContext, X509};
use tokio::io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

use crate::error::{OryvexCoreError, Result};
use crate::stats;

pub const CA_CRT: &str = "oryvex-mitm-ca.crt";
pub const CA_DER: &str = "oryvex-mitm-ca.der";
const CA_KEY: &str = "oryvex-mitm-ca.key";

const IDLE: Duration = Duration::from_secs(300);
const DIAL_TIMEOUT: Duration = Duration::from_secs(8);
const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(12);
const DNS_TTL: Duration = Duration::from_secs(300);
const MAX_CLIENTS: usize = 1024;

const ROOTS_PEM: &str = include_str!("mitm_roots.pem");

fn tls_err(e: impl std::fmt::Display) -> OryvexCoreError {
    OryvexCoreError::Tls(e.to_string())
}

fn other(msg: impl Into<String>) -> OryvexCoreError {
    OryvexCoreError::Other(msg.into())
}

fn env_value(name: &str) -> Option<String> {
    std::env::var(name)
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

/// True when this run is the MITM route: `--mitm`, or `--protocol mitm`.
pub fn enabled() -> bool {
    if env_value("ORYVEXCORE_MITM")
        .map(|v| matches!(v.to_ascii_lowercase().as_str(), "1" | "true" | "yes" | "on"))
        .unwrap_or(false)
    {
        return true;
    }
    env_value("ORYVEXCORE_PROTOCOL")
        .map(|v| v.eq_ignore_ascii_case("mitm"))
        .unwrap_or(false)
}

/// Where the CA lives: `--mitm-dir`, else a folder beside the identity file.
pub fn state_dir(base_config: &str) -> PathBuf {
    if let Some(dir) = env_value("ORYVEXCORE_MITM_DIR") {
        return PathBuf::from(dir);
    }
    let config = PathBuf::from(base_config);
    let stem = config
        .file_stem()
        .map(|n| n.to_string_lossy().to_string())
        .unwrap_or_else(|| "oryvexcore".to_string());
    match config.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.join(format!("{stem}-mitm")),
        _ => PathBuf::from(format!("{stem}-mitm")),
    }
}

// ---------------------------------------------------------------------------------------------
// Which sites, and how each one is fronted
// ---------------------------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Group {
    Google,
    GoogleVideo,
    Meta,
    Fastly,
}

const GOOGLE_VIDEO: &[&str] = &["googlevideo.com"];

const GOOGLE: &[&str] = &[
    "google.com", "googleapis.com", "gstatic.com", "youtube.com", "youtu.be", "ytimg.com",
    "ggpht.com", "googleusercontent.com", "gvt1.com", "gvt2.com", "withgoogle.com",
    "google-analytics.com", "googletagmanager.com", "googlesyndication.com", "doubleclick.net",
    "youtube-nocookie.com", "googleadservices.com", "gmail.com", "blogger.com", "blogspot.com",
    "goo.gl", "g.co", "recaptcha.net", "ampproject.org", "android.com", "googledrive.com",
    "googlevideo.com", "google.org", "youtubekids.com", "yt.be",
];

const META: &[&str] = &[
    "facebook.com", "fb.com", "fb.me", "fbcdn.net", "fbsbx.com", "facebook.net", "instagram.com",
    "cdninstagram.com", "whatsapp.com", "whatsapp.net", "wa.me", "messenger.com", "meta.com",
    "oculus.com", "threads.net", "threads.com", "fbpigeon.com", "internet.org",
];

const FASTLY: &[&str] = &[
    "reddit.com", "redd.it", "redditmedia.com", "redditstatic.com", "redditspace.com", "cnn.com",
    "buzzfeed.com", "githubassets.com", "pypi.org", "pythonhosted.org", "python.org",
    "fastly.net", "fastly.com",
];

/// Domains that are never touched: local names and Iranian sites go out directly.
fn always_direct(host: &str) -> bool {
    host == "localhost" || host.ends_with(".local") || host.ends_with(".lan") || suffix_in(host, &["ir"])
}

fn suffix_in(host: &str, list: &[&str]) -> bool {
    list.iter()
        .any(|d| host == *d || (host.len() > d.len() && host.ends_with(d) && host.as_bytes()[host.len() - d.len() - 1] == b'.'))
}

/// Which front serves `host`, if any.
pub fn classify(host: &str) -> Option<Group> {
    let host = host.trim_end_matches('.').to_ascii_lowercase();
    if always_direct(&host) {
        return None;
    }
    if suffix_in(&host, GOOGLE_VIDEO) {
        Some(Group::GoogleVideo)
    } else if suffix_in(&host, GOOGLE) {
        Some(Group::Google)
    } else if suffix_in(&host, META) {
        Some(Group::Meta)
    } else if suffix_in(&host, FASTLY) {
        Some(Group::Fastly)
    } else {
        None
    }
}

/// Where the upstream connection goes.
enum Dial {
    /// The real address of the site that was asked for.
    Target,
    /// The address of this host instead (a Fastly edge that serves the site).
    Host(&'static str),
}

struct Front {
    /// The name sent in the handshake: what a filter reads.
    sni: &'static str,
    /// The certificate that comes back must carry one of these, or the requested name.
    names: &'static [&'static str],
    dial: Dial,
}

const GOOGLE_NAMES: &[&str] = &["www.google.com", "dns.google", "www.googlevideo.com", "www.youtube.com"];
const META_NAMES: &[&str] = &[
    "www.google.com", "www.microsoft.com", "www.whatsapp.com", "www.facebook.com", "www.ar.meta.com",
    "www.fb.com", "www.whatsapp.net", "www.atlassolutions.com", "www.secure.facebook.com",
    "www.extern.facebook.com", "www.internet.org", "www.oculus.com", "www.wit.ai",
    "www.facebook-dns.com", "www.instagram.com", "www.meta.com", "www.external-disputes.meta.com",
    "www.fbe2e.com", "www.cloud.x2p.facebook.net", "www.secure.latest.facebook.com",
];
const FASTLY_NAMES: &[&str] = &[
    "www.python.org", "pypi.org", "fastly.com", "www.fastly.com", "developer.fastly.com",
    "reddit.com", "githubassets.com", "github.com", "github.io", "githubusercontent.com",
    "github.githubassets.com",
];
const DOH_NAMES: &[&str] = &[
    "www.microsoft.com", "www.google.com", "dns.google", "cloudflare-dns.com", "one.one.one.one",
];

fn front(group: Group) -> Front {
    match group {
        Group::Google | Group::GoogleVideo => Front { sni: "www.google.com", names: GOOGLE_NAMES, dial: Dial::Target },
        Group::Meta => Front { sni: "www.microsoft.com", names: META_NAMES, dial: Dial::Target },
        Group::Fastly => Front { sni: "github.githubassets.com", names: FASTLY_NAMES, dial: Dial::Host("github.githubassets.com") },
    }
}

// ---------------------------------------------------------------------------------------------
// The device's own certificate authority
// ---------------------------------------------------------------------------------------------

fn new_key() -> Result<PKey<Private>> {
    let group = EcGroup::from_curve_name(Nid::X9_62_PRIME256V1).map_err(tls_err)?;
    let ec = EcKey::generate(&group).map_err(tls_err)?;
    PKey::from_ec_key(ec).map_err(tls_err)
}

fn serial() -> Result<Asn1Integer> {
    let mut bn = BigNum::new().map_err(tls_err)?;
    bn.rand(120, MsbOption::MAYBE_ZERO, false).map_err(tls_err)?;
    bn.to_asn1_integer().map_err(tls_err)
}

fn subject(common_name: &str) -> Result<X509Name> {
    let mut b = boring::x509::X509NameBuilder::new().map_err(tls_err)?;
    b.append_entry_by_nid(Nid::ORGANIZATIONNAME, "OryvexVPN").map_err(tls_err)?;
    b.append_entry_by_nid(Nid::COMMONNAME, common_name).map_err(tls_err)?;
    Ok(b.build())
}

fn unix_now() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn make_ca() -> Result<(X509, PKey<Private>)> {
    let key = new_key()?;
    let name = subject("OryvexVPN MITM CA (this device only)")?;
    let mut b = boring::x509::X509Builder::new().map_err(tls_err)?;
    b.set_version(2).map_err(tls_err)?;
    let sn = serial()?;
    b.set_serial_number(&sn).map_err(tls_err)?;
    b.set_subject_name(&name).map_err(tls_err)?;
    b.set_issuer_name(&name).map_err(tls_err)?;
    let nb = Asn1Time::from_unix(unix_now() - 86_400).map_err(tls_err)?;
    b.set_not_before(&nb).map_err(tls_err)?;
    let na = Asn1Time::days_from_now(3650).map_err(tls_err)?;
    b.set_not_after(&na).map_err(tls_err)?;
    b.set_pubkey(&key).map_err(tls_err)?;
    let ext1: boring::x509::X509Extension = BasicConstraints::new().critical().ca().build().map_err(tls_err)?;
    b.append_extension(&ext1).map_err(tls_err)?;
    let ext2: boring::x509::X509Extension = KeyUsage::new().critical().key_cert_sign().crl_sign().build().map_err(tls_err)?;
    b.append_extension(&ext2).map_err(tls_err)?;
    b.sign(&key, MessageDigest::sha256()).map_err(tls_err)?;
    Ok((b.build(), key))
}

/// The CA and the keys that sign and serve the per-site certificates.
pub struct Authority {
    ca_cert: X509,
    ca_key: PKey<Private>,
    leaf_key: PKey<Private>,
    cache: Mutex<HashMap<String, X509>>,
}

impl Authority {
    /// Loads the CA from `dir`, or makes one (once per device) and saves it there.
    pub fn load_or_create(dir: &Path) -> Result<Self> {
        let crt = dir.join(CA_CRT);
        let key = dir.join(CA_KEY);
        let (ca_cert, ca_key) = match (std::fs::read(&crt), std::fs::read(&key)) {
            (Ok(c), Ok(k)) => match (X509::from_pem(&c), PKey::private_key_from_pem(&k)) {
                (Ok(c), Ok(k)) => (c, k),
                _ => Self::create(dir)?,
            },
            _ => Self::create(dir)?,
        };
        // Always keep the DER copy beside it: Android's installer wants that form.
        let der = dir.join(CA_DER);
        if !der.is_file() {
            if let Ok(bytes) = ca_cert.to_der() {
                let _ = std::fs::write(&der, bytes);
            }
        }
        Ok(Self::with_ca(ca_cert, ca_key)?)
    }

    fn create(dir: &Path) -> Result<(X509, PKey<Private>)> {
        std::fs::create_dir_all(dir).map_err(|e| other(format!("cannot create {}: {e}", dir.display())))?;
        let (cert, key) = make_ca()?;
        let key_pem = key.private_key_to_pem_pkcs8().map_err(tls_err)?;
        let key_path = dir.join(CA_KEY);
        std::fs::write(&key_path, key_pem).map_err(|e| other(format!("cannot save the MITM key: {e}")))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = std::fs::set_permissions(&key_path, std::fs::Permissions::from_mode(0o600));
        }
        std::fs::write(dir.join(CA_CRT), cert.to_pem().map_err(tls_err)?)
            .map_err(|e| other(format!("cannot save the MITM certificate: {e}")))?;
        let _ = std::fs::write(dir.join(CA_DER), cert.to_der().map_err(tls_err)?);
        log::info!("[+] made a new certificate authority for this device");
        Ok((cert, key))
    }

    fn with_ca(ca_cert: X509, ca_key: PKey<Private>) -> Result<Self> {
        Ok(Self { ca_cert, ca_key, leaf_key: new_key()?, cache: Mutex::new(HashMap::new()) })
    }

    /// A certificate for `host`, signed by the CA (cached).
    pub fn leaf_for(&self, host: &str) -> Result<X509> {
        let host = host.trim_end_matches('.').to_ascii_lowercase();
        if let Some(found) = self.cache.lock().map_err(|_| other("certificate cache poisoned"))?.get(&host) {
            return Ok(found.clone());
        }
        let name = subject(&host)?;
        let mut b = boring::x509::X509Builder::new().map_err(tls_err)?;
        b.set_version(2).map_err(tls_err)?;
        let sn = serial()?;
        b.set_serial_number(&sn).map_err(tls_err)?;
        b.set_subject_name(&name).map_err(tls_err)?;
        b.set_issuer_name(self.ca_cert.subject_name()).map_err(tls_err)?;
        let nb = Asn1Time::from_unix(unix_now() - 86_400).map_err(tls_err)?;
    b.set_not_before(&nb).map_err(tls_err)?;
        let na = Asn1Time::days_from_now(90).map_err(tls_err)?;
        b.set_not_after(&na).map_err(tls_err)?;
        b.set_pubkey(&self.leaf_key).map_err(tls_err)?;
        let ext3: boring::x509::X509Extension = BasicConstraints::new().build().map_err(tls_err)?;
        b.append_extension(&ext3).map_err(tls_err)?;
        let ext4: boring::x509::X509Extension = KeyUsage::new().critical().digital_signature().build().map_err(tls_err)?;
        b.append_extension(&ext4).map_err(tls_err)?;
        let ext5: boring::x509::X509Extension = ExtendedKeyUsage::new().server_auth().build().map_err(tls_err)?;
        b.append_extension(&ext5).map_err(tls_err)?;
        let san = {
            let ctx = b.x509v3_context(Some(&*self.ca_cert), None);
            let mut s = SubjectAlternativeName::new();
            if host.parse::<IpAddr>().is_ok() {
                s.ip(&host);
            } else {
                s.dns(&host);
            }
            s.build(&ctx).map_err(tls_err)?
        };
        b.append_extension(&san).map_err(tls_err)?;
        b.sign(&self.ca_key, MessageDigest::sha256()).map_err(tls_err)?;
        let cert = b.build();
        let mut cache = self.cache.lock().map_err(|_| other("certificate cache poisoned"))?;
        if cache.len() > 4000 {
            cache.clear();
        }
        cache.insert(host, cert.clone());
        Ok(cert)
    }
}

/// What the browser meets: a TLS server that issues a certificate for whatever name it is asked
/// for, and speaks h2 or http/1.1 (googlevideo only http/1.1, as the Xray config does).
fn build_acceptor(auth: &Arc<Authority>) -> Result<SslAcceptor> {
    let mut b = SslAcceptor::mozilla_intermediate_v5(SslMethod::tls()).map_err(tls_err)?;
    let fallback = auth.leaf_for("oryvex.local")?;
    b.set_certificate(&fallback).map_err(tls_err)?;
    b.set_private_key(&auth.leaf_key).map_err(tls_err)?;
    let issuer = auth.clone();
    b.set_servername_callback(move |ssl: &mut SslRef, _alert| {
        let Some(name) = ssl.servername(NameType::HOST_NAME).map(str::to_string) else {
            return Ok(());
        };
        let cert = issuer.leaf_for(&name).map_err(|_| SniError::ALERT_FATAL)?;
        ssl.set_certificate(&cert).map_err(|_| SniError::ALERT_FATAL)?;
        ssl.set_private_key(&issuer.leaf_key).map_err(|_| SniError::ALERT_FATAL)?;
        Ok(())
    });
    b.set_alpn_select_callback(|ssl, offered| {
        let h1_only = ssl
            .servername(NameType::HOST_NAME)
            .map(|n| n.to_ascii_lowercase().ends_with("googlevideo.com"))
            .unwrap_or(false);
        let ours: &'static [u8] = if h1_only { b"\x08http/1.1" } else { b"\x02h2\x08http/1.1" };
        select_next_proto(ours, offered).ok_or(AlpnError::NOACK)
    });
    Ok(b.build())
}

// ---------------------------------------------------------------------------------------------
// The way out: TLS with another name, checked against the real one
// ---------------------------------------------------------------------------------------------

fn roots() -> &'static X509Store {
    static ROOTS: OnceLock<X509Store> = OnceLock::new();
    ROOTS.get_or_init(|| {
        let mut b = X509StoreBuilder::new().expect("a certificate store");
        if let Ok(list) = X509::stack_from_pem(ROOTS_PEM.as_bytes()) {
            for cert in list {
                let _ = b.add_cert(cert);
            }
        }
        b.build()
    })
}

#[derive(Clone, Copy)]
enum Alpn {
    None,
    Http1,
    H2Http1,
}

fn connector(alpn: Alpn) -> &'static SslConnector {
    static CONNECTORS: OnceLock<Vec<SslConnector>> = OnceLock::new();
    let all = CONNECTORS.get_or_init(|| {
        [Alpn::None, Alpn::Http1, Alpn::H2Http1]
            .iter()
            .map(|kind| {
                let mut b = SslConnector::builder(SslMethod::tls()).expect("tls");
                // The certificate is checked by hand after the handshake (verify_peer): the name
                // in it is not the name in the handshake.
                b.set_verify(SslVerifyMode::NONE);
                match kind {
                    Alpn::None => {}
                    Alpn::Http1 => {
                        let _ = b.set_alpn_protos(b"\x08http/1.1");
                    }
                    Alpn::H2Http1 => {
                        let _ = b.set_alpn_protos(b"\x02h2\x08http/1.1");
                    }
                }
                b.build()
            })
            .collect()
    });
    match alpn {
        Alpn::None => &all[0],
        Alpn::Http1 => &all[1],
        Alpn::H2Http1 => &all[2],
    }
}

/// `pattern` (a certificate name, possibly `*.x`) covers `name`.
pub fn dns_match(pattern: &str, name: &str) -> bool {
    let pattern = pattern.to_ascii_lowercase();
    let name = name.to_ascii_lowercase();
    if let Some(rest) = pattern.strip_prefix("*.") {
        match name.split_once('.') {
            Some((label, tail)) => !label.is_empty() && tail == rest,
            None => false,
        }
    } else {
        pattern == name
    }
}

/// Does the certificate chain lead to a trusted root, and does it carry one of `allowed`?
fn verify_peer(ssl: &SslRef, allowed: &[&str], also: &str) -> Result<()> {
    let leaf = ssl.peer_certificate().ok_or_else(|| tls_err("the server sent no certificate"))?;
    let empty;
    let chain = match ssl.peer_cert_chain() {
        Some(c) => c,
        None => {
            empty = Stack::<X509>::new().map_err(tls_err)?;
            &*empty
        }
    };
    let mut ctx = X509StoreContext::new().map_err(tls_err)?;
    let trusted = ctx
        .init(roots(), &leaf, chain, |c| c.verify_cert())
        .map_err(tls_err)?;
    if !trusted {
        return Err(tls_err("the server certificate is not signed by a trusted authority"));
    }
    let Some(sans) = leaf.subject_alt_names() else {
        return Err(tls_err("the server certificate names nothing"));
    };
    for gn in sans.iter() {
        if let Some(dns) = gn.dnsname() {
            if dns_match(dns, also) || allowed.iter().any(|a| dns_match(dns, a)) {
                return Ok(());
            }
        }
    }
    Err(tls_err(format!("the server certificate is not for {also} or any allowed name")))
}

type Upstream = tokio_boring::SslStream<TcpStream>;

async fn tcp(addr: SocketAddr) -> std::io::Result<TcpStream> {
    let s = tokio::time::timeout(DIAL_TIMEOUT, crate::egress::tcp_connect(addr))
        .await
        .map_err(|_| std::io::Error::new(std::io::ErrorKind::TimedOut, "connect timed out"))??;
    let _ = s.set_nodelay(true);
    Ok(s)
}

/// TLS to `addr` naming `sni`, with the certificate checked against `allowed` and `real`.
async fn fronted_connect(addr: SocketAddr, sni: &str, allowed: &[&str], real: &str, alpn: Alpn) -> Result<Upstream> {
    let sock = tcp(addr).await.map_err(|e| other(format!("connect {addr}: {e}")))?;
    let mut config = connector(alpn).configure().map_err(tls_err)?;
    config.set_verify_hostname(false);
    config.set_use_server_name_indication(true);
    let tls = tokio::time::timeout(HANDSHAKE_TIMEOUT, tokio_boring::connect(config, sni, sock))
        .await
        .map_err(|_| tls_err("handshake timed out"))?
        .map_err(tls_err)?;
    verify_peer(tls.ssl(), allowed, real)?;
    Ok(tls)
}

// ---------------------------------------------------------------------------------------------
// Names: DNS over HTTPS to 1.1.1.1, itself fronted
// ---------------------------------------------------------------------------------------------

fn dns_query(name: &str, id: u16) -> Vec<u8> {
    let mut q = Vec::with_capacity(32 + name.len());
    q.extend_from_slice(&id.to_be_bytes());
    q.extend_from_slice(&[0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
    for label in name.trim_end_matches('.').split('.') {
        q.push(label.len().min(63) as u8);
        q.extend_from_slice(&label.as_bytes()[..label.len().min(63)]);
    }
    q.push(0);
    q.extend_from_slice(&[0, 1, 0, 1]); // A, IN
    q
}

fn skip_name(buf: &[u8], mut pos: usize) -> Option<usize> {
    loop {
        let len = *buf.get(pos)? as usize;
        if len == 0 {
            return Some(pos + 1);
        }
        if len & 0xC0 == 0xC0 {
            return Some(pos + 2);
        }
        pos += 1 + len;
    }
}

/// The IPv4 addresses in a DNS answer.
pub fn parse_a_records(msg: &[u8]) -> Vec<Ipv4Addr> {
    let mut out = Vec::new();
    if msg.len() < 12 || msg[3] & 0x0F != 0 {
        return out;
    }
    let qd = u16::from_be_bytes([msg[4], msg[5]]) as usize;
    let an = u16::from_be_bytes([msg[6], msg[7]]) as usize;
    let mut pos = 12;
    for _ in 0..qd {
        let Some(p) = skip_name(msg, pos) else { return out };
        pos = p + 4;
    }
    for _ in 0..an {
        let Some(p) = skip_name(msg, pos) else { return out };
        if p + 10 > msg.len() {
            return out;
        }
        let rtype = u16::from_be_bytes([msg[p], msg[p + 1]]);
        let rdlen = u16::from_be_bytes([msg[p + 8], msg[p + 9]]) as usize;
        let data = p + 10;
        if data + rdlen > msg.len() {
            return out;
        }
        if rtype == 1 && rdlen == 4 {
            out.push(Ipv4Addr::new(msg[data], msg[data + 1], msg[data + 2], msg[data + 3]));
        }
        pos = data + rdlen;
    }
    out
}

/// The body of an HTTP/1.1 response, de-chunked when it is chunked.
pub fn http_body(raw: &[u8]) -> Option<Vec<u8>> {
    let split = raw.windows(4).position(|w| w == b"\r\n\r\n")?;
    let head = String::from_utf8_lossy(&raw[..split]).to_ascii_lowercase();
    if !head.starts_with("http/1.1 200") && !head.starts_with("http/1.0 200") {
        return None;
    }
    let body = &raw[split + 4..];
    if !head.contains("transfer-encoding: chunked") {
        return Some(body.to_vec());
    }
    let mut out = Vec::new();
    let mut rest = body;
    loop {
        let eol = rest.windows(2).position(|w| w == b"\r\n")?;
        let size = usize::from_str_radix(String::from_utf8_lossy(&rest[..eol]).split(';').next()?.trim(), 16).ok()?;
        rest = &rest[eol + 2..];
        if size == 0 {
            return Some(out);
        }
        if rest.len() < size {
            return None;
        }
        out.extend_from_slice(&rest[..size]);
        rest = rest.get(size + 2..)?;
    }
}

async fn doh_once(resolver: Ipv4Addr, name: &str) -> Result<Vec<Ipv4Addr>> {
    let id = (rand::rng().next_u32() & 0xffff) as u16;
    let query = dns_query(name, id);
    let encoded = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&query);
    let mut tls = fronted_connect(
        SocketAddr::new(IpAddr::V4(resolver), 443),
        "www.microsoft.com",
        DOH_NAMES,
        "cloudflare-dns.com",
        Alpn::Http1,
    )
    .await?;
    let request = format!(
        "GET /dns-query?dns={encoded} HTTP/1.1\r\nHost: cloudflare-dns.com\r\nAccept: application/dns-message\r\nConnection: close\r\n\r\n"
    );
    tls.write_all(request.as_bytes()).await.map_err(|e| other(e.to_string()))?;
    let mut raw = Vec::new();
    let read = async {
        let mut buf = [0u8; 4096];
        loop {
            match tls.read(&mut buf).await {
                Ok(0) | Err(_) => break,
                Ok(n) => {
                    raw.extend_from_slice(&buf[..n]);
                    if raw.len() > 64 * 1024 {
                        break;
                    }
                }
            }
        }
    };
    let _ = tokio::time::timeout(Duration::from_secs(8), read).await;
    let body = http_body(&raw).ok_or_else(|| other("the resolver gave no answer"))?;
    Ok(parse_a_records(&body))
}

fn dns_cache() -> &'static Mutex<HashMap<String, (Instant, Vec<IpAddr>)>> {
    static CACHE: OnceLock<Mutex<HashMap<String, (Instant, Vec<IpAddr>)>>> = OnceLock::new();
    CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

fn is_private(ip: IpAddr) -> bool {
    match ip {
        IpAddr::V4(v) => v.is_private() || v.is_loopback() || v.is_link_local() || v.is_unspecified(),
        IpAddr::V6(v) => v.is_loopback() || v.is_unspecified(),
    }
}

/// The addresses of `host`: itself if it is one, else the fronted resolver's answer, else the
/// system's.
async fn resolve(host: &str) -> Result<Vec<IpAddr>> {
    if let Ok(ip) = host.parse::<IpAddr>() {
        return Ok(vec![ip]);
    }
    let key = host.to_ascii_lowercase();
    if let Ok(cache) = dns_cache().lock() {
        if let Some((at, list)) = cache.get(&key) {
            if at.elapsed() < DNS_TTL {
                return Ok(list.clone());
            }
        }
    }
    let mut found: Vec<IpAddr> = Vec::new();
    if !always_direct(&key) {
        for resolver in [Ipv4Addr::new(1, 1, 1, 1), Ipv4Addr::new(1, 0, 0, 1)] {
            match doh_once(resolver, &key).await {
                Ok(list) if !list.is_empty() => {
                    found = list.into_iter().map(IpAddr::V4).filter(|ip| !is_private(*ip)).collect();
                    if !found.is_empty() {
                        break;
                    }
                }
                Ok(_) => {}
                Err(e) => log::debug!("[mitm] resolver {resolver}: {e}"),
            }
        }
    }
    if found.is_empty() {
        let system = tokio::net::lookup_host((key.as_str(), 443))
            .await
            .map_err(|e| other(format!("{host} did not resolve: {e}")))?;
        found = system.map(|a| a.ip()).filter(|ip| ip.is_ipv4()).collect();
    }
    if found.is_empty() {
        return Err(other(format!("{host} did not resolve")));
    }
    if let Ok(mut cache) = dns_cache().lock() {
        if cache.len() > 5000 {
            cache.clear();
        }
        cache.insert(key, (Instant::now(), found.clone()));
    }
    Ok(found)
}

// ---------------------------------------------------------------------------------------------
// Relaying
// ---------------------------------------------------------------------------------------------

async fn copy_counted<R, W>(from: &mut R, to: &mut W, upload: bool)
where
    R: AsyncRead + Unpin,
    W: AsyncWrite + Unpin,
{
    let mut buf = vec![0u8; 16 * 1024];
    loop {
        let n = match tokio::time::timeout(IDLE, from.read(&mut buf)).await {
            Ok(Ok(n)) if n > 0 => n,
            _ => break,
        };
        if to.write_all(&buf[..n]).await.is_err() {
            break;
        }
        if upload {
            stats::add_up(n);
        } else {
            stats::add_down(n);
        }
    }
    let _ = to.shutdown().await;
}

async fn pump<A, B>(a: A, b: B)
where
    A: AsyncRead + AsyncWrite + Unpin,
    B: AsyncRead + AsyncWrite + Unpin,
{
    let (mut ar, mut aw) = tokio::io::split(a);
    let (mut br, mut bw) = tokio::io::split(b);
    let up = copy_counted(&mut ar, &mut bw, true);
    let down = copy_counted(&mut br, &mut aw, false);
    tokio::join!(up, down);
}

// ---------------------------------------------------------------------------------------------
// The proxy: SOCKS5 and HTTP on the same port
// ---------------------------------------------------------------------------------------------

struct Ctx {
    auth: Arc<Authority>,
    acceptor: SslAcceptor,
    warned_cert: Mutex<Option<Instant>>,
}

async fn handle_client(sock: TcpStream, ctx: Arc<Ctx>) {
    let _ = sock.set_nodelay(true);
    let mut first = [0u8; 1];
    let Ok(Ok(n)) = tokio::time::timeout(Duration::from_secs(15), sock.peek(&mut first)).await else {
        return;
    };
    if n == 0 {
        return;
    }
    let result = if first[0] == 0x05 { socks5(sock, &ctx).await } else { http_proxy(sock, &ctx).await };
    if let Err(e) = result {
        log::debug!("[mitm] {e}");
    }
}

async fn socks5(mut sock: TcpStream, ctx: &Arc<Ctx>) -> Result<()> {
    let io = |e: std::io::Error| other(e.to_string());
    let mut head = [0u8; 2];
    sock.read_exact(&mut head).await.map_err(io)?;
    let mut methods = vec![0u8; head[1] as usize];
    sock.read_exact(&mut methods).await.map_err(io)?;
    sock.write_all(&[5, 0]).await.map_err(io)?;

    let mut req = [0u8; 4];
    sock.read_exact(&mut req).await.map_err(io)?;
    let host = match req[3] {
        1 => {
            let mut a = [0u8; 4];
            sock.read_exact(&mut a).await.map_err(io)?;
            Ipv4Addr::from(a).to_string()
        }
        3 => {
            let mut len = [0u8; 1];
            sock.read_exact(&mut len).await.map_err(io)?;
            let mut name = vec![0u8; len[0] as usize];
            sock.read_exact(&mut name).await.map_err(io)?;
            String::from_utf8_lossy(&name).to_string()
        }
        4 => {
            let mut a = [0u8; 16];
            sock.read_exact(&mut a).await.map_err(io)?;
            std::net::Ipv6Addr::from(a).to_string()
        }
        _ => {
            let _ = sock.write_all(&[5, 8, 0, 1, 0, 0, 0, 0, 0, 0]).await;
            return Ok(());
        }
    };
    let mut p = [0u8; 2];
    sock.read_exact(&mut p).await.map_err(io)?;
    let port = u16::from_be_bytes(p);
    if req[1] != 1 {
        // UDP and BIND are not served: browsers fall back from QUIC to TCP, which this route covers.
        let _ = sock.write_all(&[5, 7, 0, 1, 0, 0, 0, 0, 0, 0]).await;
        return Ok(());
    }
    connect_target(sock, ctx, host, port, Reply::Socks).await
}

#[derive(Clone, Copy)]
enum Reply {
    Socks,
    Http,
}

async fn say_ok(sock: &mut TcpStream, how: Reply) -> std::io::Result<()> {
    match how {
        Reply::Socks => sock.write_all(&[5, 0, 0, 1, 0, 0, 0, 0, 0, 0]).await,
        Reply::Http => sock.write_all(b"HTTP/1.1 200 Connection Established\r\n\r\n").await,
    }
}

async fn say_fail(sock: &mut TcpStream, how: Reply) {
    let _ = match how {
        Reply::Socks => sock.write_all(&[5, 4, 0, 1, 0, 0, 0, 0, 0, 0]).await,
        Reply::Http => sock.write_all(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n").await,
    };
}

async fn connect_target(mut sock: TcpStream, ctx: &Arc<Ctx>, host: String, port: u16, how: Reply) -> Result<()> {
    if port == 443 {
        if let Some(group) = classify(&host) {
            say_ok(&mut sock, how).await.map_err(|e| other(e.to_string()))?;
            return fronted(sock, ctx, &host, group).await;
        }
    }
    // Everything else goes out directly, untouched.
    let addrs = match resolve(&host).await {
        Ok(a) => a,
        Err(e) => {
            say_fail(&mut sock, how).await;
            return Err(e);
        }
    };
    let mut out = None;
    for ip in addrs.iter().take(4) {
        if let Ok(s) = tcp(SocketAddr::new(*ip, port)).await {
            out = Some(s);
            break;
        }
    }
    let Some(out) = out else {
        say_fail(&mut sock, how).await;
        return Err(other(format!("cannot reach {host}:{port}")));
    };
    say_ok(&mut sock, how).await.map_err(|e| other(e.to_string()))?;
    pump(sock, out).await;
    Ok(())
}

async fn fronted(sock: TcpStream, ctx: &Arc<Ctx>, host: &str, group: Group) -> Result<()> {
    let spec = front(group);
    // The browser first: it must accept our certificate for this name.
    let client = match tokio::time::timeout(HANDSHAKE_TIMEOUT, tokio_boring::accept(&ctx.acceptor, sock)).await {
        Ok(Ok(tls)) => tls,
        Ok(Err(e)) => {
            note_cert_trouble(ctx, host, &e.to_string());
            return Ok(());
        }
        Err(_) => return Ok(()),
    };
    let alpn = match client.ssl().selected_alpn_protocol() {
        Some(b"h2") => Alpn::H2Http1,
        Some(b"http/1.1") => Alpn::Http1,
        _ => Alpn::None,
    };
    // For the upstream, offer only what the browser got: h2 passes through as h2.
    let upstream_alpn = match client.ssl().selected_alpn_protocol() {
        Some(b"h2") => Alpn::H2Http1,
        _ => match alpn {
            Alpn::None => Alpn::None,
            _ => Alpn::Http1,
        },
    };

    let dial_host = match spec.dial {
        Dial::Target => host.to_string(),
        Dial::Host(h) => h.to_string(),
    };
    let addrs = resolve(&dial_host).await?;
    let mut last = other(format!("no address for {dial_host}"));
    for ip in addrs.iter().take(3) {
        match fronted_connect(SocketAddr::new(*ip, 443), spec.sni, spec.names, host, upstream_alpn).await {
            Ok(up) => {
                // The two sides must have agreed on the same protocol, or the bytes mean nothing.
                let mine = client.ssl().selected_alpn_protocol().map(|p| p.to_vec());
                let theirs = up.ssl().selected_alpn_protocol().map(|p| p.to_vec());
                if mine != theirs && !(mine.is_none() && theirs.is_none()) {
                    last = other(format!("{host}: protocol mismatch, retrying"));
                    continue;
                }
                pump(client, up).await;
                return Ok(());
            }
            Err(e) => last = e,
        }
    }
    log::debug!("[mitm] {host}: {last}");
    Err(last)
}

fn note_cert_trouble(ctx: &Arc<Ctx>, host: &str, why: &str) {
    let mut last = match ctx.warned_cert.lock() {
        Ok(l) => l,
        Err(_) => return,
    };
    if last.map(|t| t.elapsed() > Duration::from_secs(30)).unwrap_or(true) {
        *last = Some(Instant::now());
        log::warn!(
            "[mitm] {host}: the app turned the certificate down ({why}). Install the OryvexVPN certificate as trusted, and use a browser (most other Android apps ignore user certificates)."
        );
    }
}

async fn http_proxy(mut sock: TcpStream, ctx: &Arc<Ctx>) -> Result<()> {
    let io = |e: std::io::Error| other(e.to_string());
    let mut head = Vec::with_capacity(2048);
    let mut buf = [0u8; 2048];
    let end = loop {
        let n = tokio::time::timeout(Duration::from_secs(15), sock.read(&mut buf))
            .await
            .map_err(|_| other("request timed out"))?
            .map_err(io)?;
        if n == 0 {
            return Ok(());
        }
        head.extend_from_slice(&buf[..n]);
        if let Some(p) = head.windows(4).position(|w| w == b"\r\n\r\n") {
            break p + 4;
        }
        if head.len() > 32 * 1024 {
            return Err(other("request head too large"));
        }
    };
    let text = String::from_utf8_lossy(&head[..end]).to_string();
    let line = text.lines().next().unwrap_or("");
    let mut parts = line.split_whitespace();
    let method = parts.next().unwrap_or("");
    let target = parts.next().unwrap_or("");
    if method.eq_ignore_ascii_case("CONNECT") {
        let (host, port) = split_host_port(target, 443);
        return connect_target(sock, ctx, host, port, Reply::Http).await;
    }
    // A plain http:// request: forward it as it is.
    let rest = target.strip_prefix("http://").ok_or_else(|| other("not a proxy request"))?;
    let authority = rest.split('/').next().unwrap_or(rest);
    let (host, port) = split_host_port(authority, 80);
    let addrs = resolve(&host).await?;
    let mut out = None;
    for ip in addrs.iter().take(4) {
        if let Ok(s) = tcp(SocketAddr::new(*ip, port)).await {
            out = Some(s);
            break;
        }
    }
    let Some(mut out) = out else {
        say_fail(&mut sock, Reply::Http).await;
        return Err(other(format!("cannot reach {host}:{port}")));
    };
    out.write_all(&head).await.map_err(io)?;
    pump(sock, out).await;
    Ok(())
}

fn split_host_port(s: &str, default: u16) -> (String, u16) {
    if let Some(rest) = s.strip_prefix('[') {
        if let Some((h, tail)) = rest.split_once(']') {
            let port = tail.strip_prefix(':').and_then(|p| p.parse().ok()).unwrap_or(default);
            return (h.to_string(), port);
        }
    }
    match s.rsplit_once(':') {
        Some((h, p)) if !h.contains(':') => (h.to_string(), p.parse().unwrap_or(default)),
        _ => (s.to_string(), default),
    }
}

async fn serve(listener: TcpListener, ctx: Arc<Ctx>) {
    let limit = Arc::new(tokio::sync::Semaphore::new(MAX_CLIENTS));
    loop {
        let (sock, _) = match listener.accept().await {
            Ok(pair) => pair,
            Err(e) => {
                log::warn!("[mitm] accept: {e}");
                tokio::time::sleep(Duration::from_millis(200)).await;
                continue;
            }
        };
        let Ok(permit) = limit.clone().acquire_owned().await else { return };
        let ctx = ctx.clone();
        tokio::spawn(async move {
            handle_client(sock, ctx).await;
            drop(permit);
        });
    }
}

/// `--mitm-make-ca`: make the certificate authority (if there is none yet), print where it is, and stop.
pub fn make_ca_requested() -> bool {
    env_value("ORYVEXCORE_MITM_MAKE_CA").map(|v| v == "1").unwrap_or(false)
}

pub fn make_ca_only(base_config: &str) -> Result<()> {
    let dir = state_dir(base_config);
    Authority::load_or_create(&dir)?;
    println!("[+] mitm certificate: {}", dir.join(CA_CRT).display());
    Ok(())
}

/// Serves the MITM route on `listen` until the core is stopped.
pub async fn run(listen: SocketAddr, base_config: &str) -> Result<()> {
    log::info!("[*] mitm route: no tunnel, sites on the list are re-sent with another name in the handshake");
    log::info!("[*] starting the mitm engine");
    let dir = state_dir(base_config);
    let auth = Arc::new(Authority::load_or_create(&dir)?);
    log::info!("[+] mitm certificate: {}", dir.join(CA_CRT).display());
    let acceptor = build_acceptor(&auth)?;
    let _ = roots();
    let ctx = Arc::new(Ctx { auth, acceptor, warned_cert: Mutex::new(None) });
    let _ = &ctx.auth;

    let listener = crate::socks::bind_listener("socks5 server", listen, "--bind").await?;
    let served = listener.local_addr().unwrap_or(listen);
    log::info!("[+] socks5 server listening on {served}");
    tokio::spawn(serve(listener, ctx.clone()));

    if let Some(http) = env_value("ORYVEXCORE_HTTP_PROXY").and_then(|v| v.parse::<SocketAddr>().ok()) {
        let listener = crate::socks::bind_listener("http proxy", http, "--http-proxy").await?;
        log::info!("[+] http proxy listening on {http}");
        tokio::spawn(serve(listener, ctx.clone()));
    }
    log::info!("[+] mitm is ready; {served} reaches the internet directly, and the listed sites are fronted");

    let _ = tokio::signal::ctrl_c().await;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_listed_sites_are_sorted_into_their_fronts() {
        assert_eq!(classify("www.youtube.com"), Some(Group::Google));
        assert_eq!(classify("rr3---sn-x.googlevideo.com"), Some(Group::GoogleVideo));
        assert_eq!(classify("i.instagram.com"), Some(Group::Meta));
        assert_eq!(classify("www.reddit.com"), Some(Group::Fastly));
        assert_eq!(classify("example.org"), None);
        assert_eq!(classify("notgoogle.com"), None);
        assert_eq!(classify("digikala.ir"), None);
    }

    #[test]
    fn wildcard_names_cover_one_label() {
        assert!(dns_match("*.google.com", "www.google.com"));
        assert!(!dns_match("*.google.com", "a.b.google.com"));
        assert!(!dns_match("*.google.com", "google.com"));
        assert!(dns_match("WWW.Google.com", "www.google.com"));
    }

    #[test]
    fn a_dns_answer_gives_its_a_records() {
        let mut msg = dns_query("example.com", 7);
        msg[2] = 0x81;
        msg[3] = 0x80;
        msg[7] = 1;
        msg.extend_from_slice(&[0xC0, 0x0C, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4, 93, 184, 216, 34]);
        assert_eq!(parse_a_records(&msg), vec![Ipv4Addr::new(93, 184, 216, 34)]);
    }

    #[test]
    fn chunked_bodies_are_put_back_together() {
        let raw = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n";
        assert_eq!(http_body(raw), Some(b"abcde".to_vec()));
        let plain = b"HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nhi";
        assert_eq!(http_body(plain), Some(b"hi".to_vec()));
        assert_eq!(http_body(b"HTTP/1.1 502 Bad\r\n\r\n"), None);
    }

    #[test]
    fn host_and_port_are_split() {
        assert_eq!(split_host_port("a.com:8443", 443), ("a.com".to_string(), 8443));
        assert_eq!(split_host_port("a.com", 80), ("a.com".to_string(), 80));
        assert_eq!(split_host_port("[::1]:99", 80), ("::1".to_string(), 99));
    }

    #[test]
    fn a_site_certificate_chains_to_the_device_ca() {
        let (ca, key) = make_ca().expect("a CA");
        let auth = Authority::with_ca(ca.clone(), key).expect("an authority");
        let leaf = auth.leaf_for("www.youtube.com").expect("a leaf");
        let mut store = X509StoreBuilder::new().expect("a store");
        store.add_cert(ca).expect("the CA");
        let store = store.build();
        let chain = Stack::<X509>::new().expect("a stack");
        let mut ctx = X509StoreContext::new().expect("a context");
        let ok = ctx.init(&store, &leaf, &chain, |c| c.verify_cert()).expect("a verdict");
        assert!(ok);
    }
}
