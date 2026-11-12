# OryvexVPN Setup

A standard NSIS Modern UI 2 wizard: Welcome, License, install folder, components (desktop icon, Start menu, start with Windows), progress, Finish with "Launch OryvexVPN".

## Build

1. Build the app: `cd apps/desktop-src && ./tool/bootstrap.ps1 && flutter build windows --release`
2. Put the core beside it in `build/windows/x64/runner/Release/core` (CI does this), plus the MSVC runtime DLLs.
3. Install NSIS 3: `winget install NSIS.NSIS` (or `choco install nsis`).
4. Run `installer/windows/build-installer.ps1` (options: `-Source`, `-Version 1.2.3`, `-OutDir`).

Output: `dist/OryvexVPN-Setup-<version>-x64.exe`. CI builds it in the `windows-app` job of `apps.yml` and the release attaches it.

## What it does

- Installs to `C:\Program Files\OryvexVPN` (any folder you pick gets its own `OryvexVPN` subfolder), for all users, elevated.
- Desktop icon and Start menu entry, Add/Remove Programs entry with icon, version, size and a quiet uninstall string.
- Optional "launch at sign-in": writes the same `HKCU\...\Run\OryvexVPN` value the app switch uses (`--background` keeps it in the tray).
- Closes a running OryvexVPN first, and switches off a loopback system proxy it may have left behind.
- Upgrades in place (keeps the previous folder and sign-in choice). Settings in `%APPDATA%` are kept unless you ask to remove them on uninstall.
- Silent: `OryvexVPN-Setup-x.y.z-x64.exe /S [/D=C:\path]`, uninstall `"Uninstall OryvexVPN.exe" /S`.
- 64-bit Windows 10/11 only; older PCs get OryvexVPN Lite.

## Files

- `OryvexVPN.nsi`: pages and sections
- `common.nsh`: install, shortcut, startup, proxy and uninstall logic
- `assets/`: `app.ico`, `welcome.bmp` (164x314), `header.bmp` (150x57)
- `build-installer.ps1`: finds makensis and builds
