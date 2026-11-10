# oryvexcore/tor

Tor files that ship with the core.

| File | What it is |
|---|---|
| `exit-nodes.txt` | Every running Tor exit IP, one per line, from the Tor Project's bulk exit list (`https://check.torproject.org/torbulkexitlist`). Snapshot of 2026-11-01: 1248 addresses. |

## Where Tor itself is

Tor is not a separate `tor.exe` here. The core carries **Arti** (the Tor Project's Rust Tor) compiled in:

- `../src/tor.rs` the Tor client: alone, through the tunnel, the tunnel through Tor
- `../src/tor_exits.rs` exit-country choice (auto / fastest / de,nl,...), fetched from Onionoo through Tor and cached in `<tor-dir>/exits.json`
- `../src/bridges.rs` bridges and pluggable transports when Tor is blocked
- `../Cargo.toml` features `tor` and `tor-exit-country` (arti-client 0.46)

Tor is a cargo feature and **off by default**. Build it in with:

```
bash scripts/build-core.sh cargo build --release
# or
cargo build --release --features tor,tor-exit-country
```

## Refresh the exit list

The list changes every hour. From the repo root:

```
bash tools/update-tor-exits.sh
# torproject.org filtered? go through the core's Tor proxy:
ORYVEX_PROXY=socks5h://127.0.0.1:1820 bash tools/update-tor-exits.sh
```
