#!/usr/bin/env bash
# usage: tools/set-repo.sh <github-user>/<repo>   e.g. tools/set-repo.sh alice/OryvexVPN
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <user>/<repo>"; exit 2; }
repo="$1"; user="${repo%%/*}"; name="${repo#*/}"; lower_user="$(echo "$user" | tr 'A-Z' 'a-z')"
ghcr_repo="$(printf '%s/%s' "$user" "$name" | tr 'A-Z' 'a-z')"
cd "$(dirname "$0")/.."
grep -rIl --exclude-dir=vendor --exclude-dir=.git --exclude=*.png -e 'themuvixo' -e 'oryvexofficial/OryvexVPN' -e 'ghcr.io/oryvexofficial/oryvexvpn' . | while read -r f; do
  sed -i.bak -e "s#oryvexofficial.github.io/OryvexVPN#$lower_user.github.io/$name#g" \
             -e "s#oryvexofficial/OryvexVPN#$repo#g" \
             -e "s#ghcr.io/oryvexofficial/oryvexvpn#ghcr.io/$ghcr_repo#g" "$f" && rm -f "$f.bak"
done
echo "links now point at $repo (GHCR: ghcr.io/$ghcr_repo)"
