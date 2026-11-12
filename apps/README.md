# Flutter Windows client

This is the Flutter source for the VexoStream Windows app. The repository's GitHub Actions workflow generates the standard Windows runner when needed, resolves Flutter packages, runs tests, builds a release, and uploads `VexoStream-Windows.zip`.

Preferred API: `https://vexostream.bond/api/v1`; fallback: `https://api.vexostream.bond/api/v1`. Override at build time with `--dart-define=VEXOSTREAM_API_BASE=https://your-api.example/api/v1`.

Build with the same shared key configured as the Worker `APP_KEY` secret: `flutter build windows --release --dart-define=APP_KEY=<same-value>`. The app sends it as `X-App-Key` on app API and image requests. Media playback uses separate short-lived signed URLs so HLS segment requests work with native players. GitHub Actions reads it from an optional repository secret named `APP_KEY`; without that secret, Actions builds for validation only and does not publish an API-ready artifact. The key is embedded in the desktop binary, so it can be extracted and should not be treated as a confidential secret.

The app reads the admin-saved Default search value for its Home feed and initial Browse/Search screen. Owner accounts use the same login form and get an Admin dashboard for maintenance mode, Core backend, default provider, and default search settings. A manually entered search overrides it; clearing the field restores the admin default.

The app is 18+ and uses the site's Worker API for accounts, catalog, performer profiles, status, social information, authorized Check host checks, and stream extraction. Secure account tokens are stored with Windows secure storage. The native player uses the Worker-signed media proxy URLs.
