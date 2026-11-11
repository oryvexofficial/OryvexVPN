# Notice

OryvexCore is a modified version of Aether (https://github.com/CluvexStudio/Aether), copyright CluvexStudio, licensed under the GNU Affero General Public License v3.0 (see LICENSE).

Modifications (2026-10-29): renamed the project, crate, binary, environment variables (`AETHER_*` -> `ORYVEXCORE_*`), FFI symbols and files to OryvexCore; added the Flutter GUI (`gui/`) for Android and Windows, the native Win32 OryvexCore Lite (`lite/`) for Windows 7/8 and 32-bit Windows, new branding (`branding/`) and the GitHub Actions app pipeline (`.github/workflows/apps.yml`).

The MITM route follows the method of patterniha/MITM-DomainFronting (https://github.com/patterniha/MITM-DomainFronting, GPL-3.0), reimplemented in Rust. `oryvexcore/src/mitm_roots.pem` is the Mozilla CA certificate list (via certifi), licensed MPL-2.0.

Under AGPL-3.0, anyone you distribute these binaries to is entitled to this source code.
