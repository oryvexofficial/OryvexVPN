use std::net::SocketAddr;
use std::path::PathBuf;

use crate::error::{OryvexCoreError, Result};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Mode {
    Off,
    Chain,
    Reverse,
    Only,
}

impl Mode {
    pub fn label(self) -> &'static str {
        match self {
            Mode::Off => "off",
            Mode::Chain => "tor through the tunnel",
            Mode::Reverse => "the tunnel through tor",
            Mode::Only => "tor alone",
        }
    }
}

pub fn mode() -> Mode {
    let raw = match std::env::var("ORYVEXCORE_TOR") {
        Ok(value) => value.trim().to_lowercase(),
        Err(_) => return Mode::Off,
    };

    match raw.as_str() {
        "" | "0" | "off" | "false" | "no" => Mode::Off,
        "reverse" | "rev" | "warp-over-tor" => Mode::Reverse,
        "only" | "alone" | "tor-only" | "direct" => Mode::Only,
        _ => Mode::Chain,
    }
}

pub fn listen_address() -> SocketAddr {
    std::env::var("ORYVEXCORE_TOR_BIND")
        .ok()
        .and_then(|value| value.trim().parse().ok())
        .unwrap_or_else(|| "127.0.0.1:1820".parse().expect("a literal address"))
}

pub fn http_listen_address() -> Option<SocketAddr> {
    std::env::var("ORYVEXCORE_TOR_HTTP")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty() && value != "off")
        .and_then(|value| value.parse().ok())
}

pub fn state_dir(base_config: &str) -> PathBuf {
    if let Some(dir) = std::env::var("ORYVEXCORE_TOR_DIR")
        .ok()
        .filter(|d| !d.trim().is_empty())
    {
        return PathBuf::from(dir.trim());
    }

    let config = PathBuf::from(base_config);
    let stem = config
        .file_stem()
        .map(|name| name.to_string_lossy().to_string())
        .unwrap_or_else(|| "oryvexcore".to_string());

    match config.parent() {
        Some(parent) if !parent.as_os_str().is_empty() => parent.join(format!("{stem}-tor")),
        _ => PathBuf::from(format!("{stem}-tor")),
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Bridges {
    Disabled,
    Manual(Vec<String>),
    Auto { forced: bool },
}

pub fn bridges_from_file() -> Vec<String> {
    let path = match std::env::var("ORYVEXCORE_TOR_BRIDGE_FILE") {
        Ok(value) if !value.trim().is_empty() => value.trim().to_string(),
        _ => return Vec::new(),
    };

    let text = match std::fs::read_to_string(&path) {
        Ok(text) => text,
        Err(e) => {
            log::warn!("[-] cannot read the bridge file {path}: {e}");
            return Vec::new();
        }
    };

    let lines = read_bridge_lines(&text);
    if lines.is_empty() {
        log::warn!("[-] the bridge file {path} held no bridge line");
    } else {
        log::info!("[+] {} bridge(s) read from {path}", lines.len());
    }
    lines
}

pub fn read_bridge_lines(text: &str) -> Vec<String> {
    text.lines()
        .map(|line| line.trim())
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .map(|line| {
            line.strip_prefix("Bridge ")
                .or_else(|| line.strip_prefix("bridge "))
                .unwrap_or(line)
                .trim()
                .to_string()
        })
        .filter(|line| !line.is_empty())
        .collect()
}

pub fn bridges() -> Bridges {
    let from_file = bridges_from_file();
    let raw = std::env::var("ORYVEXCORE_TOR_BRIDGES").unwrap_or_default();
    let trimmed = raw.trim();

    if !from_file.is_empty() {
        let mut lines = from_file;
        if !matches!(
            trimmed.to_lowercase().as_str(),
            "" | "off"
                | "no"
                | "0"
                | "false"
                | "none"
                | "auto"
                | "on"
                | "1"
                | "yes"
                | "true"
                | "force"
        ) {
            lines.extend(read_bridge_lines(&trimmed.replace(';', "\n")));
        }
        return Bridges::Manual(lines);
    }

    match trimmed.to_lowercase().as_str() {
        "" => Bridges::Auto { forced: false },
        "off" | "no" | "0" | "false" | "none" => Bridges::Disabled,
        "auto" | "on" | "1" | "yes" | "true" | "force" => Bridges::Auto { forced: true },
        _ => {
            let lines: Vec<String> = trimmed
                .split(['\n', ';'])
                .map(|line| line.trim().to_string())
                .filter(|line| !line.is_empty())
                .collect();

            if lines.is_empty() {
                Bridges::Auto { forced: false }
            } else {
                Bridges::Manual(lines)
            }
        }
    }
}

pub fn bridge_lines() -> Vec<String> {
    match bridges() {
        Bridges::Manual(lines) => lines,
        _ => Vec::new(),
    }
}

pub fn transports() -> Vec<(String, String)> {
    std::env::var("ORYVEXCORE_TOR_PT")
        .unwrap_or_default()
        .split(['\n', ';'])
        .filter_map(|entry| {
            let entry = entry.trim();
            if entry.is_empty() {
                return None;
            }
            match entry.split_once('=') {
                Some((protocol, path)) => {
                    Some((protocol.trim().to_string(), path.trim().to_string()))
                }
                None => Some(("obfs4".to_string(), entry.to_string())),
            }
        })
        .collect()
}

#[cfg(not(feature = "tor"))]
fn unsupported() -> OryvexCoreError {
    OryvexCoreError::Other(
        "this build has no tor support; rebuild with `cargo build --release --features tor`".into(),
    )
}

#[cfg(not(feature = "tor"))]
pub async fn run_chain(_through: SocketAddr, _state: PathBuf) -> Result<()> {
    Err(unsupported())
}

#[cfg(not(feature = "tor"))]
pub async fn run_only(
    _listener: tokio::net::TcpListener,
    _listen: SocketAddr,
    _state: PathBuf,
) -> Result<()> {
    Err(unsupported())
}

#[cfg(not(feature = "tor"))]
pub async fn start_reverse(_state: PathBuf) -> Result<(SocketAddr, tokio::task::AbortHandle)> {
    Err(unsupported())
}

#[cfg(feature = "tor")]
pub use with_tor::{run_chain, run_only, start_reverse};

#[cfg(feature = "tor")]
mod with_tor {
    use super::*;

    use std::collections::BTreeMap;
    use std::path::Path;
    use std::time::Duration;

    use arti_client::config::{BridgeConfigBuilder, CfgPath, TorClientConfigBuilder};
    use arti_client::{TorClient, TorClientConfig};
    use tokio::net::TcpListener;
    use tor_chanmgr::ProxyProtocol;
    use tor_rtcompat::PreferredRuntime;

    use crate::bridges::{Plan, Transport};
    use crate::tor_exits::{ExitChoice, BEST_PROBES, FASTEST_CANDIDATES};

    pub type Client = std::sync::Arc<TorClient<PreferredRuntime>>;

    /// How long one exit country gets to open a test stream before the next is tried.
    const EXIT_PROBE: Duration = Duration::from_secs(30);

    const BOOTSTRAP_RETRY: Duration = Duration::from_secs(10);
    const DIRECT_PROBE: Duration = Duration::from_secs(75);
    const BRIDGE_PROBE: Duration = Duration::from_secs(360);
    const STALL_LIMIT: Duration = Duration::from_secs(75);
    const STALL_CHECK: Duration = Duration::from_secs(5);
    const PROOF_LIMIT: Duration = Duration::from_secs(45);
    const WAVE_TRIES: usize = 2;
    const FOREVER: usize = usize::MAX;

    fn init_tracing() {
        use tracing_subscriber::filter::EnvFilter;

        let wanted = std::env::var("ORYVEXCORE_TOR_LOG")
            .ok()
            .filter(|value| !value.trim().is_empty())
            .unwrap_or_else(|| match std::env::var("ORYVEXCORE_LOG_LEVEL").as_deref() {
                Ok("debug") | Ok("trace") => "debug".to_string(),
                _ => "info".to_string(),
            });

        let filter = EnvFilter::try_new(&wanted).unwrap_or_else(|_| EnvFilter::new("info"));
        let _ = tracing_subscriber::fmt()
            .with_env_filter(filter)
            .with_writer(std::io::stderr)
            .with_target(true)
            .try_init();
    }
    const REVERSE_ATTEMPTS: usize = 3;

    fn direct_probe() -> Duration {
        std::env::var("ORYVEXCORE_TOR_DIRECT_SECS")
            .ok()
            .and_then(|value| value.trim().parse().ok())
            .map(Duration::from_secs)
            .unwrap_or(DIRECT_PROBE)
    }

    fn manual_transports() -> Vec<Transport> {
        let mut grouped: Vec<Transport> = Vec::new();

        for (protocol, path) in transports() {
            let path = PathBuf::from(path);
            match grouped.iter_mut().find(|held| held.path == path) {
                Some(held) if !held.protocols.contains(&protocol) => held.protocols.push(protocol),
                Some(_) => {}
                None => grouped.push(Transport {
                    protocols: vec![protocol],
                    path,
                }),
            }
        }

        grouped
    }

    fn announce(plan: &Plan) {
        let mut kinds: BTreeMap<String, usize> = BTreeMap::new();
        for line in &plan.lines {
            let kind = crate::bridges::transport_of(line).unwrap_or_else(|| "vanilla".to_string());
            *kinds.entry(kind).or_default() += 1;
        }

        if !plan.lines.is_empty() {
            let summary: Vec<String> = kinds
                .iter()
                .map(|(kind, count)| format!("{count} {kind}"))
                .collect();
            log::info!(
                "[+] tor has {} bridge(s) {}: {}",
                plan.lines.len(),
                plan.source,
                summary.join(", ")
            );
        }

        for transport in &plan.transports {
            log::info!(
                "[+] {} speaks {}",
                transport.path.display(),
                transport.protocols.join(", ")
            );
        }

        if !plan.missing.is_empty() {
            log::warn!(
                "[-] nothing here can speak {}; {}",
                plan.missing.join(", "),
                crate::bridges::install_hint()
            );
        }
    }

    async fn auto_plan(state: &Path, through: Option<SocketAddr>) -> Plan {
        let (lines, source) = crate::bridges::fetch(state, through).await;
        let lines = crate::bridges::keep_reachable(lines, through).await;
        let plan = crate::bridges::plan(lines, source, manual_transports());
        announce(&plan);
        plan
    }

    fn build_config(
        state: &Path,
        through: Option<SocketAddr>,
        plan: Option<&Plan>,
        slot: Option<&str>,
    ) -> Result<TorClientConfig> {
        prepare_dir(state)?;
        let home = match slot {
            Some(name) => state.join("attempts").join(name),
            None => state.to_path_buf(),
        };
        let cache = home.join("cache");
        let data = home.join("state");
        prepare_dir(&home)?;
        prepare_dir(&cache)?;
        prepare_dir(&data)?;

        let mut builder = TorClientConfigBuilder::default();
        builder
            .storage()
            .cache_dir(CfgPath::new(cache.to_string_lossy().to_string()));
        builder
            .storage()
            .state_dir(CfgPath::new(data.to_string_lossy().to_string()));

        // Without a tunnel to dial through, tor leaves through the upstream proxy, if there is one.
        if let Some(proxy) = through.or_else(upstream_socks) {
            let parsed: ProxyProtocol = format!("socks5://{proxy}")
                .parse()
                .map_err(|e| OryvexCoreError::Other(format!("tor cannot dial through {proxy}: {e}")))?;
            builder.channel().outbound_proxy(parsed);
        } else if let Some(proxy) = crate::upstream::configured() {
            // Connecting directly would leave outside the proxy oryvexcore was told to dial through.
            return Err(OryvexCoreError::Other(format!(
                "tor cannot dial through the upstream proxy at {}: it takes a socks5 address without a password",
                proxy.endpoint()
            )));
        }

        if let Some(plan) = plan {
            let mut taken = 0usize;
            for line in &plan.lines {
                match line.parse::<BridgeConfigBuilder>() {
                    Ok(bridge) => {
                        builder.bridges().bridges().push(bridge);
                        taken += 1;
                    }
                    Err(e) => log::warn!("[-] skipping a bridge tor cannot read: {e}"),
                }
            }

            if taken == 0 {
                return Err(OryvexCoreError::Other(
                    "none of the bridges could be read by tor".into(),
                ));
            }

            for transport in &plan.transports {
                let mut named = Vec::new();
                for protocol in &transport.protocols {
                    named.push(
                        protocol.parse().map_err(|e| {
                            OryvexCoreError::Other(format!("transport '{protocol}': {e}"))
                        })?,
                    );
                }

                let mut entry = arti_client::config::pt::TransportConfigBuilder::default();
                entry
                    .protocols(named)
                    .path(CfgPath::new(transport.path.to_string_lossy().to_string()))
                    .run_on_startup(true);
                builder.bridges().transports().push(entry);
            }
        }

        builder
            .build()
            .map_err(|e| OryvexCoreError::Other(format!("tor configuration: {e}")))
    }

    struct AbortOnDrop(tokio::task::AbortHandle);

    impl Drop for AbortOnDrop {
        fn drop(&mut self) {
            self.0.abort();
        }
    }

    struct Sleeper {
        client: Client,
        keep: bool,
    }

    impl Drop for Sleeper {
        fn drop(&mut self) {
            if !self.keep {
                self.client.set_dormant(arti_client::DormantMode::Soft);
            }
        }
    }

    fn watch_progress(
        client: Client,
        label: &'static str,
        seen: std::sync::Arc<std::sync::atomic::AtomicU64>,
        started: std::time::Instant,
    ) -> AbortOnDrop {
        let task = tokio::spawn(async move {
            use futures::StreamExt;
            use std::sync::atomic::Ordering;

            let mut events = client.bootstrap_events();
            let mut shown = String::new();
            let mut best = 0u64;

            while let Some(status) = events.next().await {
                let reached = (status.as_frac().max(0.0) * 1000.0).round() as u64;
                if reached > best {
                    best = reached;
                    seen.store(started.elapsed().as_secs(), Ordering::Relaxed);
                }

                let line = status.to_string();
                if line == shown {
                    continue;
                }
                shown = line.clone();

                if status.blocked().is_some() {
                    log::warn!("[-] tor {label}: {line}");
                } else {
                    log::info!("[*] tor {label}: {line}");
                }
            }
        });

        AbortOnDrop(task.abort_handle())
    }

    async fn boot(
        config: TorClientConfig,
        label: &'static str,
        stall: Option<Duration>,
    ) -> Result<Client> {
        use std::sync::atomic::{AtomicU64, Ordering};

        let client = TorClient::builder()
            .config(config)
            .create_unbootstrapped()
            .map_err(|e| OryvexCoreError::Other(format!("tor client: {e}")))?;

        let started = std::time::Instant::now();
        let seen = std::sync::Arc::new(AtomicU64::new(0));
        let _watcher = watch_progress(client.clone(), label, seen.clone(), started);
        let mut sleeper = Sleeper {
            client: client.clone(),
            keep: false,
        };

        let booted: Result<()> = match stall {
            None => client
                .bootstrap()
                .await
                .map_err(|e| OryvexCoreError::Other(format!("{e}"))),
            Some(limit) => {
                let handle = client.clone();
                let running = async move { handle.bootstrap().await };
                tokio::pin!(running);

                loop {
                    tokio::select! {
                        outcome = &mut running => {
                            break outcome.map_err(|e| OryvexCoreError::Other(format!("{e}")));
                        }
                        _ = tokio::time::sleep(STALL_CHECK) => {
                            let quiet = started
                                .elapsed()
                                .as_secs()
                                .saturating_sub(seen.load(Ordering::Relaxed));

                            if quiet >= limit.as_secs() {
                                break Err(OryvexCoreError::Other(format!("no headway for {quiet}s")));
                            }
                        }
                    }
                }
            }
        };

        booted?;
        prove(&client, label).await?;

        sleeper.keep = true;
        Ok(client)
    }

    fn proof_target() -> (String, u16) {
        let raw = std::env::var("ORYVEXCORE_TOR_CHECK").unwrap_or_default();
        let raw = raw.trim();

        if raw.is_empty() {
            return ("check.torproject.org".to_string(), 443);
        }

        match raw.rsplit_once(':') {
            Some((host, port)) => (host.to_string(), port.parse().unwrap_or(443)),
            None => (raw.to_string(), 443),
        }
    }

    async fn prove(client: &Client, label: &'static str) -> Result<()> {
        let (host, port) = proof_target();
        log::info!("[*] tor {label}: trying a way out through {host}:{port}");

        match tokio::time::timeout(PROOF_LIMIT, client.connect((host.as_str(), port))).await {
            Ok(Ok(_stream)) => {
                log::info!("[+] tor {label}: the way out is open");
                Ok(())
            }
            Ok(Err(e)) => Err(OryvexCoreError::Other(format!(
                "tor came up but could not reach {host}:{port}: {e}"
            ))),
            Err(_) => Err(OryvexCoreError::Other(format!(
                "tor came up but {host}:{port} stayed silent for {}s",
                PROOF_LIMIT.as_secs()
            ))),
        }
    }

    async fn stage(
        state: &Path,
        through: Option<SocketAddr>,
        plan: Option<&Plan>,
        label: &'static str,
        attempts: usize,
        deadline: Option<Duration>,
        stall: Option<Duration>,
        slot: Option<&str>,
    ) -> Result<Client> {
        let mut tried = 0usize;
        loop {
            tried += 1;
            let config = build_config(state, through, plan, slot)?;
            let run = boot(config, label, stall);

            let outcome = match deadline {
                Some(limit) => match tokio::time::timeout(limit, run).await {
                    Ok(result) => result,
                    Err(_) => Err(OryvexCoreError::Other(format!(
                        "no answer in {}s",
                        limit.as_secs()
                    ))),
                },
                None => run.await,
            };

            match outcome {
                Ok(client) => return Ok(client),
                Err(e) if tried >= attempts => return Err(e),
                Err(e) => {
                    log::warn!("[-] tor {label} failed: {e}; trying again in {BOOTSTRAP_RETRY:?}");
                    tokio::time::sleep(BOOTSTRAP_RETRY).await;
                }
            }
        }
    }

    async fn establish(state: &Path, through: Option<SocketAddr>, rounds: usize) -> Result<Client> {
        let policy = bridges();

        if let Bridges::Manual(lines) = &policy {
            let plan = crate::bridges::plan(lines.clone(), "given by hand", manual_transports());
            announce(&plan);
            if plan.is_empty() {
                return Err(OryvexCoreError::Other(format!(
                    "the bridges you gave need a pluggable transport that is not installed; {}",
                    crate::bridges::install_hint()
                )));
            }
            return stage(
                state,
                through,
                Some(&plan),
                "over your bridges",
                rounds,
                None,
                None,
                None,
            )
            .await;
        }

        let forced = matches!(policy, Bridges::Auto { forced: true });
        let may_fall_back = match (&policy, through) {
            (Bridges::Disabled, _) => false,
            (_, Some(_)) => forced,
            _ => true,
        };

        if !forced {
            let attempts = if may_fall_back { 1 } else { rounds };
            let deadline = may_fall_back.then(direct_probe);
            let tries = stage(
                state,
                through,
                None,
                "reaching the network",
                attempts,
                deadline,
                None,
                Some("direct"),
            );
            match tries.await {
                Ok(client) => return Ok(client),
                Err(e) if !may_fall_back => return Err(e),
                Err(e) => log::warn!("[-] tor could not get through on its own: {e}"),
            }
        }

        if through.is_some() {
            log::warn!(
                "[-] a pluggable transport dials for itself, outside the tunnel; plain bridges go \
                 through it, so they are the ones that work on a network which blocks tor outright"
            );
        }

        let plan = auto_plan(state, through).await;
        if plan.is_empty() {
            return Err(OryvexCoreError::Other(format!(
                "tor is blocked on this network and no pluggable transport is installed, so no \
                 bridge can be used; {}",
                crate::bridges::install_hint()
            )));
        }

        if let Some(client) = try_each_transport(state, through, &plan).await? {
            return Ok(client);
        }

        stage(
            state,
            through,
            Some(&plan),
            "over bridges",
            rounds,
            None,
            None,
            Some("all"),
        )
        .await
    }

    fn bridge_probe() -> Duration {
        std::env::var("ORYVEXCORE_TOR_BRIDGE_SECS")
            .ok()
            .and_then(|value| value.trim().parse().ok())
            .map(Duration::from_secs)
            .unwrap_or(BRIDGE_PROBE)
    }

    fn stall_limit() -> Duration {
        std::env::var("ORYVEXCORE_TOR_STALL_SECS")
            .ok()
            .and_then(|value| value.trim().parse().ok())
            .map(Duration::from_secs)
            .unwrap_or(STALL_LIMIT)
    }

    async fn try_each_transport(
        state: &Path,
        through: Option<SocketAddr>,
        plan: &Plan,
    ) -> Result<Option<Client>> {
        let worked = crate::bridges::recall(state);
        let waves = crate::bridges::waves(plan, worked.as_deref());
        if waves.is_empty() {
            return Ok(None);
        }

        let deadline = bridge_probe();
        let names: Vec<&str> = waves.iter().map(|(name, _)| name.as_str()).collect();
        log::info!("[*] tor will try {} in turn", names.join(", then "));

        for (name, wave) in &waves {
            for round in 1..=WAVE_TRIES {
                let mut only = wave.clone();
                crate::bridges::shuffle(&mut only.lines);

                let where_to: Vec<String> = only
                    .lines
                    .iter()
                    .filter_map(|line| crate::bridges::address_of(line))
                    .map(|address| address.to_string())
                    .collect();

                log::info!(
                    "[*] {name}: go {round} of {WAVE_TRIES}, dropped after {}s without headway, \
                     over {}",
                    stall_limit().as_secs(),
                    if where_to.is_empty() {
                        format!("{} bridge(s)", only.lines.len())
                    } else {
                        where_to.join(", ")
                    }
                );

                let outcome = stage(
                    state,
                    through,
                    Some(&only),
                    "over bridges",
                    1,
                    Some(deadline),
                    Some(stall_limit()),
                    Some(name.as_str()),
                )
                .await;

                match outcome {
                    Ok(client) => {
                        crate::bridges::remember(state, name);
                        log::info!("[+] {name} got through");
                        return Ok(Some(client));
                    }
                    Err(e) => log::warn!("[-] {name} did not get through: {e}"),
                }
            }
        }

        log::warn!("[-] no transport got through on its own; trying every bridge together");
        Ok(None)
    }

    /// Binds Tor's http proxy when one is asked for, with --tor-http.
    async fn bind_http() -> Result<Option<TcpListener>> {
        match http_listen_address() {
            Some(address) => Ok(Some(
                crate::socks::bind_listener("tor http proxy", address, "--tor-http").await?,
            )),
            None => Ok(None),
        }
    }

    // --- the exit ----------------------------------------------------------------------------

    /// What a stream asks of its exit. With the tor-exit-country feature it is arti's own
    /// stream preferences, which carry the exit country; without it there is nothing to ask.
    #[cfg(feature = "tor-exit-country")]
    type Prefs = arti_client::StreamPrefs;

    #[cfg(not(feature = "tor-exit-country"))]
    #[derive(Debug, Clone)]
    struct Prefs;

    /// Stream preferences that leave from `cc` (lowercase ISO code). Tor tells the country of
    /// each relay from its own bundled GeoIP table, so this asks no web service anything.
    #[cfg(feature = "tor-exit-country")]
    fn prefs_for(cc: &str) -> Option<Prefs> {
        let code: tor_geoip::CountryCode = match cc.to_uppercase().parse() {
            Ok(code) => code,
            Err(e) => {
                log::warn!("[-] tor exit: {} is no country tor knows: {e}", cc.to_uppercase());
                return None;
            }
        };
        let mut prefs = arti_client::StreamPrefs::new();
        prefs.exit_country(code);
        Some(prefs)
    }

    #[cfg(not(feature = "tor-exit-country"))]
    fn prefs_for(_cc: &str) -> Option<Prefs> {
        None
    }

    #[cfg(feature = "tor-exit-country")]
    async fn dial(
        client: &Client,
        host: &str,
        port: u16,
        prefs: Option<&Prefs>,
    ) -> std::result::Result<arti_client::DataStream, arti_client::Error> {
        match prefs {
            Some(prefs) => client.connect_with_prefs((host, port), prefs).await,
            None => client.connect((host, port)).await,
        }
    }

    #[cfg(not(feature = "tor-exit-country"))]
    async fn dial(
        client: &Client,
        host: &str,
        port: u16,
        _prefs: Option<&Prefs>,
    ) -> std::result::Result<arti_client::DataStream, arti_client::Error> {
        client.connect((host, port)).await
    }

    /// The same exit preferences in an isolation group of their own, so a stream dialled with
    /// them gets a circuit of its own: a separate exit relay to measure. The winner's group is
    /// kept, which keeps the proxy on the circuit that measured quickest.
    #[cfg(feature = "tor-exit-country")]
    fn isolated(prefs: &Prefs) -> Prefs {
        let mut fresh = prefs.clone();
        fresh.new_isolation_group();
        fresh
    }

    #[cfg(not(feature = "tor-exit-country"))]
    fn isolated(prefs: &Prefs) -> Prefs {
        prefs.clone()
    }

    /// `--tor-exit-best`: opens [BEST_PROBES] test streams through exits in `cc` side by side,
    /// each on its own circuit, and returns the quickest one's preferences, its time, the
    /// slowest answer and how many answered. None when no circuit there answered.
    async fn best_in_country(
        client: &Client,
        cc: &str,
        base: &Prefs,
        host: &str,
        port: u16,
    ) -> Option<(Prefs, Duration, Duration, usize)> {
        let upper = cc.to_uppercase();
        let probes = (0..BEST_PROBES).map(|_| {
            let client = client.clone();
            let host = host.to_string();
            let prefs = isolated(base);
            async move {
                let started = std::time::Instant::now();
                let outcome =
                    tokio::time::timeout(EXIT_PROBE, dial(&client, &host, port, Some(&prefs))).await;
                (prefs, started.elapsed(), outcome)
            }
        });
        let results = futures::future::join_all(probes).await;

        let mut answered = 0usize;
        let mut slowest = Duration::ZERO;
        let mut best: Option<(Prefs, Duration)> = None;
        for (n, (prefs, took, outcome)) in results.into_iter().enumerate() {
            match outcome {
                Ok(Ok(_stream)) => {
                    answered += 1;
                    log::info!(
                        "[*] tor exit: {upper} circuit {} of {BEST_PROBES} answered in {} ms",
                        n + 1,
                        took.as_millis()
                    );
                    if took > slowest {
                        slowest = took;
                    }
                    let better = match &best {
                        Some((_, held)) => took < *held,
                        None => true,
                    };
                    if better {
                        best = Some((prefs, took));
                    }
                }
                Ok(Err(e)) => log::warn!(
                    "[-] tor exit: {upper} circuit {} of {BEST_PROBES} did not answer: {e}",
                    n + 1
                ),
                Err(_) => log::warn!(
                    "[-] tor exit: {upper} circuit {} of {BEST_PROBES} stayed silent for {}s",
                    n + 1,
                    EXIT_PROBE.as_secs()
                ),
            }
        }
        best.map(|(prefs, took)| (prefs, took, slowest, answered))
    }

    fn exit_strict() -> bool {
        matches!(
            std::env::var("ORYVEXCORE_TOR_EXIT_STRICT")
                .unwrap_or_default()
                .trim()
                .to_lowercase()
                .as_str(),
            "1" | "true" | "yes" | "on"
        )
    }

    const AUTO_LINE: &str = "[+] tor exit: using auto (tor picks a fast exit, weighted by bandwidth)";

    /// Picks the exit the proxy leaves from, as `--tor-exit` asks, and says which in the log:
    /// every path ends in one "tor exit: using" line the apps wait for.
    async fn choose_exit(client: &Client, state: &Path) -> Result<Option<Prefs>> {
        let choice = crate::tor_exits::choice();
        let dir = crate::tor_exits::load(state);
        crate::tor_exits::announce(&dir);

        if choice == ExitChoice::Auto {
            log::info!("{AUTO_LINE}");
            return Ok(None);
        }
        if !cfg!(feature = "tor-exit-country") {
            log::warn!(
                "[-] tor exit: this build cannot pick an exit country (it was built without the \
                 tor-exit-country feature); --tor-exit {} is ignored",
                choice.label()
            );
            log::info!("{AUTO_LINE}");
            return Ok(None);
        }

        let (candidates, fastest) = match &choice {
            ExitChoice::Countries(list) => (list.clone(), false),
            _ => (dir.fastest_candidates(FASTEST_CANDIDATES), true),
        };
        let shown: Vec<String> = candidates.iter().map(|cc| cc.to_uppercase()).collect();
        if fastest {
            log::info!(
                "[*] tor exit: measuring {} countries for the fastest exit: {}",
                candidates.len(),
                shown.join(", ")
            );
        }

        let (host, port) = proof_target();
        let mut best: Option<(String, Duration, Prefs)> = None;
        let best_node = !fastest && crate::tor_exits::best_node();

        for cc in &candidates {
            let Some(prefs) = prefs_for(cc) else {
                continue;
            };
            let upper = cc.to_uppercase();
            if best_node {
                log::info!(
                    "[*] tor exit: trying {upper} ({}), measuring {BEST_PROBES} exits for the best one",
                    dir.name_of(cc)
                );
                match best_in_country(client, cc, &prefs, &host, port).await {
                    Some((chosen, took, slowest, answered)) => {
                        log::info!(
                            "[=] tor-exit-best {{\"cc\":\"{cc}\",\"probes\":{BEST_PROBES},\"answered\":{answered},\"ms\":{},\"slowest_ms\":{}}}",
                            took.as_millis(),
                            slowest.as_millis()
                        );
                        log::info!(
                            "[+] tor exit: using {cc} ({}), the best of {answered} exits, answered in {} ms",
                            dir.name_of(cc),
                            took.as_millis()
                        );
                        return Ok(Some(chosen));
                    }
                    None => {
                        log::warn!("[-] tor exit: no exit in {upper} answered");
                        continue;
                    }
                }
            }
            log::info!("[*] tor exit: trying {upper} ({})", dir.name_of(cc));
            let started = std::time::Instant::now();
            match tokio::time::timeout(EXIT_PROBE, dial(client, &host, port, Some(&prefs))).await {
                Ok(Ok(_stream)) => {
                    let took = started.elapsed();
                    log::info!("[*] tor exit: {upper} answered in {} ms", took.as_millis());
                    if !fastest {
                        log::info!(
                            "[+] tor exit: using {cc} ({}), answered in {} ms",
                            dir.name_of(cc),
                            took.as_millis()
                        );
                        return Ok(Some(prefs));
                    }
                    let better = match &best {
                        Some((_, held, _)) => took < *held,
                        None => true,
                    };
                    if better {
                        best = Some((cc.clone(), took, prefs));
                    }
                }
                Ok(Err(e)) => log::warn!("[-] tor exit: {upper} did not answer: {e}"),
                Err(_) => log::warn!(
                    "[-] tor exit: {upper} stayed silent for {}s",
                    EXIT_PROBE.as_secs()
                ),
            }
        }

        if let Some((cc, took, prefs)) = best {
            log::info!(
                "[+] tor exit: using {cc} ({}), the fastest at {} ms",
                dir.name_of(&cc),
                took.as_millis()
            );
            return Ok(Some(prefs));
        }

        if exit_strict() {
            return Err(OryvexCoreError::Other(format!(
                "no tor exit in {} answered, and --tor-exit-strict forbids any other",
                shown.join(", ")
            )));
        }
        log::warn!(
            "[-] tor exit: no exit in {} answered; leaving wherever tor picks",
            shown.join(", ")
        );
        log::info!("{AUTO_LINE}");
        Ok(None)
    }

    async fn serve(
        listener: TcpListener,
        http: Option<TcpListener>,
        client: Client,
        prefs: Option<Prefs>,
        kind: &'static str,
    ) -> Result<()> {
        let connector = move |host: String, port: u16| {
            let client = client.clone();
            let prefs = prefs.clone();
            async move {
                dial(&client, host.as_str(), port, prefs.as_ref())
                    .await
                    .map(|stream| {
                        use tokio_util::compat::FuturesAsyncReadCompatExt;
                        stream.compat()
                    })
                    .map_err(std::io::Error::other)
            }
        };

        // Served inside this future, so that it ends with it, letting go of its port, also when
        // the future is dropped as the core ends. Its failing leaves the socks5 one serving.
        let http_connector = connector.clone();
        let http_proxy = async move {
            if let Some(http_listener) = http {
                if let Err(e) = crate::socks::serve_http_connector(
                    http_listener,
                    "tor http proxy",
                    http_connector,
                )
                .await
                {
                    log::error!("[-] the tor http proxy stopped: {e}");
                }
            }
            std::future::pending::<std::convert::Infallible>().await
        };

        tokio::select! {
            outcome = crate::socks::serve_connector(listener, kind, connector) => outcome,
            never = http_proxy => match never {},
        }
    }

    /// The upstream proxy tor dials through when no tunnel carries it, see
    /// [crate::upstream::Upstream::socks_address].
    fn upstream_socks() -> Option<SocketAddr> {
        crate::upstream::configured()?.socks_address()
    }

    /// Says how tor reaches the network when no tunnel carries it: through the upstream proxy, or
    /// directly when there is none; with one tor cannot dial through, tor does not start.
    fn announce_upstream() {
        let Some(proxy) = crate::upstream::configured() else {
            return;
        };
        match proxy.socks_address() {
            Some(address) => {
                log::info!("[*] tor dials out through the upstream proxy at {address}")
            }
            None => log::warn!(
                "[-] tor cannot dial through the upstream proxy at {}, which is no socks5 address \
                 without a password; it does not connect directly instead",
                proxy.endpoint()
            ),
        }
    }

    /// Waits for the core's socks5 server on `through`: the core holds its listener from its start
    /// and answers once a tunnel serves it.
    async fn wait_for_proxy(through: SocketAddr) {
        crate::socks::until_answered(through, Duration::from_secs(2), || {
            log::info!("[*] tor is waiting for the tunnel proxy at {through}")
        })
        .await
    }

    pub async fn run_chain(through: SocketAddr, state: PathBuf) -> Result<()> {
        init_tracing();
        let listen = listen_address();
        // Both held from the start, as the core holds its own: the user dials them while the
        // tunnel and Tor come up, and no other program may take them meanwhile.
        let listener = crate::socks::bind_listener("tor socks5", listen, "--tor-bind").await?;
        let listen = listener.local_addr().unwrap_or(listen);
        let http = bind_http().await?;

        wait_for_proxy(through).await;
        log::info!("[*] bootstrapping tor through the tunnel at {through}");

        let client = establish(&state, Some(through), FOREVER).await?;
        log::info!("[+] tor is ready; {listen} leaves through tor, carried by the tunnel");
        let prefs = choose_exit(&client, &state).await?;
        tokio::spawn(crate::tor_exits::refresh_in_background(
            state.clone(),
            crate::socks::dialable(listen),
        ));

        serve(listener, http, client, prefs, "tor socks5").await
    }

    /// Tor with no tunnel underneath it, serving `listener`, which the core holds on `listen` from
    /// its start; its http proxy is held from the start as well.
    pub async fn run_only(listener: TcpListener, listen: SocketAddr, state: PathBuf) -> Result<()> {
        init_tracing();
        // The port the system gave, where --bind names port 0.
        let listen = listener.local_addr().unwrap_or(listen);
        let http = bind_http().await?;

        log::info!("[*] bootstrapping tor with no tunnel underneath it");
        announce_upstream();

        let client = establish(&state, None, FOREVER).await?;
        log::info!("[+] tor is ready; {listen} leaves through tor");
        let prefs = choose_exit(&client, &state).await?;
        tokio::spawn(crate::tor_exits::refresh_in_background(
            state.clone(),
            crate::socks::dialable(listen),
        ));

        serve(listener, http, client, prefs, "tor socks5").await
    }

    /// Starts Tor for the tunnel to be dialled through: its socks5 address, and the handle that
    /// ends it with the core.
    pub async fn start_reverse(state: PathBuf) -> Result<(SocketAddr, tokio::task::AbortHandle)> {
        init_tracing();
        let listen = listen_address();
        let listener = crate::socks::bind_listener("tor socks5", listen, "--tor-bind").await?;
        // Where the tunnel dials Tor: where its listener is bound, a port 0 asked for being the port
        // the system picked.
        let dialled = crate::socks::dialable(listener.local_addr().unwrap_or(listen));

        log::info!("[*] bootstrapping tor; the tunnel will be dialled through it");
        // The upstream is still the proxy oryvexcore was given: the caller points it at tor once tor is up.
        announce_upstream();

        let client = establish(&state, None, REVERSE_ATTEMPTS).await?;
        log::info!("[+] tor is ready; the tunnel goes out through {dialled}");

        let serving = tokio::spawn(async move {
            let served = match bind_http().await {
                // The tunnel's own exit is warp's: the tor exit country does not apply here.
                Ok(http) => serve(listener, http, client, None, "tor socks5").await,
                Err(e) => Err(e),
            };
            if let Err(e) = served {
                log::error!("[-] the tor proxy stopped: {e}");
            }
        });

        Ok((dialled, serving.abort_handle()))
    }

    fn prepare_dir(path: &Path) -> Result<()> {
        std::fs::create_dir_all(path)?;

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mut perms = std::fs::metadata(path)?.permissions();
            perms.set_mode(0o700);
            std::fs::set_permissions(path, perms)?;
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The hold on the tor settings of a test: the variables are the whole process's, and the
    /// tests run side by side, so each test holds them first, or one clearing them would wipe a
    /// value another had just set. They start out clear, and are cleared again as the hold is
    /// let go, also by a test that failed half way.
    struct SettingsHeld(std::sync::MutexGuard<'static, ()>);

    impl Drop for SettingsHeld {
        fn drop(&mut self) {
            clear();
        }
    }

    /// Waits for the hold on the tor settings, see `SettingsHeld`. A test that failed while it
    /// held them poisoned the lock, but cleared them all the same, so the lock is taken anyway.
    fn hold_settings() -> SettingsHeld {
        static SETTINGS: std::sync::OnceLock<std::sync::Mutex<()>> = std::sync::OnceLock::new();
        let held = SETTINGS
            .get_or_init(|| std::sync::Mutex::new(()))
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        clear();
        SettingsHeld(held)
    }

    fn clear() {
        std::env::remove_var("ORYVEXCORE_TOR");
        std::env::remove_var("ORYVEXCORE_TOR_DIR");
        std::env::remove_var("ORYVEXCORE_TOR_BIND");
        std::env::remove_var("ORYVEXCORE_TOR_BRIDGES");
        std::env::remove_var("ORYVEXCORE_TOR_PT");
        std::env::remove_var("ORYVEXCORE_TOR_EXIT");
        std::env::remove_var("ORYVEXCORE_TOR_EXIT_STRICT");
        std::env::remove_var("ORYVEXCORE_TOR_EXIT_BEST");
    }

    #[test]
    fn every_mode_has_a_spelling() {
        let _settings = hold_settings();
        assert_eq!(mode(), Mode::Off);
        for written in ["1", "on", "chain", "yes"] {
            std::env::set_var("ORYVEXCORE_TOR", written);
            assert_eq!(mode(), Mode::Chain, "{written}");
        }
        for written in ["reverse", "rev", "warp-over-tor"] {
            std::env::set_var("ORYVEXCORE_TOR", written);
            assert_eq!(mode(), Mode::Reverse, "{written}");
        }
        for written in ["only", "alone", "tor-only", "direct"] {
            std::env::set_var("ORYVEXCORE_TOR", written);
            assert_eq!(mode(), Mode::Only, "{written}");
        }
        for written in ["0", "off", "false", "no"] {
            std::env::set_var("ORYVEXCORE_TOR", written);
            assert_eq!(mode(), Mode::Off, "{written}");
        }
    }

    #[test]
    fn the_state_dir_sits_beside_the_identity_file() {
        let _settings = hold_settings();
        assert_eq!(state_dir("oryvexcore.toml"), PathBuf::from("oryvexcore-tor"));
        assert_eq!(
            state_dir("/etc/oryvexcore/oryvexcore.toml"),
            PathBuf::from("/etc/oryvexcore/oryvexcore-tor")
        );
        std::env::set_var("ORYVEXCORE_TOR_DIR", "/var/lib/oryvexcore-tor");
        assert_eq!(
            state_dir("oryvexcore.toml"),
            PathBuf::from("/var/lib/oryvexcore-tor")
        );
    }

    #[test]
    fn the_tor_listener_has_a_default_of_its_own() {
        let _settings = hold_settings();
        assert_eq!(listen_address(), "127.0.0.1:1820".parse().unwrap());
        std::env::set_var("ORYVEXCORE_TOR_BIND", "127.0.0.1:9150");
        assert_eq!(listen_address(), "127.0.0.1:9150".parse().unwrap());
    }

    #[test]
    fn bridges_are_read_one_per_entry() {
        let _settings = hold_settings();
        assert!(bridge_lines().is_empty());
        std::env::set_var(
            "ORYVEXCORE_TOR_BRIDGES",
            "obfs4 192.0.2.55:38114 316E64 cert=abc iat-mode=0 ; obfs4 198.51.100.25:443 7DD627 cert=def",
        );
        let lines = bridge_lines();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].starts_with("obfs4 192.0.2.55"));
        assert!(lines[1].starts_with("obfs4 198.51.100.25"));
    }

    #[test]
    fn a_transport_may_be_named_or_assumed_to_be_obfs4() {
        let _settings = hold_settings();
        assert!(transports().is_empty());
        std::env::set_var("ORYVEXCORE_TOR_PT", "/usr/bin/lyrebird");
        assert_eq!(
            transports(),
            vec![("obfs4".to_string(), "/usr/bin/lyrebird".to_string())]
        );
        std::env::set_var(
            "ORYVEXCORE_TOR_PT",
            "obfs4=/usr/bin/lyrebird;snowflake=/usr/bin/snowflake-client",
        );
        assert_eq!(
            transports(),
            vec![
                ("obfs4".to_string(), "/usr/bin/lyrebird".to_string()),
                (
                    "snowflake".to_string(),
                    "/usr/bin/snowflake-client".to_string()
                ),
            ]
        );
    }
}

#[cfg(test)]
mod bridge_file_tests {
    use super::*;

    #[test]
    fn a_torrc_shaped_file_reads_line_by_line() {
        let text = "\
# my bridges
Bridge obfs4 1.2.3.4:443 ABCD cert=xx iat-mode=0

bridge obfs4 5.6.7.8:80 EF01 cert=yy iat-mode=0
9.9.9.9:443 0123456789012345678901234567890123456789
";
        let lines = read_bridge_lines(text);
        assert_eq!(lines.len(), 3);
        assert!(lines[0].starts_with("obfs4 1.2.3.4:443"));
        assert!(lines[1].starts_with("obfs4 5.6.7.8:80"));
        assert!(lines[2].starts_with("9.9.9.9:443"));
    }

    #[test]
    fn comments_and_blank_lines_carry_nothing() {
        assert!(read_bridge_lines("\n  \n# only a comment\n").is_empty());
    }
}
