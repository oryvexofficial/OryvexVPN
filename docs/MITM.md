# MITM (domain fronting)

A direct route with **no server, no account and no v2ray**. oryvexcore itself is the proxy.
Based on the method of [patterniha/MITM-DomainFronting](https://github.com/patterniha/MITM-DomainFronting)
(GPL-3.0), implemented natively in `oryvexcore/src/mitm.rs`.

## What it reaches

YouTube / Google (including googlevideo), Instagram, WhatsApp, Facebook (Meta), Reddit, CNN,
BuzzFeed and other sites behind Fastly. It does not give access to the whole internet and does
not change your address. Everything not on the list goes out directly and untouched.

## How it works

1. oryvexcore makes a **certificate authority on your device** the first time (`oryvex-mitm-ca.crt`
   and a private key beside your identity file, in `oryvexcore-mitm/`). The key never leaves the device.
2. You install `oryvex-mitm-ca.crt` as a trusted root, **once**.
3. A browser asks the proxy for `www.youtube.com:443`. oryvexcore answers the TLS handshake itself
   with a certificate for that name signed by your CA, and reads the request.
4. It connects to the real server's address but sends a different, unblocked name in the TLS
   handshake (the SNI, which is what filters read): `www.google.com` for Google, `www.microsoft.com`
   for Meta, `github.githubassets.com` (at a Fastly edge) for Reddit and friends.
5. It checks the certificate the server returns against the real name (chain to a trusted root,
   plus a name check), then relays bytes both ways (HTTP/2 and HTTP/1.1).
6. Name lookups go through DNS-over-HTTPS to 1.1.1.1, itself fronted, so poisoned DNS does not matter.

## Use it

| Where | Steps |
|---|---|
| Windows app (x64) | Pick **MITM**, open **About this connection**, press **Install certificate** (Windows asks to confirm), restart the browser, Connect. The system proxy is set automatically. |
| Windows Lite (7/8/10/11, x86 and x64) | Pick **MITM**, Connect, then double-click `%APPDATA%\OryvexCore\oryvexcore-mitm\oryvex-mitm-ca.crt` and install it into Current User > Trusted Root Certification Authorities. |
| Android 5.0+ (all ABIs) | Pick **MITM**, Connect once (this makes the certificate), then **About this connection > Install certificate**. In Settings: Security and privacy > More security settings > Install from device storage > CA certificate > `oryvex-mitm-ca.crt`. Turn on **Whole-device VPN** to route the browser. Use Chrome or another Chromium browser. |
| Linux / macOS / OpenWrt | `oryvexcore --mitm`, trust `oryvexcore-mitm/oryvex-mitm-ca.crt` (Linux: copy to `/usr/local/share/ca-certificates/` and `update-ca-certificates`; macOS: Keychain Access > Always Trust), point the browser at SOCKS5/HTTP `127.0.0.1:1819`. |

Firefox keeps its own certificate list (Settings > Privacy > View Certificates > Import; on Android Firefox use Secret Settings > "Use third party CA certificates").

## Limits

* Only the listed services. The list is in `oryvexcore/src/mitm.rs`; send a pull request to add one.
* Apps that ignore user-installed certificates (most non-browser apps on non-rooted Android) cannot use it.
* QUIC is not served (browsers fall back to TCP).
* Never share the `.key` file, and never install a certificate somebody else made.

## Command line

```
oryvexcore --mitm                       # run it
oryvexcore --mitm-make-ca               # only make the certificate and print its path
oryvexcore --mitm --mitm-dir /path      # keep the CA somewhere else
```
