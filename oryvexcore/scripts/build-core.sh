#!/usr/bin/env bash
# Builds the core with Tor and Tor exit-country selection, and falls back on plain Tor when the
# exit-country feature does not build (it rides arti's GeoIP API, which is newer than the rest).
#
# usage (from oryvexcore/):
#   bash scripts/build-core.sh cargo build --release --target x86_64-unknown-linux-gnu
#   bash scripts/build-core.sh cargo ndk -t arm64-v8a --platform 29 build --release
#
# The features are appended to the command given. The ones that built are written to
# target/oryvexcore-features.txt and, on GitHub Actions, exported as CORE_FEATURES_USED, so the
# license notices are made for exactly what was built.
#
#   CORE_FEATURES           what to try first   (default: tor,tor-exit-country)
#   CORE_FALLBACK_FEATURES  what to fall back on (default: tor)
#   CORE_FEATURES_STRICT=1  fail instead of falling back
set -uo pipefail

[ $# -ge 2 ] || { echo "usage: $0 <cargo command...>" >&2; exit 2; }

want="${CORE_FEATURES:-tor,tor-exit-country}"
fallback="${CORE_FALLBACK_FEATURES:-tor}"
used="$want"

if ! "$@" --features "$want"; then
  if [ "${CORE_FEATURES_STRICT:-0}" = 1 ] || [ "$want" = "$fallback" ]; then
    echo "core build failed with features '$want'" >&2
    exit 1
  fi
  echo "::warning title=Tor exit-country selection left out::the core did not build with '$want'; building with '$fallback'. The app still works, --tor-exit falls back on auto."
  if ! "$@" --features "$fallback"; then
    echo "core build failed with features '$fallback' too" >&2
    exit 1
  fi
  used="$fallback"
fi

mkdir -p "${CARGO_TARGET_DIR:-target}"
echo "$used" > "${CARGO_TARGET_DIR:-target}/oryvexcore-features.txt"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "CORE_FEATURES_USED=$used" >> "$GITHUB_ENV"
fi
echo "core built with features: $used"
