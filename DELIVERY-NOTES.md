# VexoStream delivery notes

## Included work

- App version is `1.0.2` (`1.0.2+7` build metadata).
- Player: keeps the first-party player video path intact while omitting the broken loading poster, and adds “More like this,” the website keyboard-shortcut reference, share/embed snippets, and device-local Continue Watching with progress and resume.
- Offline/update gates: animated no-connection modal with retry and reconnection handling; stable GitHub release check; mandatory update gate with verified Windows installer or Android APK link; explicit failed/unconfigured states, retry, and continue-with-warning.
- Android/general: responsive drawer and page layouts, Check Host country flags, contrast/switch styling, and an APK CI build with the default Flutter ABI set.
- Android branding: `prepare_android.sh` sets the installed app label to `VexoStream` and installs density/adaptive launcher icons derived from the same artwork as the Windows desktop icon.
- Windows/release: corrected NSIS output path under `apps/flutterapp/installer/`, a standalone NSIS artifact plus a Windows bundle with the portable ZIP, and automatic version-tagged GitHub Releases after successful `main`/`master` builds when the version tag is new. Release assets include the Windows installer, portable ZIP, and universal Android APK. Existing version tags are not overwritten; bump the app version for another release. Missing `APP_KEY` is labeled validation-only and produces a pre-release, excluded from stable update checks.
- Website Worker source and compiled bundle remain in `site/`; deploy it separately for the server-side no-poster player change.

## Platform notes

Windows uses Microsoft Edge WebView2. Its normal navigation failure page is left to WebView2 when a network navigation fails. Android uses Android System WebView, not Edge; system error screens and retry details vary by Android/WebView version and are not pixel-identical to Edge's “can't reach this page” page. The Flutter offline modal checks network-interface connectivity, which cannot detect every captive portal, DNS failure, or upstream outage.

## Validation performed here

- Website Worker build succeeded using the available Node runtime.
- All 57 website Node regression tests passed.
- The supplied GitHub Actions logs show the website job succeeded and the Flutter jobs stopped during tests before either platform build started. They exposed three Dart compile errors: missing playback-video fields on the WebView widgets, a const-constructor access of a release object's version, and a GNU `sed` regular-expression bug for the `+` in the pubspec version. Those are fixed in this revision.
- The logs also contained the same run twice; both ZIPs have identical SHA-256 hashes.
- GitHub Actions runs website tests, Flutter tests, Windows/NSIS builds, Android APK build, and release packaging on an appropriately provisioned runner.

## Not built or device-tested here

This environment has no Flutter or Dart SDK, Android SDK/ADB, or NSIS compiler, and has no internet access to resolve Flutter packages. Therefore no Windows executable, NSIS installer, or Android APK was produced here; Flutter tests/builds, real playback, WebView error pages, installation, and physical/emulated device compatibility remain unverified. CI is configured to produce those artifacts, but has not been run from this delivered source.

The two source ZIPs supplied earlier have identical SHA-256 hashes and identical extracted file trees, so they did not provide a distinguishable before/after baseline.

## Local Android build

From `apps/flutterapp`, with Flutter stable, Android SDK, and Java 17 installed:

```sh
bash tool/prepare_android.sh
flutter pub get
flutter test
flutter build apk --release \
  --dart-define=APP_VERSION=1.0.2 \
  --dart-define=VEXOSTREAM_GITHUB_REPOSITORY=OWNER/REPOSITORY \
  --dart-define=APP_KEY=YOUR_WORKER_APP_KEY
```

The APK is a universal/multi-ABI package for the ABIs supported by the Flutter toolchain. Configure Android release signing before distribution. `APP_KEY` is embedded in the client and is not a durable secret.
