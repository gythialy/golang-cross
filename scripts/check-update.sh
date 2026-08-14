#!/bin/bash

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
TMP_DIR=tmp
pushd "${REPO_ROOT}" || exit

DOCKERFILE=${1:-Dockerfile}

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

update_golang() {
  local golang_version_file=${TMP_DIR}/golang.json
  curl -fsSL "https://go.dev/dl/?mode=json" >"${golang_version_file}"

  # latest stable golang release: linux/amd64 archive (the .tar.gz used by Dockerfile)
  local latest_go_version
  local latest_golang_dist_sha
  latest_go_version=$(jq -r <"${golang_version_file}" 'first(.[] | select(.stable == true) | .version)')
  latest_golang_dist_sha=$(jq -r <"${golang_version_file}" 'first(.[] | select(.stable == true) | .files[] | select(.os == "linux" and .arch == "amd64" and .kind == "archive") | .sha256)')

  local go_version_old
  local golang_dist_sha_old
  go_version_old=$(sed -n 's/ARG GO_VERSION=\(.*\)/\1/p' "$DOCKERFILE")
  golang_dist_sha_old=$(sed -n 's/ARG GOLANG_DIST_SHA=\(.*\)/\1/p' "$DOCKERFILE")

  # check latest_go_version latest_golang_dist_sha go_version_old golang_dist_sha_old are set
  if [[ -z "$latest_go_version" || -z "$latest_golang_dist_sha" || -z "$go_version_old" || -z "$golang_dist_sha_old" ]]; then
    echo "invalid golang version or dist hash value"
    exit 1
  fi

  # no new version, keep Dockerfile untouched
  GO_CHANGED=false
  if [[ "${latest_go_version}" == "${go_version_old}" && "${latest_golang_dist_sha}" == "${golang_dist_sha_old}" ]]; then
    echo "golang is up to date: ${go_version_old}"
  else
    GO_CHANGED=true
    sed_inplace "s/ARG GO_VERSION=.*/ARG GO_VERSION=${latest_go_version}/" "$DOCKERFILE"
    sed_inplace "s/ARG GOLANG_DIST_SHA=.*/ARG GOLANG_DIST_SHA=${latest_golang_dist_sha}/" "$DOCKERFILE"
    echo -e "update golang from $go_version_old: $golang_dist_sha_old to ${latest_go_version}: ${latest_golang_dist_sha}"
  fi

  write_version GO_VERSION "${latest_go_version}"
  write_version GOLANG_DIST_SHA "${latest_golang_dist_sha}"
}

update_repo() {
  local repo="$1"
  local file="$2"
  local version="$3"
  local hash="$4"
  local flag="${5:-}"
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

  local version_old
  local hash_old
  version_old=$(sed -n "s/ARG ${version}=\(.*\)/\1/p" "$DOCKERFILE")
  hash_old=$(sed -n "s/ARG ${hash}=\(.*\)/\1/p" "$DOCKERFILE")

  # no new version, keep Dockerfile untouched
  if [[ "${latest_version}" == "${version_old}" && "${checksum}" == "${hash_old}" ]]; then
    echo "${repo} is up to date: ${latest_version}"
  else
    sed_inplace "s/ARG ${version}=.*/ARG ${version}=${latest_version}/" "$DOCKERFILE"
    sed_inplace "s/ARG ${hash}=.*/ARG ${hash}=${checksum}/" "$DOCKERFILE"
    echo "update ${repo}, ${latest_version}:${checksum}"
  fi

  write_version "${version}" "${latest_version}"
  write_version "${hash}" "${checksum}"
}

update_golang

# tools are only updated together with a golang release
if [[ "${GO_CHANGED}" == "true" ]]; then
  update_repo 'sigstore/cosign' 'cosign_checksums.txt' 'COSIGN_VERSION' 'COSIGN_SHA' 'cosign-linux-amd64$'
  update_repo 'anchore/syft' 'checksums.txt' 'SYFT_VERSION' 'SYFT_SHA' 'linux_amd64.tar.gz$'
  update_repo 'goreleaser/goreleaser' 'checksums.txt' 'GORELEASER_VERSION' 'GORELEASER_SHA' 'Linux_x86_64.tar.gz$'
  update_repo 'ko-build/ko' 'checksums.txt' 'KO_VERSION' 'KO_SHA' 'ko_Linux_x86_64.tar.gz$'
  update_repo 'git-chglog/git-chglog' 'checksums.txt' 'GIT_CHGLOG_VERSION' 'GIT_CHGLOG_SHA' 'linux_amd64.tar.gz$'
  update_repo 'docker/buildx' 'checksums.txt' 'BUILDX_VERSION' 'BUILDX_SHA' 'linux-amd64$'
  update_repo 'buildpacks/pack' 'linux.tgz.sha256' 'PACK_VERSION' 'PACK_SHA'
else
  echo "golang unchanged, skip tool updates"
fi

# machine-readable versions for CI (consumed by .github/workflows/auto-release-go.yml)
echo "##VERSIONS##"
cat "${VERSIONS_ENV}"

# clean tmp files
rm -rf ${TMP_DIR}

popd || exit
