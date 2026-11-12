# oryvex-bypass

The engine behind `oryvexcore --bypass` and the **Bypass** route in the Windows and Android apps.
A C program with no dependencies: a local SOCKS5 proxy (it also takes SOCKS4/4a and HTTP proxy
requests on the same port, and relays SOCKS5 UDP) that sends your traffic straight out and
reshapes the first bytes of each connection, so a filter that matches the site name in the
stream no longer sees it. It has its own anti-poisoning DNS resolver.

oryvexcore starts it as a child process, waits for its ready line, and then reports it like any
other route (`socks5 server listening on ...`). The engine stops by itself when oryvexcore does.

## What it beats, and what it does not

| Filter | Bypass |
| --- | --- |
| Reads the site name packet by packet (stateless DPI) | defeated by splitting / reordering the ClientHello or request |
| DNS poisoning | defeated by the resolver (several resolvers, bogus answers filtered) |
| Reassembles the whole stream before reading it (stateful DPI) | **not** defeated: use a tunnel route |
| Blocks by IP address | **not** defeated: use a tunnel route |

Your IP address does not change. Bypass is the light route: no tunnel, no WARP identity, almost
no overhead.

## Platform integration

- **Windows 10/11 desktop and Windows 7/8/10/11 Lite:** the app starts a local HTTP CONNECT
  listener and automatically points the per-user Windows system proxy at it while Bypass is
  connected. The previous proxy settings are restored on disconnect or the next app launch.
  This covers applications that honor Windows proxy settings; apps that ignore them still need
  to use the local proxy directly.
- **Android 5.0+:** choose Bypass and enable **Whole-device VPN** to route device traffic through
  the engine. The app requests Android's normal VPN permission; no SOCKS/HTTP entry is needed.
- **Linux/macOS CLI:** build/install `oryvexcore` and the native C engine beside one another.
  Use the local SOCKS5/HTTP proxy from the clients you want to route. The project does not ship a
  Linux/macOS GUI or a whole-system Bypass VPN.

## Build

```bash
make                                  # here, with cc
bash build.sh native out/             # the same, to a folder
bash build.sh windows x86_64 out/     # oryvex-bypass.exe (needs zig); x86 for 32-bit
ANDROID_NDK_HOME=... bash build.sh android arm64-v8a out/   # liboryvex_bypass.so
make test                             # the engine's own tests
```

Put the result next to `oryvexcore` (the Android app ships it as `liboryvex_bypass.so` in the
same folder as `liboryvexcore_cli.so`), or point at it with `--bypass-bin`.

## Use

```bash
oryvexcore --bypass                                   # try techniques per site, keep what works
oryvexcore --bypass --bypass-strategy "fake(ttl=4),split(sni)"
oryvexcore --bypass --bypass-keep-quic --bypass-no-doh
oryvexcore --bypass --bypass-args "--decoy-name example.org"
```

Then use `socks5h://127.0.0.1:1819`. `--http-proxy` works too (it forwards to the engine).

The engine can also run on its own: `oryvex-bypass --port 10800 --auto --doh` (see `--help`).
The packet-layer "Advanced" backend (decoy packets with a low TTL, needs WinDivert or NFQUEUE and
administrator rights) is in the sources behind `-DORYVEX_RAW` and is not part of the default build.
