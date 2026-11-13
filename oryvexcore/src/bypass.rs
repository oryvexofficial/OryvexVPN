//! The Bypass route: no tunnel, no change of exit address. The engine (`oryvex-bypass`, C, in
//! `oryvexcore/bypass/`) is a SOCKS5 proxy that reshapes the first bytes of each connection (it
//! splits and reorders the TLS ClientHello or HTTP request, and sends decoys) so a filter that
//! matches the site name in the stream no longer sees it, and that answers names with its own
//! anti-poisoning resolver. oryvexcore runs it as a child process, waits for its ready line, then
//! reports it the way every other route does ("socks5 server listening on ..."), so the apps need
//! nothing special to drive it.
//!
//! What it beats: filters that inspect packets one by one (stateless DPI) and DNS poisoning.
//! What it does not: filters that reassemble the whole stream, or block by address. Use a tunnel
//! route for those.

use std::net::{Ipv4Addr, SocketAddr};
use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::Command;

use crate::error::{OryvexCoreError, Result};
use crate::stats;

const BINARY_NAMES: &[&str] = &["oryvex-bypass", "liboryvex_bypass.so"];
const READY_TIMEOUT_SECS: u64 = 20;
const STATS_POLL_SECS: u64 = 2;

fn env_value(name: &str) -> Option<String> {
    std::env::var(name)
        .ok()
        .map(|v| v.trim().to_string())
        .filter(|v| !v.is_empty())
}

fn is_on(raw: &str) -> bool {
    matches!(
        raw.trim().to_ascii_lowercase().as_str(),
        "1" | "true" | "yes" | "on"
    )
}

fn is_off(raw: &str) -> bool {
    matches!(
        raw.trim().to_ascii_lowercase().as_str(),
        "0" | "false" | "no" | "off"
    )
}

/// True when this run is the Bypass route: `--bypass`, or `--protocol bypass`.
pub fn enabled() -> bool {
    if env_value("ORYVEXCORE_BYPASS").map(|v| is_on(&v)).unwrap_or(false) {
        return true;
    }
    env_value("ORYVEXCORE_PROTOCOL")
        .map(|v| v.eq_ignore_ascii_case("bypass"))
        .unwrap_or(false)
}

/// What the user chose for the engine.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Options {
    /// A fixed strategy such as `fake(ttl=4),split(sni)`. None: the engine tries techniques per
    /// site and keeps the one that works.
    pub strategy: Option<String>,
    /// Resolve names with the engine's anti-poisoning resolver.
    pub doh: bool,
    /// Drop QUIC datagrams so browsers fall back to TCP, which the techniques cover.
    pub drop_quic: bool,
    /// v4 | v6 | both
    pub ip: String,
    /// Anything else, passed to the engine as it is.
    pub extra: Vec<String>,
}

impl Default for Options {
    fn default() -> Self {
        Self {
            strategy: None,
            doh: true,
            drop_quic: true,
            ip: "v4".to_string(),
            extra: Vec::new(),
        }
    }
}

impl Options {
    pub fn from_env() -> Self {
        let mut o = Self::default();
        o.strategy = env_value("ORYVEXCORE_BYPASS_STRATEGY").filter(|v| !v.eq_ignore_ascii_case("auto"));
        if let Some(v) = env_value("ORYVEXCORE_BYPASS_DOH") {
            o.doh = !is_off(&v);
        }
        if let Some(v) = env_value("ORYVEXCORE_BYPASS_DROP_QUIC") {
            o.drop_quic = !is_off(&v);
        }
        if let Some(v) = env_value("ORYVEXCORE_IP") {
            o.ip = v.to_ascii_lowercase();
        }
        if let Some(v) = env_value("ORYVEXCORE_BYPASS_ARGS") {
            o.extra = v.split_whitespace().map(|s| s.to_string()).collect();
        }
        o
    }

    /// The engine's command line for a proxy on `listen`.
    pub fn engine_args(&self, listen: SocketAddr) -> Vec<String> {
        let mut args = vec![
            "--listen".to_string(),
            listen.ip().to_string(),
            "--port".to_string(),
            listen.port().to_string(),
        ];
        match &self.strategy {
            Some(spec) => {
                args.push("--strategy".to_string());
                args.push(spec.clone());
            }
            None => args.push("--auto".to_string()),
        }
        if self.doh {
            args.push("--doh".to_string());
        }
        if self.drop_quic {
            args.push("--drop-quic".to_string());
        }
        match self.ip.as_str() {
            "v6" => args.push("--ipv6".to_string()),
            "both" => {}
            _ => args.push("--ipv4-only".to_string()),
        }
        args.extend(self.extra.iter().cloned());
        args
    }
}

fn search_dirs() -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Ok(exe) = std::env::current_exe() {
        if let Some(here) = exe.parent() {
            dirs.push(here.to_path_buf());
            dirs.push(here.join("bypass"));
        }
    }
    dirs.push(PathBuf::from("."));
    dirs.push(PathBuf::from("bypass"));
    if let Ok(path) = std::env::var("PATH") {
        dirs.extend(std::env::split_paths(&path));
    }
    dirs
}

/// Where the engine is: `--bypass-bin`, else next to oryvexcore (the Android app ships it as
/// `liboryvex_bypass.so` in the same folder), else on the PATH.
pub fn binary() -> Option<PathBuf> {
    if let Some(given) = env_value("ORYVEXCORE_BYPASS_BIN")
        .map(PathBuf::from)
        .filter(|p| p.is_file())
    {
        return Some(given);
    }
    let suffix = if cfg!(windows) { ".exe" } else { "" };
    for dir in search_dirs() {
        for name in BINARY_NAMES {
            let plain = dir.join(name);
            if plain.is_file() {
                return Some(plain);
            }
            if !suffix.is_empty() {
                let with_suffix = dir.join(format!("{name}{suffix}"));
                if with_suffix.is_file() {
                    return Some(with_suffix);
                }
            }
        }
    }
    None
}

fn install_hint() -> String {
    "the bypass engine (oryvex-bypass) was not found next to oryvexcore. Build it with \
     `make -C oryvexcore/bypass` and put it beside the core, or name it with --bypass-bin"
        .to_string()
}

fn http_listen() -> Option<SocketAddr> {
    env_value("ORYVEXCORE_HTTP_PROXY").and_then(|v| v.parse().ok())
}

/// Serves the Bypass route on `listen` until the engine ends or the core is stopped.
pub async fn run(listen: SocketAddr) -> Result<()> {
    let exe = binary().ok_or_else(|| OryvexCoreError::Other(install_hint()))?;
    let options = Options::from_env();
    log::info!("[*] bypass route: no tunnel, the first packets of each connection are reshaped");
    log::info!("[*] starting the bypass engine from {}", exe.display());

    let mut command = Command::new(&exe);
    command
        .args(options.engine_args(listen))
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    #[cfg(windows)]
    {
        command.creation_flags(0x0800_0000); // CREATE_NO_WINDOW
    }

    let mut child = command
        .spawn()
        .map_err(|e| OryvexCoreError::Other(format!("the bypass engine would not start: {e}")))?;

    // The engine ends by itself when its stdin closes, so it never outlives the core.
    let mut stdin = child
        .stdin
        .take()
        .ok_or_else(|| OryvexCoreError::Other("the bypass engine gave no command stream".into()))?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| OryvexCoreError::Other("the bypass engine gave no event stream".into()))?;
    if let Some(err) = child.stderr.take() {
        tokio::spawn(async move {
            let mut lines = BufReader::new(err).lines();
            while let Ok(Some(line)) = lines.next_line().await {
                log::debug!("[bypass] {line}");
            }
        });
    }

    let mut lines = BufReader::new(stdout).lines();
    let deadline = tokio::time::Instant::now() + Duration::from_secs(READY_TIMEOUT_SECS);
    let port = loop {
        match tokio::time::timeout_at(deadline, lines.next_line()).await {
            Err(_) => {
                return Err(OryvexCoreError::Other(
                    "the bypass engine did not start in time".into(),
                ))
            }
            Ok(Err(e)) => return Err(OryvexCoreError::Other(format!("bypass engine: {e}"))),
            Ok(Ok(None)) => {
                return Err(OryvexCoreError::Other(format!(
                    "the bypass engine stopped before it was ready; is {listen} already in use?"
                )))
            }
            Ok(Ok(Some(line))) => {
                let value: serde_json::Value = match serde_json::from_str(&line) {
                    Ok(v) => v,
                    Err(_) => {
                        log::debug!("[bypass] {line}");
                        continue;
                    }
                };
                match value["type"].as_str() {
                    Some("ready") => {
                        break value["port"]
                            .as_u64()
                            .and_then(|p| u16::try_from(p).ok())
                            .unwrap_or(listen.port());
                    }
                    Some("error") => {
                        return Err(OryvexCoreError::Other(format!(
                            "the bypass engine could not start: {}",
                            value["msg"].as_str().unwrap_or("unknown reason")
                        )))
                    }
                    _ => log::debug!("[bypass] {line}"),
                }
            }
        }
    };

    let served = SocketAddr::new(listen.ip(), port);
    log::info!("[+] socks5 server listening on {served}");

    // The engine also takes HTTP proxy requests on its own port, so an http proxy address (the
    // Windows system proxy) is a plain forwarder to it.
    if let Some(http) = http_listen() {
        let listener = crate::socks::bind_listener("http proxy", http, "--http-proxy").await?;
        let target = if served.ip().is_unspecified() {
            SocketAddr::new(Ipv4Addr::LOCALHOST.into(), port)
        } else {
            served
        };
        log::info!("[+] http proxy listening on {http}");
        tokio::spawn(async move {
            loop {
                let (mut inbound, _) = match listener.accept().await {
                    Ok(pair) => pair,
                    Err(e) => {
                        log::warn!("[bypass] http proxy accept: {e}");
                        tokio::time::sleep(Duration::from_millis(200)).await;
                        continue;
                    }
                };
                tokio::spawn(async move {
                    if let Ok(mut outbound) = tokio::net::TcpStream::connect(target).await {
                        let _ = tokio::io::copy_bidirectional(&mut inbound, &mut outbound).await;
                    }
                });
            }
        });
    }
    log::info!("[+] bypass is ready; {served} reaches the internet directly, with its first packets reshaped");

    let mut tick = tokio::time::interval(Duration::from_secs(STATS_POLL_SECS));
    tick.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
    let mut seen_up = 0u64;
    let mut seen_down = 0u64;

    loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                let _ = stdin.write_all(b"STOP\n").await;
                let _ = stdin.flush().await;
                return Ok(());
            }
            status = child.wait() => {
                let how = match status {
                    Ok(s) => s.to_string(),
                    Err(e) => e.to_string(),
                };
                return Err(OryvexCoreError::Other(format!("the bypass engine ended ({how})")));
            }
            _ = tick.tick() => {
                if stats::enabled() {
                    let _ = stdin.write_all(b"STATS\n").await;
                    let _ = stdin.flush().await;
                }
            }
            line = lines.next_line() => {
                match line {
                    Ok(Some(text)) => count_traffic(&text, &mut seen_up, &mut seen_down),
                    Ok(None) | Err(_) => {
                        return Err(OryvexCoreError::Other("the bypass engine closed its stream".into()));
                    }
                }
            }
        }
    }
}

/// One line from the engine. Its stats lines feed the core's traffic counters, which the
/// `[=] up ... down ...` line is made from; everything else is for the debug log.
fn count_traffic(line: &str, seen_up: &mut u64, seen_down: &mut u64) {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(line) else {
        log::debug!("[bypass] {line}");
        return;
    };
    match value["type"].as_str() {
        Some("stats") => {
            let up = value["bytes_up"].as_u64().unwrap_or(*seen_up);
            let down = value["bytes_down"].as_u64().unwrap_or(*seen_down);
            stats::add_up(up.saturating_sub(*seen_up).min(usize::MAX as u64) as usize);
            stats::add_down(down.saturating_sub(*seen_down).min(usize::MAX as u64) as usize);
            *seen_up = up;
            *seen_down = down;
        }
        Some("error") => log::warn!(
            "[bypass] {}",
            value["msg"].as_str().unwrap_or("the engine reported an error")
        ),
        _ => log::debug!("[bypass] {line}"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn listen() -> SocketAddr {
        "127.0.0.1:1819".parse().unwrap()
    }

    #[test]
    fn the_default_is_auto_with_the_resolver_and_no_quic_on_ipv4() {
        let args = Options::default().engine_args(listen());
        assert_eq!(
            args,
            vec!["--listen", "127.0.0.1", "--port", "1819", "--auto", "--doh", "--drop-quic", "--ipv4-only"]
        );
    }

    #[test]
    fn a_fixed_strategy_replaces_auto() {
        let o = Options {
            strategy: Some("fake(ttl=4),split(sni)".into()),
            doh: false,
            drop_quic: false,
            ip: "both".into(),
            extra: vec!["--decoy-name".into(), "example.org".into()],
        };
        let args = o.engine_args(listen());
        assert!(args.contains(&"--strategy".to_string()));
        assert!(!args.contains(&"--auto".to_string()));
        assert!(!args.contains(&"--doh".to_string()));
        assert!(!args.contains(&"--ipv4-only".to_string()));
        assert_eq!(args.last().map(String::as_str), Some("example.org"));
    }

    #[test]
    fn ipv6_prefers_ipv6() {
        let o = Options { ip: "v6".into(), ..Options::default() };
        assert!(o.engine_args(listen()).contains(&"--ipv6".to_string()));
    }

    #[test]
    fn traffic_is_counted_as_the_difference_between_stats_lines() {
        let (mut up, mut down) = (0u64, 0u64);
        count_traffic(r#"{"type":"stats","bytes_up":10,"bytes_down":20}"#, &mut up, &mut down);
        assert_eq!((up, down), (10, 20));
        count_traffic(r#"{"type":"stats","bytes_up":15,"bytes_down":20}"#, &mut up, &mut down);
        assert_eq!((up, down), (15, 20));
        count_traffic("not json", &mut up, &mut down);
        assert_eq!((up, down), (15, 20));
    }
}
