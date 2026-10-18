#!/usr/bin/env bash
# Cut the GitHub release(s) that publish a Go line's images.
#
# Since #473 a published GitHub release on `vX.Y.Z-N` is the only thing that
# publishes: draft releases never fire, a bare `vX.Y.Z` tag is skipped, and the
# workflows refuse to publish from a branch ref. Cutting one by hand means
# remembering the target commit, the revision, which majors want `--latest`, and
# writing notes that match what will actually be pushed.
#
# This script does that bookkeeping and stops before the publish:
#
#   scripts/release.sh 1.27.2                    # dry run, current commit
#   scripts/release.sh 1.26.9 1.27.2 --execute   # one release per major
#   scripts/release.sh 1.27 -t origin/main       # tag a specific commit/ref
#
# The target defaults to the current commit (HEAD), so check out or switch to the
# commit you mean to publish first. It refuses to tag a commit whose
# versions.json does not pin the version being released.
#
# Usage: release.sh <version>... [options]
#
#   <version>...         one or more Go patches (1.27.2 or go1.27.2), or a major
#                        (1.27) to use whatever versions.json pins for it. One
#                        release per major; a major may appear only once.
#   -n, --revision N     build revision (default: first free N for that patch)
#   -t, --target REF     ref to tag (default: HEAD, the current commit)
#       --previous TAG   base tag for the changelog link (default: detected)
#       --notes FILE     use FILE instead of the generated notes (single version only)
#       --latest         force GitHub's "latest" badge on every release
#       --no-latest      force it off (default: on only for the newest major)
#       --execute, -y    actually run `gh release create`
#       --dry-run        only print the plan (the default)
#   -h, --help
#
# Exit status: 0 ok, 1 bad input / refused, 2 missing dependency.
set -euo pipefail

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
  exit 1
}

die() {
  echo "error: $*" >&2
  exit 1
}

versions=()
revision=""
target="HEAD"
previous=""
notes_file=""
latest="auto"
execute=0

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage ;;
    -n | --revision)
      [ $# -ge 2 ] || die "--revision needs a value"
      revision=$2
      shift 2
      ;;
    -t | --target)
      [ $# -ge 2 ] || die "--target needs a value"
      target=$2
      shift 2
      ;;
    --previous)
      [ $# -ge 2 ] || die "--previous needs a value"
      previous=$2
      shift 2
      ;;
    --notes)
      [ $# -ge 2 ] || die "--notes needs a value"
      notes_file=$2
      shift 2
      ;;
    --latest) latest=yes; shift ;;
    --no-latest) latest=no; shift ;;
    --execute | -y) execute=1; shift ;;
    --dry-run) execute=0; shift ;;
    -*) die "unknown option: $1" ;;
    *)
      versions+=("$1")
      shift
      ;;
  esac
done

[ "${#versions[@]}" -gt 0 ] || usage
if [ -n "${notes_file}" ] && [ "${#versions[@]}" -gt 1 ]; then
  die "--notes is per-release and cannot be used with several versions"
fi

for tool in git jq; do
  command -v "${tool}" >/dev/null 2>&1 || {
    echo "error: ${tool} is required" >&2
    exit 2
  }
done
if [ "${execute}" = 1 ]; then
  command -v gh >/dev/null 2>&1 || {
    echo "error: gh is required to --execute" >&2
    exit 2
  }
fi

root=$(git rev-parse --show-toplevel 2>/dev/null) || die "not inside a git checkout"
cd "${root}" || exit 2
[ -f versions.json ] || die "versions.json not found under ${root}"

repo_slug=$(git config --get remote.origin.url 2>/dev/null |
  sed -E 's#^(git@|https://|ssh://)[^:/]+[:/]##; s#\.git$##' || true)
if [ -z "${repo_slug}" ]; then
  repo_slug="gythialy/golang-cross"
fi
repo_url="https://github.com/${repo_slug}"

# ---------------------------------------------------------------- target ---
sha=$(git rev-parse --verify --quiet "${target}^{commit}" 2>/dev/null) ||
  die "cannot resolve ${target}; fetch it first (git fetch origin)"
short=$(git rev-parse --short "${sha}")
main_sha=$(git rev-parse --verify --quiet 'origin/main^{commit}' || true)
if [ -n "${main_sha}" ] && ! git merge-base --is-ancestor "${sha}" "${main_sha}" 2>/dev/null; then
  echo "warning: ${short} is not on origin/main; make sure that is intended" >&2
fi

# One tag list for every version: the remote is authoritative, the local list is
# the fallback for a clone without a readable remote.
if raw=$(git ls-remote --tags --refs origin 2>/dev/null); then
  all_tags=$(printf '%s\n' "${raw}" | sed 's#.*refs/tags/##')
else
  all_tags=$(git tag -l)
fi

# ------------------------------------------------------------- validate ---
declare -a majors=()
declare -a bares=()
for v in "${versions[@]}"; do
  stripped=${v#go}
  case "${stripped}" in
    *.*.*) major=$(printf '%s' "${stripped}" | cut -d. -f1,2) ;;
    *.*) major=${stripped} ;;
    *) die "expected a Go version like 1.27.2, or a major like 1.27 (got '${v}')" ;;
  esac

  for m in ${majors[@]+"${majors[@]}"}; do
    [ "${m}" = "${major}" ] || continue
    die "${major} was given twice; one release per major (a release publishes one line)"
  done

  if ! jq -e --arg m "${major}" '.supported | index($m)' versions.json >/dev/null 2>&1; then
    die "${major} is not in versions.json's supported list ($(jq -r '.supported | join(", ")' versions.json))
It may be end-of-life; publishing it would only add drift."
  fi

  pinned=$(jq -r --arg m "${major}" '.releases[$m].version // ""' versions.json)
  [ -n "${pinned}" ] || die "versions.json has no releases.${major}.version"
  bare=${pinned#go}
  if [ "${stripped}" != "${major}" ] && [ "${stripped}" != "${bare}" ]; then
    die "${major} is pinned to ${pinned} in versions.json, not ${stripped}"
  fi

  at_target=$(git show "${sha}:versions.json" 2>/dev/null |
    jq -r --arg m "${major}" '.releases[$m].version // ""' 2>/dev/null) ||
    die "${short} has no versions.json"
  if [ "${at_target}" != "${pinned}" ]; then
    die "${short} (${target}) pins ${major} to '${at_target}', but this checkout has '${pinned}'.
Tag the commit whose versions.json matches what you mean to publish."
  fi

  majors+=("${major}")
  bares+=("${bare}")
done

# ---------------------------------------------------------------- plan ---
newest_major=$(jq -r '.supported | sort_by(split(".") | map(tonumber)) | .[-1]' versions.json)

declare -a tags=()
declare -a notes_files=()
declare -a latest_flags=()

gen_notes() { # <notes file> <bare> <revision> <builders> <codenames> <tag> <major> <previous>
  local out=$1 bare=$2 rev=$3 builders=$4 codenames=$5 tag=$6 major=$7 prev=$8
  local zig_tags="" osx_tags="" builder_tags="" tools_tags=""
  local c
  local -a codename_list
  read -r -a codename_list <<<"${codenames}"

  for c in "${codename_list[@]}"; do
    tools_tags="${tools_tags}\`v${bare}-${rev}-${c}\`, "
    case " ${builders} " in
      *" zig "*)
        zig_tags="${zig_tags}\`v${bare}-${rev}-${c}-zig\`, "
        if [ "${c}" = trixie ]; then
          zig_tags="${zig_tags}\`v${bare}-${rev}\`, "
        fi
        ;;
    esac
    case " ${builders} " in
      *" osxcross "*)
        osx_tags="${osx_tags}\`v${bare}-${rev}-${c}\`, "
        builder_tags="${builder_tags}\`v${bare}-${rev}-${c}\`, "
        ;;
    esac
  done
  zig_tags=${zig_tags%, }
  osx_tags=${osx_tags%, }
  builder_tags=${builder_tags%, }
  tools_tags=${tools_tags%, }

  {
    printf "Go %s toolchain — build revision **%s**.\n\n" "${bare}" "${rev}"
    printf "Published by the release of \`%s\` from \`%s\` (\`%s\`).\n\n" \
      "${tag}" "${short}" "${target}"
    printf "### Images\n\n| repository | tags |\n| --- | --- |\n"
    if [ -n "${zig_tags}" ]; then
      printf "| \`golang-cross\` (zig) | %s; \`%s-zig\` float |\n" "${zig_tags}" "${major}"
    fi
    if [ -n "${osx_tags}" ]; then
      printf "| \`golang-cross\` (osxcross) | %s |\n" "${osx_tags}"
    fi
    if [ -n "${builder_tags}" ]; then
      printf "| \`golang-cross-builder\` | %s |\n" "${builder_tags}"
    fi
    printf "| \`golang-cross-tools\` | %s |\n\n" "${tools_tags}"
    printf "\`%s\` (no codename) is the trixie **zig** build, matching the alias rules;\n" \
      "${tag}"
    printf "a major that also ships osxcross is pinned through its codename-suffixed\n"
    printf "tags. Release tooling is whatever \`Dockerfile.tools\` pins at \`%s\`.\n\n" "${short}"
    printf "### Verify\n\n\`\`\`sh\n"
    if [ -n "${zig_tags}" ]; then
      cat <<VERIFY
cosign verify ghcr.io/gythialy/golang-cross:${tag}-trixie-zig \\
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\
  --certificate-identity "${repo_url}/.github/workflows/builder.yml@refs/tags/${tag}"
VERIFY
    fi
    if [ -n "${osx_tags}" ]; then
      printf "\n"
      cat <<VERIFY
cosign verify ghcr.io/gythialy/golang-cross:${tag}-trixie \\
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\
  --certificate-identity "${repo_url}/.github/workflows/release-golang-cross.yml@refs/tags/${tag}"
VERIFY
    fi
    printf "\`\`\`\n\n"
    if [ -n "${prev}" ]; then
      printf "**Full Changelog**: %s/compare/%s...%s\n" "${repo_url}" "${prev}" "${tag}"
    fi
  } >"${out}"
}

index=0
for v in "${versions[@]}"; do
  major=${majors[${index}]}
  bare=${bares[${index}]}
  index=$((index + 1))

  builders=$(jq -r --arg m "${major}" '.releases[$m].builders | join(" ")' versions.json)
  codenames=$(jq -r --arg m "${major}" '.releases[$m].codenames | join(" ")' versions.json)
  escaped=$(printf '%s' "${bare}" | sed 's/\./\\./g')

  if [ -n "${revision}" ]; then
    rev=${revision}
  else
    highest=$(printf '%s\n' "${all_tags}" | grep -oE "^v${escaped}-[0-9]+$" |
      sed -E "s/^v${escaped}-//" | sort -n | tail -1 || true)
    rev=$(( ${highest:--1} + 1 ))
  fi
  case "${rev}" in
    '' | *[!0-9]*) die "--revision must be a number, got '${rev}'" ;;
  esac

  tag="v${bare}-${rev}"
  if printf '%s\n' "${all_tags}" | grep -Fxq -- "${tag}"; then
    die "${tag} already exists (locally or on origin); pass --revision to cut the next one"
  fi

  prev=${previous}
  if [ -z "${prev}" ]; then
    prev=$(printf '%s\n' "${all_tags}" |
      grep -E "^v${major//./\\.}\.[0-9]+-[0-9]+$" |
      grep -Fxv -- "${tag}" | sort -V | tail -1 || true)
  fi

  if [ "${latest}" = auto ]; then
    if [ "${major}" = "${newest_major}" ]; then flag=yes; else flag=no; fi
  else
    flag=${latest}
  fi

  out=${notes_file}
  if [ -z "${out}" ]; then
    out="$(git rev-parse --git-dir)/release-notes-${tag}.md"
    gen_notes "${out}" "${bare}" "${rev}" "${builders}" "${codenames}" "${tag}" "${major}" "${prev}"
  fi

  tags+=("${tag}")
  notes_files+=("${out}")
  latest_flags+=("${flag}")

  printf 'release %s\n' "${tag}"
  printf '  version:   go%s (%s)\n' "${bare}" "${major}"
  printf '  target:    %s (%s)\n' "${short}" "${target}"
  printf '  builders:  %s\n' "${builders}"
  printf '  codenames: %s\n' "${codenames}"
  printf '  latest:    %s\n' "${flag}"
  printf '  notes:     %s\n' "${out}"
  if [ -n "${prev}" ]; then
    printf '  compare:   %s...%s\n' "${prev}" "${tag}"
  fi
  printf '\n----- notes -----\n'
  cat "${out}"
  printf '\n-----------------\n\n'
done

# -------------------------------------------------------------- commands ---
for i in "${!tags[@]}"; do
  cmd=(gh release create "${tags[${i}]}" --target "${sha}" --title "${tags[${i}]}"
    --notes-file "${notes_files[${i}]}")
  if [ "${latest_flags[${i}]}" = no ]; then
    cmd+=(--latest=false)
  fi
  printf 'command %d:\n  ' $((i + 1))
  printf '%s ' "${cmd[@]}"
  printf '\n'
done

if [ "${execute}" != 1 ]; then
  printf '\n(dry run — re-run with --execute to publish)\n'
  exit 0
fi

for i in "${!tags[@]}"; do
  cmd=(gh release create "${tags[${i}]}" --target "${sha}" --title "${tags[${i}]}"
    --notes-file "${notes_files[${i}]}")
  if [ "${latest_flags[${i}]}" = no ]; then
    cmd+=(--latest=false)
  fi
  "${cmd[@]}"
done

printf '\nrelease(s) created. follow the publishing runs with:\n'
printf '  gh run list --workflow builder.yml -L 3              # zig + tools\n'
printf '  gh run list --workflow release-golang-cross.yml -L 3  # osxcross majors\n'
