# VexoStream Native Rust Desktop App

A fully native Rust desktop client built with `eframe` and `egui` (no WebView).

## Features

- **Direct API integration**: Communicates natively with the Cloudflare Worker `/api/v1` API over HTTPS using `reqwest`.
- **Browse & Search**: Multi-provider support (Pornhub, XVideos, XNXX, RedTube, YouPorn) with search, pagination, and direct playback.
- **Top 3 Podium Leaderboard**: OnlyFans models directory featuring Olympic-style podium (#1 Gold, #2 Silver, #3 Bronze) with profile inspection.
- **Stream Extraction & Playback**: Resolves Worker-signed streaming URLs and direct playback links.
- **Diagnostics & Tools**: Built-in Check Host diagnostics, live System Status, Developers embed info, and Social channels.
- **Account Management**: Member login and signup with session token support.

## Building

```powershell
cargo test
cargo build --release
```

The output executable is located at `target/release/vexostreamapp_rust.exe`.
