//! Which Tor exit the proxy leaves from, and what exits there are to pick from.
//!
//! The choice comes from `--tor-exit` (`ORYVEXCORE_TOR_EXIT`):
//!
//! * `auto` (the default): tor picks an exit itself, weighted by bandwidth, as Tor Browser does;
//! * `fastest`: oryvexcore opens a test stream through exits in the best-served countries and
//!   keeps the country whose exit answered first;
//! * `de` or `de,nl,se`: leave from that country, the first that answers, in the order given.
//!
//! The list of exit countries is the exit directory: every running exit relay Onionoo knows,
//! counted per country. torproject.org is filtered on many networks, so the directory is never
//! fetched over the user's own connection: it is asked for through Tor itself, once Tor is up, and
//! kept on disk. Before the first fetch a bundled list stands in. The country each relay sits in
//! is worked out locally by tor from its own bundled GeoIP database, so picking an exit country
//! needs no web service at all.

use std::collections::BTreeMap;
use std::net::SocketAddr;
use std::path::Path;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

/// Onionoo's details endpoint. Overridable with `ORYVEXCORE_TOR_EXIT_API`, for a mirror.
const ONIONOO_DETAILS: &str = "https://onionoo.torproject.org/details";
const CACHE_FILE: &str = "exits.json";
/// The directory is fetched again in the background when the saved one is older than this.
const REFRESH_AFTER: Duration = Duration::from_secs(6 * 60 * 60);
const FETCH_TIMEOUT: Duration = Duration::from_secs(60);
/// How many countries `fastest` measures.
pub const FASTEST_CANDIDATES: usize = 6;
/// How many circuits `--tor-exit-best` measures side by side in the chosen country.
pub const BEST_PROBES: usize = 4;
/// How many of a country's strongest exit relays travel with the directory.
const TOP_RELAYS: usize = 5;

/// Every country that has hosted Tor exit relays in recent years, best served first. Used before
/// the first directory fetch, so the apps can offer every exit location from the start, and to
/// fill `fastest` when the directory is short. Same order as the apps' bundled list.
const BUNDLED: &[(&str, &str)] = &[
    ("de", "Germany"),
    ("nl", "Netherlands"),
    ("us", "United States"),
    ("fr", "France"),
    ("se", "Sweden"),
    ("ch", "Switzerland"),
    ("fi", "Finland"),
    ("ro", "Romania"),
    ("at", "Austria"),
    ("lu", "Luxembourg"),
    ("no", "Norway"),
    ("gb", "United Kingdom"),
    ("ca", "Canada"),
    ("pl", "Poland"),
    ("cz", "Czechia"),
    ("is", "Iceland"),
    ("md", "Moldova"),
    ("bg", "Bulgaria"),
    ("dk", "Denmark"),
    ("es", "Spain"),
    ("it", "Italy"),
    ("lt", "Lithuania"),
    ("lv", "Latvia"),
    ("ee", "Estonia"),
    ("ua", "Ukraine"),
    ("hu", "Hungary"),
    ("sg", "Singapore"),
    ("jp", "Japan"),
    ("hk", "Hong Kong"),
    ("au", "Australia"),
    ("br", "Brazil"),
    ("in", "India"),
    ("za", "South Africa"),
    ("tr", "Türkiye"),
    ("rs", "Serbia"),
    ("tw", "Taiwan"),
    ("vn", "Vietnam"),
    ("pe", "Peru"),
    ("az", "Azerbaijan"),
    ("be", "Belgium"),
    ("ie", "Ireland"),
    ("pt", "Portugal"),
    ("gr", "Greece"),
    ("sk", "Slovakia"),
    ("si", "Slovenia"),
    ("hr", "Croatia"),
    ("il", "Israel"),
    ("kr", "South Korea"),
    ("nz", "New Zealand"),
    ("ar", "Argentina"),
    ("cl", "Chile"),
    ("mx", "Mexico"),
    ("cr", "Costa Rica"),
    ("pa", "Panama"),
    ("ru", "Russia"),
    ("kz", "Kazakhstan"),
    ("th", "Thailand"),
    ("my", "Malaysia"),
    ("id", "Indonesia"),
    ("ph", "Philippines"),
    ("ae", "United Arab Emirates"),
    ("cy", "Cyprus"),
    ("mt", "Malta"),
    ("li", "Liechtenstein"),
    ("sc", "Seychelles"),
    ("bz", "Belize"),
    ("gi", "Gibraltar"),
    ("ge", "Georgia"),
    ("am", "Armenia"),
    ("al", "Albania"),
    ("mk", "North Macedonia"),
    ("ba", "Bosnia and Herzegovina"),
    ("ec", "Ecuador"),
    ("co", "Colombia"),
    ("uy", "Uruguay"),
    ("by", "Belarus"),
];

/// What `--tor-exit` asks for.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ExitChoice {
    Auto,
    Fastest,
    /// Lowercase ISO 3166-1 alpha-2 codes, in the order they are to be tried.
    Countries(Vec<String>),
}

impl ExitChoice {
    pub fn label(&self) -> String {
        match self {
            ExitChoice::Auto => "auto".to_string(),
            ExitChoice::Fastest => "fastest".to_string(),
            ExitChoice::Countries(list) => list
                .iter()
                .map(|cc| cc.to_uppercase())
                .collect::<Vec<_>>()
                .join(","),
        }
    }
}

/// Reads an exit choice as written on the command line. Anything unreadable is `auto`.
pub fn parse_choice(raw: &str) -> ExitChoice {
    let trimmed = raw.trim().to_lowercase();
    match trimmed.as_str() {
        "" | "auto" | "any" | "default" | "off" | "0" => return ExitChoice::Auto,
        "fastest" | "fast" | "best" | "speed" => return ExitChoice::Fastest,
        _ => {}
    }

    let mut countries: Vec<String> = Vec::new();
    for part in trimmed.split([',', ';', ' ', '|']) {
        let part = part.trim().trim_start_matches('{').trim_end_matches('}');
        if is_country_code(part) && !countries.iter().any(|held| held == part) {
            countries.push(part.to_string());
        }
    }

    if countries.is_empty() {
        log::warn!("[-] tor exit: cannot read --tor-exit {raw:?}; using auto");
        ExitChoice::Auto
    } else {
        ExitChoice::Countries(countries)
    }
}

pub fn is_country_code(text: &str) -> bool {
    text.len() == 2 && text.bytes().all(|b| b.is_ascii_lowercase())
}

/// The exit choice this run uses.
pub fn choice() -> ExitChoice {
    parse_choice(&std::env::var("ORYVEXCORE_TOR_EXIT").unwrap_or_default())
}

/// `--tor-exit-best`: with countries asked for, measure [BEST_PROBES] circuits through exits in
/// each and keep the quickest, instead of the first circuit tor builds there.
pub fn best_node() -> bool {
    matches!(
        std::env::var("ORYVEXCORE_TOR_EXIT_BEST")
            .unwrap_or_default()
            .trim()
            .to_lowercase()
            .as_str(),
        "1" | "true" | "yes" | "on"
    )
}

/// One of a country's strongest exit relays, as the directory carries it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExitRelay {
    /// The relay's nickname.
    pub nick: String,
    /// Its RSA fingerprint, 40 upper-case hex digits ("" when onionoo left it out).
    #[serde(default)]
    pub fp: String,
    /// Advertised bandwidth, bytes per second.
    #[serde(default)]
    pub bw: u64,
}

/// One country in the exit directory.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExitCountry {
    /// Lowercase ISO 3166-1 alpha-2.
    pub cc: String,
    /// English name, as Onionoo writes it.
    pub name: String,
    /// Running exit relays in the country (0 when unknown, for the bundled list).
    pub relays: u32,
    /// Their advertised bandwidth together, in bytes per second.
    pub bandwidth: u64,
    /// The share of exit traffic tor would send there by itself, 0..1.
    #[serde(default)]
    pub probability: f64,
    /// Its strongest exit relays, best first. Empty for the bundled list.
    #[serde(default)]
    pub top: Vec<ExitRelay>,
}

/// The exit directory: every exit country, best served first.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Directory {
    /// Unix seconds of the fetch, 0 for the bundled list.
    pub updated: u64,
    /// `onionoo` or `bundled`.
    pub source: String,
    pub countries: Vec<ExitCountry>,
}

impl Directory {
    pub fn bundled() -> Self {
        Directory {
            updated: 0,
            source: "bundled".to_string(),
            countries: BUNDLED
                .iter()
                .map(|(cc, name)| ExitCountry {
                    cc: cc.to_string(),
                    name: name.to_string(),
                    relays: 0,
                    bandwidth: 0,
                    probability: 0.0,
                    top: Vec::new(),
                })
                .collect(),
        }
    }

    pub fn total_relays(&self) -> u32 {
        self.countries.iter().map(|c| c.relays).sum()
    }

    pub fn find(&self, cc: &str) -> Option<&ExitCountry> {
        self.countries.iter().find(|c| c.cc == cc)
    }

    pub fn name_of(&self, cc: &str) -> String {
        self.find(cc)
            .map(|c| c.name.clone())
            .or_else(|| {
                BUNDLED
                    .iter()
                    .find(|(code, _)| *code == cc)
                    .map(|(_, name)| name.to_string())
            })
            .unwrap_or_else(|| cc.to_uppercase())
    }

    /// The countries `fastest` measures: the best served of the directory, topped up from the
    /// bundled order when the directory is short.
    pub fn fastest_candidates(&self, want: usize) -> Vec<String> {
        let mut out: Vec<String> = Vec::new();
        for country in &self.countries {
            if out.len() >= want {
                break;
            }
            // A country with one or two small exits is a poor bet for speed.
            if self.source != "bundled" && country.relays < 3 {
                continue;
            }
            out.push(country.cc.clone());
        }
        for (cc, _) in BUNDLED {
            if out.len() >= want {
                break;
            }
            if !out.iter().any(|held| held == cc) {
                out.push(cc.to_string());
            }
        }
        out
    }

    fn age(&self) -> Duration {
        Duration::from_secs(now().saturating_sub(self.updated))
    }

    pub fn is_stale(&self) -> bool {
        self.source == "bundled" || self.age() > REFRESH_AFTER
    }

    /// One compact JSON line for the apps: `{"updated":..,"source":..,"countries":[..]}`.
    pub fn to_line(&self) -> String {
        serde_json::to_string(self).unwrap_or_else(|_| "{}".to_string())
    }
}

#[derive(Debug, Deserialize)]
struct OnionooDetails {
    #[serde(default)]
    relays: Vec<OnionooRelay>,
}

#[derive(Debug, Deserialize)]
struct OnionooRelay {
    #[serde(default)]
    nickname: Option<String>,
    #[serde(default)]
    fingerprint: Option<String>,
    #[serde(default)]
    country: Option<String>,
    #[serde(default)]
    country_name: Option<String>,
    #[serde(default)]
    advertised_bandwidth: Option<u64>,
    #[serde(default)]
    exit_probability: Option<f64>,
    #[serde(default)]
    flags: Option<Vec<String>>,
    #[serde(default)]
    running: Option<bool>,
}

/// Counts an Onionoo details answer into a directory, best served country first.
pub fn summarize(body: &str) -> Option<Directory> {
    let details: OnionooDetails = serde_json::from_str(body).ok()?;
    let mut by_country: BTreeMap<String, ExitCountry> = BTreeMap::new();

    for relay in details.relays {
        if relay.running == Some(false) {
            continue;
        }
        let flags = relay.flags.unwrap_or_default();
        if !flags.iter().any(|f| f == "Exit") || flags.iter().any(|f| f == "BadExit") {
            continue;
        }
        let Some(cc) = relay.country.map(|c| c.trim().to_lowercase()) else {
            continue;
        };
        if !is_country_code(&cc) {
            continue;
        }

        let entry = by_country.entry(cc.clone()).or_insert_with(|| ExitCountry {
            cc: cc.clone(),
            name: relay
                .country_name
                .clone()
                .filter(|n| !n.trim().is_empty())
                .unwrap_or_else(|| cc.to_uppercase()),
            relays: 0,
            bandwidth: 0,
            probability: 0.0,
            top: Vec::new(),
        });
        let bandwidth = relay.advertised_bandwidth.unwrap_or(0);
        entry.relays += 1;
        entry.bandwidth += bandwidth;
        entry.probability += relay.exit_probability.unwrap_or(0.0);
        if let Some(nick) = relay.nickname.map(|n| n.trim().to_string()).filter(|n| !n.is_empty()) {
            entry.top.push(ExitRelay {
                nick,
                fp: relay
                    .fingerprint
                    .map(|f| f.trim().to_uppercase())
                    .unwrap_or_default(),
                bw: bandwidth,
            });
        }
    }

    if by_country.is_empty() {
        return None;
    }

    let mut countries: Vec<ExitCountry> = by_country.into_values().collect();
    for country in &mut countries {
        country
            .top
            .sort_by(|a, b| b.bw.cmp(&a.bw).then_with(|| a.nick.cmp(&b.nick)));
        country.top.truncate(TOP_RELAYS);
    }
    countries.sort_by(|a, b| {
        b.bandwidth
            .cmp(&a.bandwidth)
            .then_with(|| b.relays.cmp(&a.relays))
            .then_with(|| a.cc.cmp(&b.cc))
    });

    Some(Directory {
        updated: now(),
        source: "onionoo".to_string(),
        countries,
    })
}

fn now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|since| since.as_secs())
        .unwrap_or(0)
}

pub fn read_cache(state: &Path) -> Option<Directory> {
    let raw = std::fs::read_to_string(state.join(CACHE_FILE)).ok()?;
    let dir: Directory = serde_json::from_str(&raw).ok()?;
    if dir.countries.is_empty() {
        None
    } else {
        Some(dir)
    }
}

fn write_cache(state: &Path, dir: &Directory) {
    let Ok(body) = serde_json::to_string_pretty(dir) else {
        return;
    };
    if std::fs::create_dir_all(state).is_err() {
        return;
    }
    let path = state.join(CACHE_FILE);
    let temporary = state.join(format!("{CACHE_FILE}.new"));
    if std::fs::write(&temporary, body).is_err() {
        return;
    }
    let _ = std::fs::rename(&temporary, &path);
}

/// The saved directory, or the bundled one.
pub fn load(state: &Path) -> Directory {
    read_cache(state).unwrap_or_else(Directory::bundled)
}

/// Tells the apps what exits there are: one machine-readable line they pick up from the log.
pub fn announce(dir: &Directory) {
    log::info!(
        "[+] tor exit directory: {} countries, {} exit relays, from {}",
        dir.countries.len(),
        dir.total_relays(),
        dir.source
    );
    log::info!("[=] tor-exits {}", dir.to_line());
}

fn api_url() -> String {
    std::env::var("ORYVEXCORE_TOR_EXIT_API")
        .ok()
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| ONIONOO_DETAILS.to_string())
}

/// Asks Onionoo for every running exit, through tor's own proxy on `tor_proxy`, so the request
/// leaves from a tor exit and the local network never sees torproject.org being asked.
pub async fn fetch_through(tor_proxy: SocketAddr) -> Option<Directory> {
    let proxy = match reqwest::Proxy::all(format!("socks5h://{tor_proxy}")) {
        Ok(proxy) => proxy,
        Err(e) => {
            log::warn!("[-] tor exit directory: cannot use the tor proxy {tor_proxy}: {e}");
            return None;
        }
    };
    let client = match reqwest::Client::builder()
        .proxy(proxy)
        .timeout(FETCH_TIMEOUT)
        .build()
    {
        Ok(client) => client,
        Err(e) => {
            log::warn!("[-] tor exit directory: {e}");
            return None;
        }
    };

    let url = api_url();
    log::info!("[*] tor exit directory: asking onionoo for running exits, through tor");
    let answer = client
        .get(&url)
        .query(&[
            ("type", "relay"),
            ("running", "true"),
            ("flag", "Exit"),
            (
                "fields",
                "nickname,fingerprint,country,country_name,advertised_bandwidth,exit_probability,flags,running",
            ),
        ])
        .send()
        .await;

    let body = match answer {
        Ok(answer) if answer.status().is_success() => match answer.text().await {
            Ok(body) => body,
            Err(e) => {
                log::warn!("[-] tor exit directory: the answer broke off: {e}");
                return None;
            }
        },
        Ok(answer) => {
            log::warn!("[-] tor exit directory: onionoo answered {}", answer.status());
            return None;
        }
        Err(e) => {
            log::warn!("[-] tor exit directory: onionoo did not answer: {e}");
            return None;
        }
    };

    match summarize(&body) {
        Some(dir) => Some(dir),
        None => {
            log::warn!("[-] tor exit directory: onionoo listed no usable exit");
            None
        }
    }
}

/// Fetches a fresh directory when the saved one is stale, saves it and announces it. Runs in the
/// background once tor serves on `tor_proxy`.
pub async fn refresh_in_background(state: std::path::PathBuf, tor_proxy: SocketAddr) {
    let saved = load(&state);
    if !saved.is_stale() && std::env::var("ORYVEXCORE_TOR_EXIT_REFRESH").as_deref() != Ok("1") {
        return;
    }
    // Give the proxy a moment to start accepting.
    tokio::time::sleep(Duration::from_secs(2)).await;
    for attempt in 1..=3u32 {
        if let Some(dir) = fetch_through(tor_proxy).await {
            write_cache(&state, &dir);
            announce(&dir);
            return;
        }
        tokio::time::sleep(Duration::from_secs(15 * u64::from(attempt))).await;
    }
    log::warn!("[-] tor exit directory: keeping the saved list from {}", saved.source);
}

/// Bytes per second, as people read it.
pub fn human_rate(bytes_per_second: u64) -> String {
    let bits = bytes_per_second as f64 * 8.0;
    if bits >= 1e9 {
        format!("{:.1} Gbit/s", bits / 1e9)
    } else if bits >= 1e6 {
        format!("{:.0} Mbit/s", bits / 1e6)
    } else {
        format!("{:.0} kbit/s", bits / 1e3)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_exit_choice_has_a_spelling() {
        assert_eq!(parse_choice(""), ExitChoice::Auto);
        assert_eq!(parse_choice("auto"), ExitChoice::Auto);
        assert_eq!(parse_choice("FASTEST"), ExitChoice::Fastest);
        assert_eq!(parse_choice("de"), ExitChoice::Countries(vec!["de".into()]));
        assert_eq!(
            parse_choice("DE, nl,{se},de"),
            ExitChoice::Countries(vec!["de".into(), "nl".into(), "se".into()])
        );
        assert_eq!(parse_choice("germany"), ExitChoice::Auto);
    }

    #[test]
    fn the_label_reads_back() {
        assert_eq!(parse_choice("de,nl").label(), "DE,NL");
        assert_eq!(ExitChoice::Fastest.label(), "fastest");
    }

    #[test]
    fn onionoo_details_are_counted_per_country() {
        let body = r#"{"version":"8.0","relays":[
            {"nickname":"slowde","fingerprint":"aaaa0000aaaa0000aaaa0000aaaa0000aaaa0000","country":"de","country_name":"Germany","advertised_bandwidth":1000,"exit_probability":0.1,"flags":["Exit","Fast","Running"],"running":true},
            {"nickname":"fastde","fingerprint":"BBBB1111BBBB1111BBBB1111BBBB1111BBBB1111","country":"de","country_name":"Germany","advertised_bandwidth":3000,"exit_probability":0.2,"flags":["Exit","Running"],"running":true},
            {"country":"nl","country_name":"Netherlands","advertised_bandwidth":2000,"flags":["Exit"],"running":true},
            {"country":"us","country_name":"United States","advertised_bandwidth":9000,"flags":["Exit","BadExit"],"running":true},
            {"country":"fr","country_name":"France","advertised_bandwidth":9000,"flags":["Guard"],"running":true},
            {"country":"se","country_name":"Sweden","advertised_bandwidth":9000,"flags":["Exit"],"running":false},
            {"advertised_bandwidth":9000,"flags":["Exit"]}
        ]}"#;
        let dir = summarize(body).expect("a directory");
        assert_eq!(dir.source, "onionoo");
        assert_eq!(dir.countries.len(), 2);
        assert_eq!(dir.countries[0].cc, "de");
        assert_eq!(dir.countries[0].relays, 2);
        assert_eq!(dir.countries[0].bandwidth, 4000);
        assert_eq!(dir.countries[1].cc, "nl");
        assert_eq!(dir.total_relays(), 3);
        // The strongest relay comes first, and a relay without a nickname is counted but not listed.
        assert_eq!(dir.countries[0].top.len(), 2);
        assert_eq!(dir.countries[0].top[0].nick, "fastde");
        assert_eq!(dir.countries[0].top[1].fp, "AAAA0000AAAA0000AAAA0000AAAA0000AAAA0000");
        assert!(dir.countries[1].top.is_empty());
    }

    #[test]
    fn an_empty_or_broken_answer_is_no_directory() {
        assert!(summarize("{\"relays\":[]}").is_none());
        assert!(summarize("<html>blocked</html>").is_none());
    }

    #[test]
    fn the_bundled_list_is_made_of_country_codes() {
        let dir = Directory::bundled();
        assert!(dir.countries.len() >= 60);
        for c in &dir.countries {
            assert!(is_country_code(&c.cc), "{}", c.cc);
            assert!(!c.name.is_empty());
        }
        assert!(dir.is_stale());
    }

    #[test]
    fn fastest_measures_well_served_countries_and_tops_up() {
        let dir = Directory {
            updated: now(),
            source: "onionoo".into(),
            countries: vec![
                ExitCountry { cc: "nl".into(), name: "Netherlands".into(), relays: 50, bandwidth: 9, probability: 0.0, top: Vec::new() },
                ExitCountry { cc: "zz".into(), name: "Tiny".into(), relays: 1, bandwidth: 8, probability: 0.0, top: Vec::new() },
                ExitCountry { cc: "de".into(), name: "Germany".into(), relays: 40, bandwidth: 7, probability: 0.0, top: Vec::new() },
            ],
        };
        let picks = dir.fastest_candidates(4);
        assert_eq!(picks[0], "nl");
        assert_eq!(picks[1], "de");
        assert!(!picks.contains(&"zz".to_string()));
        assert_eq!(picks.len(), 4);
    }

    #[test]
    fn a_cache_from_before_top_relays_still_reads() {
        let old = r#"{"updated":1,"source":"onionoo","countries":[{"cc":"de","name":"Germany","relays":3,"bandwidth":9}]}"#;
        let dir: Directory = serde_json::from_str(old).expect("old cache");
        assert!(dir.countries[0].top.is_empty());
    }

    #[test]
    fn the_directory_line_reads_back() {
        let dir = Directory::bundled();
        let back: Directory = serde_json::from_str(&dir.to_line()).expect("json");
        assert_eq!(back, dir);
    }

    #[test]
    fn rates_read_like_people_write_them() {
        assert_eq!(human_rate(125_000_000), "1.0 Gbit/s");
        assert_eq!(human_rate(1_250_000), "10 Mbit/s");
    }
}
