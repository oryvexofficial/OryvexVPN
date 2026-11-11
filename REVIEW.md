# OryvexVPN 1.1.0: review and change notes

## What changed in this drop
- **IP / country lookup removed** (app + core): `ip_info.dart` deleted, Connect-page IP card gone, `exitloc.rs` deleted with `--exit-loc`/`--exit-loc-secs`, the "<route> exit:" trace calls in tor.rs / psiphon.rs removed, bridge fetch no longer probes your country (only a hand-set `ORYVEXCORE_TOR_COUNTRY`). Internet check now uses empty generate_204 probes. Tor *exit country choice* is kept: it is a routing option, not a lookup.
- **Updates**: Settings > Updates checks automatically on open, shows "Update available: download vX" and opens the release. New `update_service.dart` (badge-ready ChangeNotifier, 6 h re-check, cached result, platform asset picking, check through the SOCKS port when connected, skip version) and `https_client.dart` (verified HTTPS over SOCKS5) are in place for the new UI to use.
- **Security**: Zero Trust and bridge-fetch reqwest clients verify TLS again (`ORYVEXCORE_INSECURE_TLS=1` opt-out).
- **Fixes**: any settings change while connected used to flag "reconnect" (even Dark mode); `set-repo.sh` searched for placeholders that no longer existed; release workflow sed path moved to `core/version.dart`; dead `_verification*` fields removed.
- **New core features for the app**: session history with lifetime totals (`history.dart`, wired into the controller), route presets (`presets.dart`), settings reset/export/import (controller), Android `openUrl` / `deviceInfo` channel methods.

## NOT done yet (be aware)
- **The from-scratch UI redesign is not in this drop.** The screens are still the original layout, patched to work with the changes above. The planned redesign (sidebar shell, signal-dial connect control, live traffic chart, Updates tab with badge, Sessions view, presets row) needs the services above wired into new pages.
- Nothing here was compiled: the build sandbox had no Flutter or Rust toolchain. Run `cargo test --lib` in `oryvexcore/` and `flutter analyze && flutter test` in `apps/shared` before releasing.

## Review findings still open
1. TLS verification is off by design across the tunnel/API paths (tls.rs `SslVerifyMode::NONE`, masque_h2 hostname check off, prober `verify_peer(false)`, WARP API in https.rs). Pinning exists behind `--tls-verify`; consider enabling pins by default for MASQUE.
2. README claimed an HTTPS gate before "Connected"; the controller marks connected on the core's ready line (README now corrected).
3. Theme: several overlays use `Colors.black` alpha (tab highlight, hover, scrollbar thumb), invisible in dark mode.
4. Desktop window defaults to 480x860 (phone shape) on Windows.
5. Lite (Win32) app was not reviewed in depth; it does no IP lookup.
