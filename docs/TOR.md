# Tor route and exit selection

SSTP has been removed. Tor is now a route of its own (protocol **Tor** in the apps, `--tor-only` on the CLI), and also available as "Tor via tunnel" (`--tor`).

## Exit choice (`--tor-exit`)
- `auto` (default): Tor picks an exit itself, weighted by bandwidth.
- `fastest`: on every connect the core opens a test stream through exits in the 6 best-served countries and keeps the quickest.
- `de` or `de,nl,se`: leave from that country, first that answers. Add `--tor-exit-strict` to fail instead of falling back.

## Where the exit list comes from
torproject.org is filtered on many networks, so the exit directory (Onionoo `details?flag=Exit&running=true`) is **only ever fetched through Tor itself**, after Tor bootstraps, and cached in `<tor-dir>/exits.json`. Until then a bundled list of 32 long-standing exit countries is used. The country of each relay is resolved locally by Arti's bundled GeoIP table, no lookup service. Mirror: `ORYVEXCORE_TOR_EXIT_API`.

Arti cannot pin a single exit relay by fingerprint, so "server" selection is per country. Exit-country selection needs the `tor-exit-country` cargo feature; CI and `scripts/build-core.sh` fall back to plain `tor` (exit = auto) if it does not build.
