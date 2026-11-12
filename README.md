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

The universal APK does not include x86 or x86_64. No Linux, macOS, OpenWrt,
Termux, legacy Windows or Docker release jobs are included.

## How to use Fox

Choose Fox under Route, then open **Settings > Fox accounts and locations**.
Use the local dashboard to sign in and choose a server. Return to OryvexVPN
and connect. Android offers whole-device VPN mode. Windows Fox uses a local
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

For Android release signing, provide `ANDROID_KEYSTORE_BASE64`,
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`
as repository secrets. The included fallback key is public and is **not
suitable for trusted production releases**. Keep your private key out of Git.

## License

OryvexVPN is provided under AGPL-3.0. The bundled Fox core includes its
upstream GPL-3.0 license and notices in `fox/core`. Preserve license and
attribution files when distributing. Shared cross-platform source files remain
where the Windows and Android builds depend on them.
