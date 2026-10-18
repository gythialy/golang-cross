#!/usr/bin/env bash
# Report supported Go versions in versions.json that are not properly released.
#
# versions.json is the source of truth for the Go patch each supported major
# builds from, but nothing tied it to reality: a version could be bumped and
# merged while nobody ever cut the vX.Y.Z-N release that publishes it. That is
# how the 1.24 (go1.24.13) and 1.25 (go1.25.14) lines drifted (#483):
#
#   1.24.13  no images at all
#   1.25.14  images exist, but from the push-triggered publisher that #473
#            retired — no git tag, no release, and signed @refs/heads/main, so
#            nobody can pin them to a version
#
# A release can also stop *half way*: the zig legs and the release tag can exist
# while the osxcross legs are still building or have failed. "Some image plus a
# tag" is therefore not enough — this checks the complete expected tag set at the
# newest release revision, mirroring the skip guard in release-golang-cross.yml
# (#491).
#
# Usage: release-drift.sh [--text|--markdown|--json]
#
# Status per supported major, evaluated at the newest release-tag revision N:
#   published   every expected tag exists
#   incomplete  the release tag exists but expected tags are missing (N listed)
#   unreleased  images exist but no release tag (unpinnable, e.g. old push builds)
#   missing     neither
#
# Exit status:
#   0  every supported major is published
#   1  at least one is not (drift)
#   2  the registry or the tag list could not be read — never reported as drift
#
# OWNER and IMAGE override the inferred repository owner and main image name.
set -euo pipefail

usage() {
  echo "usage: $(basename "$0") [--text|--markdown|--json]" >&2
  exit 2
}

format=text
case "${1:-}" in
  --text) format=text ;;
  --markdown) format=markdown ;;
  --json) format=json ;;
  '') ;;
  *) usage ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
cd "${root}" || exit 2
if [ ! -f versions.json ]; then
  echo "versions.json not found under ${root}" >&2
  exit 2
fi

# GITHUB_REPOSITORY is set on Actions runners; fall back to the git remote so
# the script also works from a developer checkout.
owner=${OWNER:-${GITHUB_REPOSITORY:-}}
owner=${owner%%/*}
if [ -z "${owner}" ]; then
  # `|| true`: under `set -e` a checkout without a remote would otherwise abort
  # with no message instead of reaching the explicit error below.
  remote=$(git config --get remote.origin.url 2>/dev/null || true)
  owner=$(printf '%s' "${remote}" | sed -E 's#^(git@|https://|ssh://)[^:/]+[:/]([^/]+)/.*#\2#')
fi
if [ -z "${owner}" ]; then
  echo "cannot determine the repository owner; set OWNER" >&2
  exit 2
fi
image=${IMAGE:-golang-cross}

tmp=$(mktemp -d)
trap 'rm -rf "${tmp:-}"' EXIT

# One listing per repository the expected sets actually reference. A registry
# that cannot be read is a broken check, not a finding, so it exits 2 instead of
# being reported as drift.
fetch_tags() { # <repository> <listing name>
  if ! bash scripts/registry-tags.sh "${owner}" "$1" >"${tmp}/$2" 2>"${tmp}/$2.err"; then
    echo "cannot list tags for ${owner}/$1:" >&2
    cat "${tmp}/$2.err" >&2
    exit 2
  fi
}

fetch_tags "${image}" main
fetch_tags golang-cross-tools tools
# The osxcross builder image only exists for majors that ship that builder.
if [ "$(jq -r '[.releases[] | select(.builders | index("osxcross"))] | length > 0' versions.json)" = true ]; then
  fetch_tags golang-cross-builder builder
fi

# Release tags, from the remote so a stale clone cannot hide a release. Falls
# back to the local tag list when the remote is not readable (private forks).
if raw=$(git ls-remote --tags --refs origin 2>/dev/null); then
  printf '%s\n' "${raw}" | sed 's#.*refs/tags/##' >"${tmp}/git-tags"
else
  git tag -l >"${tmp}/git-tags"
fi

# rows: <major>|<version>|<status>|<revision>|<missing>|<newest image>|<release tag>
: >"${tmp}/rows"
drift=0
while IFS='|' read -r major version builders codenames; do
  [ -n "${major}" ] || continue
  bare=${version#go}
  # `v1.24.13-0`, `v1.24.13-0-trixie-zig`, ... The trailing dash keeps v1.24.1
  # from matching v1.24.13.
  escaped=$(printf '%s' "${bare}" | sed 's/\./\\./g')

  # Newest revision with a release tag (what "published" has to mean) and the
  # newest revision with any image (what to show when nothing is released).
  tag_rev=$(grep -oE "^v?${escaped}-[0-9]+$" "${tmp}/git-tags" |
    sed -E "s/^v?${escaped}-//" | sort -n | tail -1 || true)
  image_rev=$(grep -oE "^v?${escaped}-[0-9]+" "${tmp}/main" |
    sed -E "s/^v?${escaped}-//" | sort -n | tail -1 || true)

  newest_image=""
  if [ -n "${image_rev}" ]; then
    newest_image="v${bare}-${image_rev}"
  fi
  release_tag=""
  if [ -n "${tag_rev}" ]; then
    release_tag="v${bare}-${tag_rev}"
  fi

  if [ -z "${tag_rev}" ]; then
    revision=""
    missing=""
    if [ -n "${image_rev}" ]; then
      status=unreleased
    else
      status=missing
    fi
    drift=$((drift + 1))
  else
    revision="${tag_rev}"
    # The expected set mirrors the skip guard in release-golang-cross.yml: the
    # tools base for every codename, the zig image for every codename plus the
    # codename-less alias (owned by trixie), and for osxcross both the builder
    # base and the main image it produces.
    missing=""
    alias_done=0
    for codename in $(printf '%s' "${codenames}" | tr ',' ' '); do
      want="v${bare}-${revision}-${codename}"
      if ! grep -Fxq -- "${want}" "${tmp}/tools"; then
        missing="${missing:+${missing},}golang-cross-tools:${want}"
      fi
      case ",${builders}," in
        *",zig,"*)
          want="v${bare}-${revision}-${codename}-zig"
          if ! grep -Fxq -- "${want}" "${tmp}/main"; then
            missing="${missing:+${missing},}${image}:${want}"
          fi
          if [ "${codename}" = trixie ] && [ "${alias_done}" = 0 ]; then
            want="v${bare}-${revision}"
            if ! grep -Fxq -- "${want}" "${tmp}/main"; then
              missing="${missing:+${missing},}${image}:${want}"
            fi
            alias_done=1
          fi
          ;;
      esac
      case ",${builders}," in
        *",osxcross,"*)
          want="v${bare}-${revision}-${codename}"
          if ! grep -Fxq -- "${want}" "${tmp}/builder"; then
            missing="${missing:+${missing},}golang-cross-builder:${want}"
          fi
          if ! grep -Fxq -- "${want}" "${tmp}/main"; then
            missing="${missing:+${missing},}${image}:${want}"
          fi
          ;;
      esac
    done
    if [ -z "${missing}" ]; then
      status=published
    else
      status=incomplete
      drift=$((drift + 1))
    fi
  fi

  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "${major}" "${version}" "${status}" "${revision}" "${missing}" \
    "${newest_image}" "${release_tag}" >>"${tmp}/rows"
done < <(jq -r '.supported[] as $m
  | "\($m)|\(.releases[$m].version // "")|\(.releases[$m].builders | join(","))|\(.releases[$m].codenames | join(","))"' versions.json)

case "${format}" in
  json)
    jq -n --rawfile rows "${tmp}/rows" --arg owner "${owner}" --arg image "${image}" '
      ($rows | split("\n") | map(select(length > 0) | split("|")
        | {
            major: .[0],
            version: .[1],
            status: .[2],
            revision: (if .[3] == "" then null else (.[3] | tonumber) end),
            missing: (if .[4] == "" then [] else (.[4] | split(",")) end),
            newest_image: (.[5] // ""),
            release_tag: (.[6] // "")
          })) as $majors
      | {
          owner: $owner,
          image: $image,
          unpublished: [$majors[] | select(.status != "published") | .major],
          majors: $majors
        }'
    ;;
  markdown)
    echo "| major | versions.json | revision | missing | status |"
    echo "| --- | --- | --- | --- | --- |"
    while IFS='|' read -r major version status revision missing _newest _tag; do
      [ -n "${major}" ] || continue
      shown="${missing:-—}"
      [ "${#shown}" -le 160 ] || shown="${shown:0:157}…"
      printf "| \`%s\` | \`%s\` | %s | %s | %s |\n" \
        "${major}" "${version}" "${revision:-—}" "${shown}" "${status}"
    done <"${tmp}/rows"
    ;;
  *)
    while IFS='|' read -r major version status revision missing newest_image release_tag; do
      [ -n "${major}" ] || continue
      printf '%-6s %-10s %-11s rev=%-3s image=%-26s tag=%s\n' \
        "${major}" "${version}" "${status}" "${revision:--}" \
        "${newest_image:--}" "${release_tag:--}"
      if [ -n "${missing}" ]; then
        printf '       missing: %s\n' "${missing}"
      fi
    done <"${tmp}/rows"
    if [ "${drift}" -gt 0 ]; then
      printf '%s supported major(s) are not properly released\n' "${drift}" >&2
    fi
    ;;
esac

if [ "${drift}" -gt 0 ]; then
  exit 1
fi
exit 0
