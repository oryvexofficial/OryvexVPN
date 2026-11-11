#!/usr/bin/env bash
# Refreshes oryvexcore/tor/exit-nodes.txt from the Tor Project's bulk exit list.
# usage: bash tools/update-tor-exits.sh
#   ORYVEX_PROXY=socks5h://127.0.0.1:1820  fetch through a proxy (e.g. the core's Tor port)
set -euo pipefail
cd "$(dirname "$0")/.."
url="${TOR_EXIT_LIST_URL:-https://check.torproject.org/torbulkexitlist}"
out="oryvexcore/tor/exit-nodes.txt"
proxy=()
[ -n "${ORYVEX_PROXY:-}" ] && proxy=(-x "$ORYVEX_PROXY")
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
curl -fsSL --max-time 60 ${proxy[@]+"${proxy[@]}"} "$url" -o "$tmp"
# keep only IPv4/IPv6 addresses, one per line, no duplicates
grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9a-fA-F:]+:[0-9a-fA-F:]*$' "$tmp" | sort -u -V > "$tmp.ok" || true
n="$(wc -l < "$tmp.ok" | tr -d ' ')"
if [ "$n" -lt 100 ]; then echo "only $n addresses came back, keeping the old list" >&2; rm -f "$tmp.ok"; exit 1; fi
mkdir -p "$(dirname "$out")"; mv "$tmp.ok" "$out"
echo "wrote $out: $n exit addresses"
