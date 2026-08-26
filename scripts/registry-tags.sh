#!/usr/bin/env bash
# Print the tags that exist in ghcr for an image, one per line.
# Usage: registry-tags.sh <owner> <image>
#
# Anonymous pull scope works for public packages; private ones return no
# tags here (the caller treats "missing" as not-published, which is the
# conservative direction for a skip guard).
set -euo pipefail

owner=${1:?usage: registry-tags.sh <owner> <image>}
image=${2:?usage: registry-tags.sh <owner> <image>}
# tr instead of ${var,,}: macOS ships bash 3.2 (no case-modifier expansion)
owner=$(printf '%s' "$owner" | tr '[:upper:]' '[:lower:]')
image=$(printf '%s' "$image" | tr '[:upper:]' '[:lower:]')

# Retry transient blips (timeouts / 5xx / 429); persistent failures still
# exit non-zero so the caller refuses to decide blindly.
CURL="curl -fsSL --retry 3 --retry-delay 2"

token=$($CURL "https://ghcr.io/token?scope=repository:${owner}/${image}:pull" |
  sed -n 's/.*"token":"\([^"]*\)".*/\1/p')
[ -n "$token" ] || { echo "no anonymous token for ${owner}/${image}" >&2; exit 1; }

url="https://ghcr.io/v2/${owner}/${image}/tags/list?n=1000"
while [ -n "$url" ]; do
  resp=$($CURL -H "Authorization: Bearer $token" -D /tmp/.registry-headers "$url")
  printf '%s' "$resp" | jq -r '.tags[]?'
  url=$(sed -n 's/^[Ll]ink:.*<\([^>]*\)>.*/\1/p' /tmp/.registry-headers)
done
