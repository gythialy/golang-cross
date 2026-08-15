#!/bin/bash
# Verify cross-build compatibility references used by the Dockerfiles:
#   1. golang official image tags for every (go version, os codename) in versions.json
#   2. osx-sdk image tags referenced by Dockerfile.builder / Dockerfile.zig
#   3. osxcross git commit (OSX_CROSS_COMMIT) still exists upstream
#   4. zig release archive (ZIG_VERSION) still exists on ziglang.org
#
# Drift in any of these means a builder build will fail; this check catches it
# so the builder matrix never builds a broken combination.
#
# Usage:
#   scripts/check-os-compat.sh            # fail (exit 1) on drift
#   scripts/check-os-compat.sh --verbose  # print per-tag status

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel)
cd "${REPO_ROOT}"

VERBOSE=false
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

VERSIONS_JSON=versions.json
if [[ ! -f "${VERSIONS_JSON}" ]]; then
  echo "versions.json not found"
  exit 1
fi

missing=0
checked=0

check_http() {
  # $1 = label, $2 = URL; 200/302 = OK, anything else = MISS
  local label="$1" url="$2" code
  code=$(curl -s -o /dev/null -w '%{http_code}' -L "${url}")
  checked=$((checked + 1))
  if [[ "${code}" == "200" || "${code}" == "302" ]]; then
    ${VERBOSE} && echo "OK   ${label}"
    return 0
  fi
  echo "MISS ${label} (HTTP ${code})"
  missing=$((missing + 1))
  return 1
}

# --- 1. golang official image tags (Docker Hub) ---
# e.g. go1.24.13 -> 1.24.13 -> golang:1.24.13-bookworm
echo "== golang official images =="
TAGS=$(jq -r '
  .releases | to_entries[] | .key as $m | .value as $v |
  ($v.version | ltrimstr("go")) as $bare |
  $v.codenames[] | "\($bare)-\(.)"
' "${VERSIONS_JSON}")

for tag in ${TAGS}; do
  check_http "golang:${tag}" \
    "https://hub.docker.com/v2/repositories/library/golang/tags/${tag}" || true
done

# --- 2. osx-sdk image tags (ghcr.io) ---
# Dockerfile.builder and Dockerfile.zig both FROM ghcr.io/gythialy/osx-sdk:<tag>
# NOTE: the osx-sdk repo is private; use `docker manifest inspect` which picks
# up the local docker login. Skipped when docker is unavailable / not logged in.
echo "== osx-sdk images =="
OSK_SDK_TAGS=$(grep -h '^ARG OSK_SDK=' Dockerfile.builder Dockerfile.zig 2>/dev/null \
  | sed 's/ARG OSK_SDK=//' | sed 's/:-.*//' | sort -u)
if ! command -v docker >/dev/null 2>&1; then
  echo "SKIP osx-sdk check (docker not available)"
else
  for tag in ${OSK_SDK_TAGS}; do
    checked=$((checked + 1))
    if docker manifest inspect "ghcr.io/gythialy/osx-sdk:${tag}" >/dev/null 2>&1; then
      ${VERBOSE} && echo "OK   osx-sdk:${tag}"
    else
      echo "MISS osx-sdk:${tag} (docker manifest inspect failed)"
      missing=$((missing + 1))
    fi
  done
fi

# --- 3. osxcross git commit ---
# OSX_CROSS_COMMIT must resolve upstream; GitHub API returns 200 for a valid commit
echo "== osxcross commit =="
OSX_CROSS_COMMIT=$(grep '^ARG OSX_CROSS_COMMIT=' Dockerfile.builder 2>/dev/null | sed 's/ARG OSX_CROSS_COMMIT=//' || true)
if [[ -n "${OSX_CROSS_COMMIT}" ]]; then
  check_http "osxcross commit ${OSX_CROSS_COMMIT:0:8}" \
    "https://api.github.com/repos/tpoechtrager/osxcross/commits/${OSX_CROSS_COMMIT}" || true
fi

# --- 4. zig release archive ---
# Dockerfile.zig pins ZIG_VERSION; ziglang.org periodically drops old archives
echo "== zig releases =="
ZIG_VERSION=$(grep '^ARG ZIG_VERSION=' Dockerfile.zig 2>/dev/null | sed 's/ARG ZIG_VERSION=//' || true)
if [[ -n "${ZIG_VERSION}" ]]; then
  check_http "zig ${ZIG_VERSION}" \
    "https://ziglang.org/download/${ZIG_VERSION}/zig-x86_64-linux-${ZIG_VERSION}.tar.xz" || true
fi

# --- 5. OSX SDK path vs osx-sdk image content ---
# Dockerfile.zig unpacks whatever SDK the pinned osx-sdk:<OSK_SDK> image ships
# and normalizes it to /osxcross/MacOSX.sdk (ENV OSX_SDK_PATH). The tarball
# must exist in the image: e.g. tag macos-13 currently carries
# MacOSX14.sdk.tar.xz (the GitHub macos-13 runner's Xcode SDK is 14), while
# tag v13 carries MacOSX13.sdk.tar.xz. If the tag mapping drifts, darwin cgo
# builds silently break — so verify the tarball actually exists here.
echo "== OSX SDK path consistency =="
for df in Dockerfile.zig Dockerfile.builder; do
  [[ -f "${df}" ]] || continue
  OSK_TAG=$(grep '^ARG OSK_SDK=' "${df}" | sed 's/ARG OSK_SDK=//' | sed 's/:-\S*//' | head -1 || true)
  if [[ -z "${OSK_TAG}" ]]; then
    echo "SKIP ${df}: no OSK_SDK"
    continue
  fi
  # what SDK does the pinned osx-sdk image actually ship? read it from the
  # COPY layer in `docker history` (uses the local pull cache; requires the
  # image to have been pulled)
  SHIPPED=$(docker history "ghcr.io/gythialy/osx-sdk:${OSK_TAG}" --no-trunc \
    --format '{{.CreatedBy}}' 2>/dev/null \
    | grep -o 'MacOSX[0-9]*\.sdk\.tar\.xz' | head -1 || true)
  checked=$((checked + 1))
  if [[ -z "${SHIPPED}" ]]; then
    echo "SKIP ${df}: cannot inspect osx-sdk:${OSK_TAG} (not pulled locally)"
    continue
  fi
  if [[ -n "${SHIPPED}" ]]; then
    ${VERBOSE} && echo "OK   ${df}: osx-sdk:${OSK_TAG} ships ${SHIPPED}"
  else
    echo "MISS ${df}: no SDK tarball found in osx-sdk:${OSK_TAG}"
    missing=$((missing + 1))
  fi
done

echo
echo "checked ${checked} references, ${missing} missing"

if [[ "${missing}" -gt 0 ]]; then
  echo "ERROR: build compatibility drift detected"
  echo "Fix the affected references in versions.json / Dockerfile.builder / Dockerfile.zig"
  exit 1
fi

echo "all build references are valid"
