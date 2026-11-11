<p align="center"><img src="branding/oryvexcore-logo.svg" width="128" alt="OryvexCore"></p>

<h1 align="center">OryvexVPN</h1>
<p align="center"><b>A way out of filtered networks.</b><br>The OryvexCore engine, plus blue-and-black apps for Windows and Android.</p>

<p align="center">
  <a href="https://github.com/oryvexofficial/OryvexVPN/releases/latest">Download</a> ·
  <a href="docs/GUIDE.md">Guide</a> ·
  <a href="docs/TOR.md">Tor exits</a> ·
  <a href="https://oryvexofficial.github.io/OryvexVPN/">Website</a> ·
  <a href="docs/DOCS.md">Full reference</a> ·
  <a href="docs/OPENWRT.md">OpenWrt</a>
</p>

---

OryvexCore finds a route that works on your network, opens an encrypted tunnel through it and serves that tunnel as a local SOCKS5 proxy (or, on Android, a whole-device VPN). It is built for networks with deep packet inspection, protocol fingerprinting, UDP throttling and endpoint blocking.

## Highlights

- **Finds its own way out.** Scans for reachable gateways and only trusts one after real traffic passes through it.
- **Four tunnels.** MASQUE over HTTP/3 or HTTP/2, classic WireGuard, WireGuard in MASQUE (`gool`) and MASQUE in MASQUE (`mim`) for a different exit address.
- **Bypass, no tunnel.** A direct route that reshapes the first packets of every connection and resolves names itself, so filters that read the site name are fooled. Your address stays the same. On Windows the app automatically uses the Windows system proxy; Android can route the whole device through its VPN service (`--bypass`, see `oryvexcore/bypass/README.md`).
- **Hard to fingerprint.** Chrome-shaped TLS, ClientHello fragmentation, obfuscation profiles from `light` to `gfw`.
- **Extra exits.** Tor through the tunnel, Tor alone, or Psiphon through the tunnel (desktop).
- **Stays up.** Automatic reconnect, and quick reconnect to the last gateway that worked.
- **Verifies real traffic.** The app shows Connected once the core reports the tunnel and proxy are up. OryvexVPN never looks up your IP address or country.
- **Tor as a route.** Built-in Tor (Arti) on Windows and Android with Auto, Fastest or a chosen exit country; the exit list is fetched through Tor itself.
- **Runs anywhere.** Windows, Android, Linux, macOS, OpenWrt routers, Termux and Docker.

## The apps

| Platform | Download | What you get |
| --- | --- | --- |
| Android 5.0+ | `OryvexVPN-android-*.apk` | Whole-device VPN (VpnService + hev-socks5-tunnel) or proxy only |
| Windows 10 / 11, 64-bit | `OryvexVPN-windows-x64.zip` | Desktop app; system proxy is automatic for Bypass and optional for other routes; Tor and Psiphon bundled |
| Windows 7 / 8 / 10 / 11, 32 and 64-bit | `OryvexVPN-windows-legacy-*.zip` | OryvexVPN Lite, a tiny native Win32 app |

### Bypass support by platform

| Platform | How Bypass routes traffic |
| --- | --- |
| Android 5.0+ | Whole-device routing through Android's VPN service when that option is enabled; supported APK ABIs are arm64-v8a, armeabi-v7a and x86_64. |
| Windows 10 / 11, x64 | The desktop app enables the per-user Windows system proxy automatically while Bypass is connected, then restores the previous setting. |
| Windows 7 / 8 / 10 / 11, x86 and x64 | OryvexVPN Lite does the same through the Windows system proxy. |
| Linux and macOS, CLI | Build/install `oryvexcore` and the native `oryvex-bypass` engine; clients must use the local proxy. There is no bundled GUI or whole-system VPN mode. |

The Windows system proxy covers apps that honor Windows proxy settings, not every app or every network protocol. Apps that ignore it still need to use the local proxy explicitly.

The desktop and Android apps share one design: a black canvas, Inter and JetBrains Mono type (bundled, no network fetch), and one blue for every action. While you connect, the Connect page shows each stage of the chosen protocol live (identity, gateway scan, tunnel, proxy, then Tor, Psiphon or the device VPN when they apply). **Activity** shows the core's log with level tags, folded repeats and one-tap copy.

## Project layout

```text
OryvexVPN/
├── oryvexcore/              the Rust core (CLI, library, C API)
│   ├── bypass/              oryvex-bypass, the C engine behind --bypass
│   ├── src/
│   ├── vendor/quiche/       Cloudflare quiche, vendored (MASQUE / QUIC)
│   └── scripts/             pt-build.sh, psiphon-build.sh, third-party-notices.py,
│                            h2-bench.sh, oryvexcore.sh (Termux installer)
├── apps/
│   ├── shared/              Dart package: UI, theme, fonts, logo, core control
│   ├── desktop-src/         Flutter app for Windows (windows/ runner, tool/bootstrap)
│   ├── android-src/         Flutter app for Android (VpnService, tool/build_android_natives.sh)
│   └── desktop-lite-src/    OryvexVPN Lite, native Win32 (Rust)
├── branding/                logo (SVG + PNG)
├── docs/                    guide, full reference, Tor exits, OpenWrt
├── site/                    GitHub Pages website (pages.yml)
├── license-texts/  tools/  .github/workflows/
└── Dockerfile  LICENSE  NOTICE.md  TRADEMARK.md
```

## Build

Everything is built by GitHub Actions (`.github/workflows/apps.yml` for the apps, `release.yml` for tagged releases). The release links and the in-app update check point at `oryvexofficial/OryvexVPN` (`apps/shared/lib/src/core/version.dart`); `tools/set-repo.sh <user>/<repo>` repoints them for a fork.

**Core** (Rust stable, a C/C++ compiler, CMake):

```bash
cd oryvexcore
bash scripts/build-core.sh cargo build --release   # tor + exit-country, falls back on tor
./target/release/oryvexcore --masque --turbo -4
```

**Desktop app** (Flutter 3.32.8, see `apps/shared/flutter-version.txt`):

```bash
cd apps/desktop-src
bash tool/bootstrap.sh                # or tool/bootstrap.ps1 on Windows
flutter build windows --release
# then copy the core to build/windows/x64/runner/Release/core/oryvexcore.exe (next to OryvexVPN.exe),
# with the bypass engine beside it: bash ../../oryvexcore/bypass/build.sh windows x86_64 <dir>
```

**Android app** (Flutter, NDK r28, cargo-ndk):

```bash
cd apps/android-src
bash tool/bootstrap.sh
bash tool/build_android_natives.sh all   # core + VPN engine into android/app/src/main/jniLibs
flutter build apk --release --split-per-abi
```

Optional release signing: add the `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` secrets. Without them the APKs are signed with the debug key.

**Windows installer**: after `flutter build windows --release` (and copying the core into `Release/core`), run `installer/windows/build-installer.ps1` with NSIS 3 installed (`winget install NSIS.NSIS`). Output: `dist/OryvexVPN-Setup-<version>-x64.exe`. See `installer/windows/README.md`.

**Lite** (Windows, Rust nightly for Windows 7 targets): `cd apps/desktop-lite-src && cargo build --release`.

## Command line

```bash
oryvexcore                                   # answer the questions as they come
oryvexcore --masque --turbo -4               # nothing asked, straight to work
oryvexcore --wg --thorough --noize gfw       # WireGuard on a strict network
oryvexcore --gool                            # WireGuard inside MASQUE
oryvexcore --mim --h2                        # MASQUE inside MASQUE over HTTP/2
oryvexcore --masque --tor                    # plus a Tor exit on --tor-bind
oryvexcore --tor-only --tor-exit fastest     # plain Tor, fastest exit country
oryvexcore --bypass                          # no tunnel: direct, first packets reshaped
```

Then point apps at `socks5h://127.0.0.1:1819`:

```bash
curl -x socks5h://127.0.0.1:1819 https://www.cloudflare.com/cdn-cgi/trace
```

Every flag has an environment variable; `oryvexcore help` lists them all. The proxy has no authentication: bind it to `0.0.0.0` only on a network you trust.

## Docker

```bash
docker run -it -p 127.0.0.1:1819:1819 -v oryvexcore-data:/data ghcr.io/owner/oryvexcore:latest
```

Keep the `-v` volume: it holds your WARP identity, and a new identity on every start gets rate limited. Publish the port to `127.0.0.1` only.

## Termux

```bash
curl -fsSL https://raw.githubusercontent.com/oryvexofficial/OryvexVPN/main/oryvexcore/scripts/oryvexcore.sh -o oryvexcore.sh
chmod +x oryvexcore.sh && ./oryvexcore.sh install
```

## Credits and license

Created by **Muvixo**. MASQUE is built on Cloudflare's **quiche**. Fonts: Inter and JetBrains Mono (SIL OFL 1.1, see `apps/shared/fonts/OFL.txt`).


AGPL-3.0. See [LICENSE](LICENSE), [NOTICE.md](NOTICE.md) and [TRADEMARK.md](TRADEMARK.md).
