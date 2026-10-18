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
# Both are invisible to CI, which is the point of this check: since #473 the
# release tag is the only thing that publishes, so "is there a release tag?"
# and "are there images?" are two separate questions and neither alone is the
# answer.
#
# Usage: release-drift.sh [--text|--markdown|--json]
#
# Status per supported major:
#   published   images and a release tag
#   unreleased  images but no release tag (unpinnable, e.g. old push builds)
#   failed      release tag but no images (publishing did not finish)
#   missing     neither
#
# Exit status:
#   0  every supported major is published
#   1  at least one is not (drift)
#   2  the registry or the tag list could not be read — never reported as drift
#
# OWNER and IMAGE override the inferred repository owner and image name.
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
  owner=$(git config --get remote.origin.url 2>/dev/null |
    sed -E 's#^(git@|https://|ssh://)[^:/]+[:/]([^/]+)/.*#\2#')
fi
if [ -z "${owner}" ]; then
  echo "cannot determine the repository owner; set OWNER" >&2
  exit 2
fi
image=${IMAGE:-golang-cross}

tmp=$(mktemp -d)
trap 'rm -rf "${tmp:-}"' EXIT

# One listing for every major. registry-tags.sh already retries transient
# failures and exits non-zero when ghcr cannot be read; that is a broken check,
# not a finding, so it must not be reported as drift.
if ! bash scripts/registry-tags.sh "${owner}" "${image}" >"${tmp}/tags" 2>"${tmp}/err"; then
  echo "cannot list tags for ${owner}/${image}:" >&2
  cat "${tmp}/err" >&2
  exit 2
fi

# Release tags, from the remote so a stale clone cannot hide a release. Falls
# back to the local tag list when the remote is not readable (private forks).
if raw=$(git ls-remote --tags --refs origin 2>/dev/null); then
  printf '%s\n' "${raw}" | sed 's#.*refs/tags/##' >"${tmp}/git-tags"
else
  git tag -l >"${tmp}/git-tags"
fi

# rows: <major>\t<version>\t<status>\t<newest image tag>\t<newest release tag>
: >"${tmp}/rows"
drift=0
while IFS=$'\t' read -r major version; do
  [ -n "${major}" ] || continue
  bare=${version#go}
  # `v1.24.13-0`, `v1.24.13-0-trixie-zig`, ... — any revision, any codename. The
  # trailing dash keeps v1.24.1 from matching v1.24.13.
  escaped=$(printf '%s' "${bare}" | sed 's/\./\\./g')
  images=$(grep -E "^v?${escaped}-[0-9]+" "${tmp}/tags" | sort -V || true)
  tags=$(grep -E "^v?${escaped}-[0-9]+$" "${tmp}/git-tags" | sort -V || true)
  newest_image=$(printf '%s\n' "${images}" | tail -1)
  newest_tag=$(printf '%s\n' "${tags}" | tail -1)
  if [ -n "${images}" ] && [ -n "${tags}" ]; then
    status=published
  elif [ -n "${images}" ]; then
    status=unreleased
  elif [ -n "${tags}" ]; then
    status=failed
  else
    status=missing
  fi
  [ "${status}" = published ] || drift=$((drift + 1))
  printf '%s\t%s\t%s\t%s\t%s\n' \
    "${major}" "${version}" "${status}" "${newest_image}" "${newest_tag}" >>"${tmp}/rows"
done < <(jq -r '.supported[] as $m | "\($m)\t\(.releases[$m].version // "")"' versions.json)

case "${format}" in
  json)
    jq -n --rawfile rows "${tmp}/rows" --arg owner "${owner}" --arg image "${image}" '
      ($rows | split("\n") | map(select(length > 0) | split("\t")
        | {
            major: .[0],
            version: .[1],
            status: .[2],
            newest_image: (.[3] // ""),
            release_tag: (.[4] // "")
          })) as $majors
      | {
          owner: $owner,
          image: $image,
          unpublished: [$majors[] | select(.status != "published") | .major],
          majors: $majors
        }'
    ;;
  markdown)
    echo "| major | versions.json | newest image | release tag | status |"
    echo "| --- | --- | --- | --- | --- |"
    while IFS=$'\t' read -r major version status newest_image newest_tag; do
      [ -n "${major}" ] || continue
      printf "| \`%s\` | \`%s\` | %s | %s | %s |\n" \
        "${major}" "${version}" "${newest_image:-—}" "${newest_tag:-—}" "${status}"
    done <"${tmp}/rows"
    ;;
  *)
    while IFS=$'\t' read -r major version status newest_image newest_tag; do
      [ -n "${major}" ] || continue
      printf '%-6s %-10s %-11s image=%-26s tag=%s\n' \
        "${major}" "${version}" "${status}" "${newest_image:-—}" "${newest_tag:-—}"
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
