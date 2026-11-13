# VexoStream Flutter app

Flutter source for Windows and Android. The app version is `1.0.2` (`1.0.2+7` in `pubspec.yaml`).

## App features

- Home, Browse/Search, provider libraries, Models and profiles, Social, Developers, Status, Check Host, account, and the native Owner/Admin tools.
- First-party VexoStream player with quality selection, “More like this,” the website’s keyboard-shortcut reference, share/embed snippets, and device-local Continue Watching with resume.
- Responsive navigation and layouts. Windows uses Microsoft Edge WebView2; Android uses Android System WebView.
- A first-party player link is requested only for validated provider video pages. The app never loads provider-supplied embed URLs. Windows denies popups and permissions and restricts top-level navigation to VexoStream’s HTTPS embed route.

## Build locally

Install Flutter stable, platform build tools, and Java 17 for Android. From this directory:

```sh
flutter pub get
flutter test
```

Windows:

```powershell
flutter create --platforms=windows --project-name=vexostream_app --org=bond.vexostream .
flutter build windows --release `
  --dart-define=APP_VERSION=1.0.2 `
  --dart-define=VEXOSTREAM_GITHUB_REPOSITORY=OWNER/REPOSITORY `
  --dart-define=APP_KEY=YOUR_WORKER_APP_KEY
```

Android universal APK:

```sh
bash tool/prepare_android.sh
flutter build apk --release \
  --dart-define=APP_VERSION=1.0.2 \
  --dart-define=VEXOSTREAM_GITHUB_REPOSITORY=OWNER/REPOSITORY \
  --dart-define=APP_KEY=YOUR_WORKER_APP_KEY
```

Flutter's default APK build includes the supported ABIs in one APK. Android release signing must be configured before store distribution. The app uses Android's system WebView, not Edge WebView2. Native error screens vary with Android/System WebView versions and may not match Edge's “can't reach this page” screen; retry and navigation behavior can also differ by OS.

The preferred API is `https://vexostream.bond/api/v1`, with `https://api.vexostream.bond/api/v1` as fallback. Override with `--dart-define=VEXOSTREAM_API_BASE=https://your-api.example/api/v1`.

## APP_KEY and protected API

For an API-ready build, provide the same `APP_KEY` configured as a Cloudflare Worker secret. The app sends it on protected API and image requests. GitHub Actions reads the optional repository secret `APP_KEY`. Without it, builds are uploaded with a `validation-no-app-key` label and a notice explaining that protected API calls will not work. The key is embedded in client binaries, so it is a client gate, not a durable secret.

## GitHub releases and mandatory updates

Every `v*` tag runs the website tests, Flutter tests, Windows build, Android universal APK build, and NSIS packaging. A version-matching tag such as `v1.0.2` publishes the Windows installer, portable ZIP, and Android APK as release assets. Releases without `APP_KEY` are clearly marked validation-only and published as pre-releases, so they do not become the stable update target.

CI passes `GITHUB_REPOSITORY` and the app version into the app at build time. On startup, the update checker reads the repository's public GitHub Releases API, compares stable semantic versions, and opens a non-dismissible mandatory-update gate with the current platform's direct download when a newer stable release exists. A failed check is shown as unverified, with Retry and an explicit Continue option; the app retries after a detected network reconnection. Local builds without a valid repository setting report that updates are not configured instead of claiming the check succeeded.

## Windows installer

The NSIS installer deploys the full Flutter release folder to `%LOCALAPPDATA%\Programs\VexoStream`, adds Start Menu shortcuts, and registers an uninstaller. NSIS writes `VexoStream-<version>-Setup.exe` beside `installer/VexoStream.nsi`. The GitHub workflow uploads that installer as its own artifact and again in the artifact bundle with the portable ZIP.

The Windows CI CMake setup defines `_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS` for `webview_windows` to work around the MSVC STL1011 warning treated as an error by some Visual Studio toolchains.

## Worker deployment

The updated Worker in `site/` is built and tested by CI but is not deployed automatically. Deploy it separately with the project's Cloudflare instructions. The server-side player change that omits the loading poster takes effect only after deploying that Worker.
