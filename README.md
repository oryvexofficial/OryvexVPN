<p align="center"><img src="branding/oryvexcore-256.png" alt="OryvexVPN logo" width="128" height="128"></p>

# OryvexVPN

OryvexVPN is an open-source app for Windows and Android with multiple
connection routes, including Tor and Fox.

Fox is an unofficial Firefox Account VPN client. It is not made, endorsed or
supported by Mozilla. A Firefox Account with service access is required.

## Downloads

The release workflow is configured to publish:

- One Windows 10 / 11 x64 setup installer.
- Android 7.0+ universal APK for ARM64 and ARMv7.
- Android ARM64 APK for newer devices.
- Android ARMv7 APK for older 32-bit ARM devices.

The universal APK is `OryvexVPN-android-universal.apk`: one install file for
both ARM64 and ARMv7. Choose it if you are not sure which ARM version you have.
It does not include x86 or x86_64. No Linux, macOS, OpenWrt,
Termux, legacy Windows or Docker release jobs are included.

## How to use Fox

Choose Fox under **Route** on the Connect page. Select **Sign in with Mozilla**
to open Mozilla's account page inside the app, then choose an available country
and connect. Manage accounts and test country latency from the same card. The
old local web panel is removed. **Other sign-in** is a direct account fallback.
Web sign-in requires Android System WebView on Android or Microsoft Edge WebView2
Runtime on Windows. A browser sign-in provider can restrict embedded WebViews. Android offers whole-device VPN mode. Windows Fox uses a local
SOCKS5 proxy, so applications must be configured to use it.

## First push

Create an empty GitHub repository. From this project's root, replace
`YOUR_USERNAME/YOUR_REPO` below with your own repository:

```bash
bash tools/set-repo.sh YOUR_USERNAME/YOUR_REPO
git init
git add .
git commit -m "Prepare Windows and Android release"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```

Set GitHub **Settings > Pages > Build and deployment > Source** to
**GitHub Actions** for the included site to publish. Give Actions permission
to write repository contents if automatic tagging is enabled.

GitHub Actions builds the Windows setup and the three Android APKs. The
release workflow publishes a tagged release only after both app builds
succeed; it checks that all four files are present and writes checksums.
Manual workflow runs on a non-tag branch build artifacts without publishing.

## Release signing

Tagged Android releases require `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`
as repository secrets. No release signing key is included in this source.
Non-release builds use the debug key and must not be published as production
releases. Keep your private key out of Git.

## Cloudflare Fox relay

Select Fox, then open **Settings > Fox connection > Deploy Cloudflare relay**.
The app uses the bundled Worker source, requests a scoped Cloudflare API token,
deploys the Worker and secret, and saves its URL in Fox. Android opens the
Cloudflare dashboard in a system Custom Tab; Windows uses the system browser.
The token must be created by the user, scoped to the intended account, and pasted
into the dialog. The Firefox sign-in WebView itself connects directly; the relay
can carry the Fox backend's account and service requests, not general VPN traffic.
The account owner can inspect relayed traffic, so use only your own account.
See `fox/docs/relay/cloudflare/README.md` for the protocol and manual setup.

## Windows release signing

For tagged Windows releases, configure `WINDOWS_PFX_BASE64` and
`WINDOWS_PFX_PASSWORD` as protected GitHub Actions secrets. These must contain
your own trusted Authenticode code-signing certificate and private key. The
release workflow signs and verifies the first-party Windows executables and the
installer; pull-request artifacts remain unsigned when no credentials are set.
The timestamping service and trust chain must be reachable during the release.
Do not commit the certificate or private key. An Authenticode signature does not
itself guarantee SmartScreen reputation.

## Website assets

The static website lives in `site/` and works as a self-contained GitHub Pages
folder. It includes the same fonts, protocol icons and country flags as the app;
see the notices in `site/assets/fonts/OFL.txt` and
`site/assets/flags/ATTRIBUTION.md`. To preview locally, run
`python3 -m http.server --directory site 8000` and open `http://localhost:8000`.

## License

OryvexVPN is provided under AGPL-3.0. The bundled Fox core includes its
upstream GPL-3.0 license and notices in `fox/core`. Preserve license and
attribution files when distributing. Shared cross-platform source files remain
where the Windows and Android builds depend on them.
