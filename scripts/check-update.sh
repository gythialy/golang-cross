#!/bin/bash

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
TMP_DIR=tmp
pushd "${REPO_ROOT}" || exit

DOCKERFILE=${1:-Dockerfile.tools}
VERSIONS_JSON=versions.json

[[ -e "${TMP_DIR}" ]] || mkdir -p "${TMP_DIR}"
VERSIONS_ENV=${TMP_DIR}/versions.env
: >"${VERSIONS_ENV}"

is_darwin() {
  case "$(uname -s)" in
  *darwin*) true ;;
  *Darwin*) true ;;
  *) false ;;
  esac
}

sed_inplace() {
  if is_darwin; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

write_version() {
  echo "${1}=${2}" >>"${VERSIONS_ENV}"
}

# keep versions.json in sync after updating the main Dockerfile's golang ARG
sync_versions_json() {
  local major_minor=$1
  local new_version=$2
  local new_sha=$3
  if [[ ! -f "${VERSIONS_JSON}" ]]; then
    return 0
  fi
  # NEW major (listed in .supported but missing from .releases): create the
  # entry with the detected version/sha and explicit default codenames/builders
  # (zig + bookworm/trixie are the forward path since 1.25). The PR diff still
  # surfaces these defaults for a conscious toolchain review.
  if ! jq -e --arg m "${major_minor}" '.releases[$m]' "${VERSIONS_JSON}" >/dev/null 2>&1; then
    jq --arg m "${major_minor}" --arg v "${new_version}" --arg s "${new_sha}" \
      '.releases[$m] = {version: $v, sha256: $s, codenames: ["bookworm", "trixie"], builders: ["zig"]}' \
      "${VERSIONS_JSON}" >"${TMP_DIR}/versions.json.tmp" || return 1
    mv "${TMP_DIR}/versions.json.tmp" "${VERSIONS_JSON}" || return 1
    echo "versions.json: created entry for new major ${major_minor} -> ${new_version} (default zig / bookworm,trixie — review toolchain)"
    return 0
  fi
  local cur_version cur_sha
  cur_version=$(jq -r --arg m "${major_minor}" '.releases[$m].version' "${VERSIONS_JSON}")
  cur_sha=$(jq -r --arg m "${major_minor}" '.releases[$m].sha256' "${VERSIONS_JSON}")
  if [[ "${new_version}" == "${cur_version}" && "${new_sha}" == "${cur_sha}" ]]; then
    return 0
  fi
  jq --arg m "${major_minor}" --arg v "${new_version}" --arg s "${new_sha}" \
    '.releases[$m].version = $v | .releases[$m].sha256 = $s' "${VERSIONS_JSON}" >"${TMP_DIR}/versions.json.tmp" || return 1
  mv "${TMP_DIR}/versions.json.tmp" "${VERSIONS_JSON}" || return 1
  echo "synced versions.json: ${major_minor} -> ${new_version}"
}

# check every supported go major.minor from versions.json for the latest
# stable patch + sha256, and sync any changes back into versions.json.
# The main Dockerfile tracks the newest supported major.
update_golang() {
  local golang_version_file=${TMP_DIR}/golang.json
  curl -fsSL "https://go.dev/dl/?mode=json&include=all" >"${golang_version_file}"

  if [[ ! -f "${VERSIONS_JSON}" ]]; then
    echo "versions.json not found, fall back to single-version check"
    update_golang_single "${golang_version_file}"
    return 0
  fi

  local supported latest_major latest_major_version
  supported=$(jq -r '.supported[]' "${VERSIONS_JSON}")
  if [[ -z "${supported}" ]]; then
    echo "versions.json has no supported list, fall back to single-version check"
    update_golang_single "${golang_version_file}"
    return 0
  fi

  # Discover a newly released Go major (e.g. 1.27 became stable) that is not
  # yet in .supported, and append it so the loop below creates its releases
  # entry (via sync_versions_json) and bumps the tools Dockerfile to it. The
  # newest stable version's major is always the highest supported after this.
  local newest_stable newest_major
  newest_stable=$(jq -r 'first(.[] | select(.stable == true) | .version)' "${golang_version_file}")
  newest_major="${newest_stable%.*}"
  newest_major="${newest_major#go}"
  if [[ -n "${newest_major}" && "${newest_major}" != "null" ]] && ! jq -e --arg m "${newest_major}" '.supported | index($m)' "${VERSIONS_JSON}" >/dev/null 2>&1; then
    jq --arg m "${newest_major}" '.supported += [$m]' "${VERSIONS_JSON}" >"${TMP_DIR}/versions.json.tmp" || return 1
    mv "${TMP_DIR}/versions.json.tmp" "${VERSIONS_JSON}" || return 1
    supported="${supported} ${newest_major}"
    echo "new go major ${newest_major} discovered (${newest_stable}), added to supported"
  fi

  GO_CHANGED=false
  latest_major=""
  UPDATED_MAJORS=""
  for major_minor in ${supported}; do
    local latest_version latest_sha
    latest_version=$(jq -r <"${golang_version_file}" --arg p "go${major_minor}." \
      '[.[] | select(.stable == true and (.version | startswith($p))) | .version][0]')
    latest_sha=$(jq -r <"${golang_version_file}" --arg v "${latest_version}" \
      '[.[] | select(.version == $v) | .files[] | select(.os == "linux" and .arch == "amd64" and .kind == "archive") | .sha256][0]')

    if [[ -z "${latest_version}" || "${latest_version}" == "null" || -z "${latest_sha}" || "${latest_sha}" == "null" ]]; then
      echo "invalid golang version or dist hash value for ${major_minor}"
      exit 1
    fi

    echo "golang ${major_minor}: latest stable ${latest_version}"

    # track the newest supported major for the tools Dockerfile
    if [[ -z "${latest_major}" || "${major_minor}" > "${latest_major}" ]]; then
      latest_major="${major_minor}"
      latest_major_version="${latest_version}"
    fi

    local cur_version cur_sha
    cur_version=$(jq -r --arg m "${major_minor}" '.releases[$m].version' "${VERSIONS_JSON}")
    cur_sha=$(jq -r --arg m "${major_minor}" '.releases[$m].sha256' "${VERSIONS_JSON}")
    if [[ "${latest_version}" == "${cur_version}" && "${latest_sha}" == "${cur_sha}" ]]; then
      echo "golang ${major_minor} is up to date: ${cur_version}"
      continue
    fi
    # Only count majors whose versions.json sync actually succeeded, so a sync
    # failure cannot produce a PR that claims to bump a version it did not
    # persist (e.g. a new major whose entry could not be created).
    if sync_versions_json "${major_minor}" "${latest_version}" "${latest_sha}"; then
      GO_CHANGED=true
      if [[ -z "${UPDATED_MAJORS}" ]]; then
        UPDATED_MAJORS="${major_minor}"
      else
        UPDATED_MAJORS="${UPDATED_MAJORS},${major_minor}"
      fi
      echo -e "update golang ${major_minor}: ${cur_version}: ${cur_sha} -> ${latest_version}: ${latest_sha}"
    else
      echo "failed to sync versions.json for ${major_minor}, skipping" >&2
    fi
  done

  # update the tools Dockerfile to the newest supported major (if needed).
  # Dockerfile.tools FROMs golang:${GO_VERSION}-${OS_CODENAME} with a bare
  # version (no "go" prefix), and no longer downloads the Go tarball, so
  # GOLANG_DIST_SHA is gone from it.
  local go_version_old latest_major_version_bare
  latest_major_version_bare="${latest_major_version#go}"
  go_version_old=$(sed -n 's/ARG GO_VERSION=\(.*\)/\1/p' "$DOCKERFILE")
  if [[ -z "${latest_major_version_bare}" || -z "${go_version_old}" ]]; then
    echo "invalid golang version value"
    exit 1
  fi
  if [[ "${latest_major_version_bare}" != "${go_version_old}" ]]; then
    GO_CHANGED=true
    sed_inplace "s/ARG GO_VERSION=.*/ARG GO_VERSION=${latest_major_version_bare}/" "$DOCKERFILE"
    echo -e "update golang (tools Dockerfile) from $go_version_old to ${latest_major_version_bare}"
  fi

  write_version GO_VERSION "${latest_major_version}"
  # machine-readable list of supported majors that moved (consumed by
  # auto-release-go.yml to build exactly those builder images)
  if [[ -n "${UPDATED_MAJORS}" ]]; then
    write_version UPDATED_MAJORS "${UPDATED_MAJORS}"
  fi
}

# single-version fallback: check only the latest stable release
update_golang_single() {
  local golang_version_file=$1
  local latest_go_version latest_golang_dist_sha
  latest_go_version=$(jq -r <"${golang_version_file}" 'first(.[] | select(.stable == true) | .version)')
  latest_golang_dist_sha=$(jq -r <"${golang_version_file}" 'first(.[] | select(.stable == true) | .files[] | select(.os == "linux" and .arch == "amd64" and .kind == "archive") | .sha256)')

  local go_version_old latest_go_version_bare
  latest_go_version_bare="${latest_go_version#go}"
  go_version_old=$(sed -n 's/ARG GO_VERSION=\(.*\)/\1/p' "$DOCKERFILE")

  if [[ -z "$latest_go_version_bare" || -z "$latest_golang_dist_sha" || -z "$go_version_old" ]]; then
    echo "invalid golang version or dist hash value"
    exit 1
  fi

  GO_CHANGED=false
  if [[ "${latest_go_version_bare}" == "${go_version_old}" ]]; then
    echo "golang is up to date: ${go_version_old}"
  else
    GO_CHANGED=true
    sed_inplace "s/ARG GO_VERSION=.*/ARG GO_VERSION=${latest_go_version_bare}/" "$DOCKERFILE"
    echo -e "update golang from $go_version_old to ${latest_go_version_bare}"
    sync_versions_json "${latest_go_version_bare}" "${latest_go_version}" "${latest_golang_dist_sha}"
    write_version UPDATED_MAJORS "${latest_go_version_bare}"
  fi

  write_version GO_VERSION "${latest_go_version}"
}

update_repo() {
  local repo="$1"
  local file="$2"
  local version="$3"
  local hash="$4"
  local flag="${5:-}"
  local flag_arm64="${6:-}"
  local file_arm64="${7:-${file}}"
  local tmpfile=${TMP_DIR}/repo.json

  curl -fsSL "https://api.github.com/repos/${repo}/releases/latest" >"$tmpfile"

  local latest_version
  local checksum_file
  latest_version=$(jq -r <"${tmpfile}" '.tag_name')
  checksum_file=$(jq -r <"${tmpfile}" --arg name "${file}" '.assets[] | select(.name | endswith($name)).browser_download_url' | head -1)

  if [[ -z "${latest_version}" || "${latest_version}" == "null" || -z "${checksum_file}" || "${checksum_file}" == "null" ]]; then
    echo "get release info failed for ${repo}!!!"
    exit 1
  fi

  local checksum
  if [[ "${checksum_file}" == *checksums.txt ]]; then
    checksum=$(curl -fsSL "${checksum_file}" | grep -e "${flag}" | awk '{print $1}' | head -1)
  else
    checksum=$(curl -fsSL "${checksum_file}" | cut -d ' ' -f 1)
  fi

  if [[ -z "${checksum}" ]]; then
    echo "get checksum failed for ${repo}!!!"
    exit 1
  fi

  # arm64 checksum: requested when a distinct arm64 flag OR asset is given
  local want_arm64=false
  [[ -n "${flag_arm64}" || "${file_arm64}" != "${file}" ]] && want_arm64=true

  local checksum_arm64=""
  if [[ "${want_arm64}" == "true" ]]; then
    local checksum_file_arm64
    checksum_file_arm64=$(jq -r <"${tmpfile}" --arg name "${file_arm64}" '.assets[] | select(.name | endswith($name)).browser_download_url' | head -1)
    if [[ -z "${checksum_file_arm64}" || "${checksum_file_arm64}" == "null" ]]; then
      echo "get arm64 checksum asset failed for ${repo}!!!"
      exit 1
    fi
    if [[ "${checksum_file_arm64}" == *checksums.txt ]]; then
      checksum_arm64=$(curl -fsSL "${checksum_file_arm64}" | grep -e "${flag_arm64}" | awk '{print $1}' | head -1)
    else
      checksum_arm64=$(curl -fsSL "${checksum_file_arm64}" | cut -d ' ' -f 1)
    fi
    if [[ -z "${checksum_arm64}" ]]; then
      echo "get arm64 checksum failed for ${repo}!!!"
      exit 1
    fi
  fi

  local hash_arm64_old=""
  [[ "${want_arm64}" == "true" ]] && hash_arm64_old=$(sed -n "s/^ARG ${hash}_ARM64=//p" "$DOCKERFILE")

  local version_old
  local hash_old
  version_old=$(sed -n "s/ARG ${version}=\(.*\)/\1/p" "$DOCKERFILE")
  hash_old=$(sed -n "s/ARG ${hash}=\(.*\)/\1/p" "$DOCKERFILE")

  # no new version, keep Dockerfile untouched
  if [[ "${latest_version}" == "${version_old}" && "${checksum}" == "${hash_old}" ]] \
    && { [[ "${want_arm64}" == "false" ]] || [[ "${checksum_arm64}" == "${hash_arm64_old}" ]]; }; then
    echo "${repo} is up to date: ${latest_version}"
  else
    sed_inplace "s/ARG ${version}=.*/ARG ${version}=${latest_version}/" "$DOCKERFILE"
    sed_inplace "s/ARG ${hash}=.*/ARG ${hash}=${checksum}/" "$DOCKERFILE"
    [[ "${want_arm64}" == "true" ]] && sed_inplace "s/ARG ${hash}_ARM64=.*/ARG ${hash}_ARM64=${checksum_arm64}/" "$DOCKERFILE"
    echo "update ${repo}, ${latest_version}:${checksum}"
  fi

  write_version "${version}" "${latest_version}"
  write_version "${hash}" "${checksum}"
  [[ "${want_arm64}" == "true" ]] && write_version "${hash}_ARM64" "${checksum_arm64}"
}

update_goimports() {
  # goimports ships in the golang.org/x/tools Go module (no GitHub release),
  # so query the module proxy for the latest version instead.
  local latest_goimports_version
  latest_goimports_version=$(curl -fsSL "https://proxy.golang.org/golang.org/x/tools/@latest" | jq -r '.Version')

  local goimports_version_old
  goimports_version_old=$(sed -n 's/ARG GOIMPORTS_VERSION=\(.*\)/\1/p' "$DOCKERFILE")

  if [[ -z "${latest_goimports_version}" || -z "${goimports_version_old}" ]]; then
    echo "invalid goimports version value"
    exit 1
  fi

  # no new version, keep Dockerfile untouched
  if [[ "${latest_goimports_version}" == "${goimports_version_old}" ]]; then
    echo "goimports is up to date: ${latest_goimports_version}"
  else
    sed_inplace "s/ARG GOIMPORTS_VERSION=.*/ARG GOIMPORTS_VERSION=${latest_goimports_version}/" "$DOCKERFILE"
    echo "update goimports from ${goimports_version_old} to ${latest_goimports_version}"
  fi

  write_version GOIMPORTS_VERSION "${latest_goimports_version}"
}

update_zig() {
  # zig is tracked in Dockerfile.zig (the experimental builder), not the
  # main Dockerfile. ziglang.org/download/index.json lists releases plus
  # "master"; pick the newest semver release.
  local zig_dockerfile=${ZIG_DOCKERFILE:-Dockerfile.zig}
  if [[ ! -f "${zig_dockerfile}" ]]; then
    echo "zig Dockerfile not found: ${zig_dockerfile}, skip"
    return 0
  fi

  local latest_zig_version
  latest_zig_version=$(curl -fsSL "https://ziglang.org/download/index.json" | jq -r '[keys[] | select(. != "master") | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))] | sort_by(split(".") | map(tonumber)) | last')

  local zig_version_old
  zig_version_old=$(sed -n 's/ARG ZIG_VERSION=\(.*\)/\1/p' "${zig_dockerfile}")

  if [[ -z "${latest_zig_version}" || -z "${zig_version_old}" ]]; then
    echo "invalid zig version value"
    exit 1
  fi

  # no new version, keep Dockerfile.zig untouched
  if [[ "${latest_zig_version}" == "${zig_version_old}" ]]; then
    echo "zig is up to date: ${latest_zig_version}"
  else
    sed_inplace "s/ARG ZIG_VERSION=.*/ARG ZIG_VERSION=${latest_zig_version}/" "${zig_dockerfile}"
    echo "update zig from ${zig_version_old} to ${latest_zig_version}"
  fi

  write_version ZIG_VERSION "${latest_zig_version}"
}

# tools-only mode: manually update tool versions without a golang change
# (used by auto-release-go.yml workflow_dispatch input `tools_only`)
TOOLS_ONLY=false
if [[ "${1:-}" == "--tools-only" ]]; then
  TOOLS_ONLY=true
  # $1 is the --tools-only flag, not a Dockerfile path; pin the target
  # explicitly so the tools get updated in the right file.
  DOCKERFILE=Dockerfile.tools
  echo "tools-only mode: skip golang check, update tools only"
fi

if [[ "${TOOLS_ONLY}" != "true" ]]; then
  update_golang
else
  GO_CHANGED=false
fi

# tools follow golang on schedule; in tools-only mode they run regardless
if [[ "${TOOLS_ONLY}" == "true" || "${GO_CHANGED}" == "true" ]]; then
  update_repo 'sigstore/cosign' 'cosign_checksums.txt' 'COSIGN_VERSION' 'COSIGN_SHA' 'cosign-linux-amd64$' 'cosign-linux-arm64$'
  update_repo 'anchore/syft' 'checksums.txt' 'SYFT_VERSION' 'SYFT_SHA' 'linux_amd64.tar.gz$' 'linux_arm64.tar.gz$'
  update_repo 'goreleaser/goreleaser' 'checksums.txt' 'GORELEASER_VERSION' 'GORELEASER_SHA' 'Linux_x86_64.tar.gz$' 'Linux_arm64.tar.gz$'
  update_repo 'ko-build/ko' 'checksums.txt' 'KO_VERSION' 'KO_SHA' 'ko_Linux_x86_64.tar.gz$' 'ko_Linux_arm64.tar.gz$'
  update_repo 'git-chglog/git-chglog' 'checksums.txt' 'GIT_CHGLOG_VERSION' 'GIT_CHGLOG_SHA' 'linux_amd64.tar.gz$' 'linux_arm64.tar.gz$'
  update_repo 'docker/buildx' 'checksums.txt' 'BUILDX_VERSION' 'BUILDX_SHA' 'linux-amd64$' 'linux-arm64$'
  update_repo 'buildpacks/pack' 'linux.tgz.sha256' 'PACK_VERSION' 'PACK_SHA' '' '' 'linux-arm64.tgz.sha256'
  update_goimports
  update_zig
else
  echo "golang unchanged, skip tool updates"
fi

# machine-readable versions for CI (consumed by .github/workflows/auto-release-go.yml)
echo "##VERSIONS##"
cat "${VERSIONS_ENV}"

# clean tmp files
rm -rf ${TMP_DIR}

popd || exit
