# Flutter Windows client

This is the Flutter source for the VexoStream Windows app. The repository's GitHub Actions workflow generates the standard Windows runner when needed, resolves Flutter packages, runs tests, builds a release, and uploads both `vexostreaapp_flutter.zip` and a per-user NSIS installer (`VexoStream-<version>-Setup.exe`).

Preferred API: `https://vexostream.bond/api/v1`; fallback: `https://api.vexostream.bond/api/v1`. Override at build time with `--dart-define=VEXOSTREAM_API_BASE=https://your-api.example/api/v1`.

Build with the same shared key configured as the Worker `APP_KEY` secret: `flutter build windows --release --dart-define=APP_KEY=<same-value>`. The app sends it as `X-App-Key` on app API and image requests. GitHub Actions reads it from an optional repository secret named `APP_KEY`; without that secret, Actions builds for validation only and does not publish an API-ready artifact. The key is embedded in the desktop binary, so it can be extracted and should not be treated as a confidential secret.

The app reads the admin-saved Default search value for its Home feed and initial Browse/Search screen. Owner accounts use the same login form and get every website Admin section in the app: maintenance, providers/order/default search, Core backend, member access and member management, team permissions/password resets, social links/bots/channel posts, Telegram bot/webhook, live viewers, database repair, and Owner password management. A manually entered search overrides it; clearing the field restores the admin default.

The app is 18+ and uses the site's Worker API for accounts, catalog, performer profiles, status, social information, authorized Check host checks, and stream extraction. Secure account tokens are stored with Windows secure storage. Video playback is handled by VexoStream’s own website player inside WebView2.

The app uses VexoStream’s own `/embed/` page inside WebView2 for playback, quality selection, and controls. A logged-in app session requests a short-lived, video-specific embed grant from the Worker; the app bearer token is never placed in the WebView URL. The grant lets the VexoStream embed honor the app login even though WebView2 has no site-login cookie. It does not call a provider embed API or load provider-supplied embed URLs. The WebView loads only VexoStream’s own HTTPS embed route, denies popups and permissions, and stops top-level navigation that leaves that route. Windows requires the WebView2 Runtime and Windows 10 version 1809 or later. If WebView2 is missing or the embedded player fails, the app offers the VexoStream embed link and original video link to copy.

The Windows CI CMake setup defines `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for the `webview_windows` target to work around the MSVC STL1011 hard error reported by newer Visual Studio toolchains.

The NSIS installer deploys the full Flutter release folder into the current user's `%LOCALAPPDATA%\Programs\VexoStream`, adds Start Menu shortcuts, and registers an uninstaller. To compile it locally, build the Windows release first, install NSIS, then run `makensis /DPRODUCT_VERSION=1.1.0.2 installer\VexoStream.nsi` from this directory.
