#!/bin/bash

set -e

REPO_ROOT=$(git rev-parse --show-toplevel)
TMP_DIR=tmp
pushd "${REPO_ROOT}" || exit

DOCKERFILE=${1:-Dockerfile}

[[ -e "${TMP_DIR}" ]] || mkdir -p "${TMP_DIR}"

is_darwin() {
  case "$(uname -s)" in
  *darwin*) true ;;
  *Darwin*) true ;;
  *) false ;;
  esac
}

update_golang() {
  local golang_version_file=${TMP_DIR}/golang.json
  curl -fsSL "https://go.dev/dl/?mode=json" >"${golang_version_file}"

  local latest_go_version
  local latest_golang_dist_sha
  latest_go_version=$(jq <"${golang_version_file}" -r '[.[].files[] | select(.filename | contains("linux-amd64"))][0] | .version' | sed -e 's/[]\/$*.^[]/\\&/g')
  latest_golang_dist_sha=$(jq <"${golang_version_file}" -r '[.[].files[] | select(.filename | contains("linux-amd64"))][0] | .sha256')

  local go_version_old
  local golang_dist_sha_old
  go_version_old=$(sed -n 's/ARG GO_VERSION=\(.*\)/\1/p' "$DOCKERFILE")
  golang_dist_sha_old=$(sed -n 's/ARG GOLANG_DIST_SHA=\(.*\)/\1/p' "$DOCKERFILE")

  # check latest_go_version latest_golang_dist_sha go_version_old golang_dist_sha_old are set
  if [[ -z "$latest_go_version" || -z "$latest_golang_dist_sha" || -z "$go_version_old" || -z "$golang_dist_sha_old" ]]; then
    echo "invalid golang version or dist hash value"
    exit 1
  fi

  if is_darwin; then
    sed -i '' "s/ARG GO_VERSION=$go_version_old/ARG GO_VERSION=$latest_go_version/g" "$DOCKERFILE"
    sed -i '' "s/ARG GOLANG_DIST_SHA=$golang_dist_sha_old/ARG GOLANG_DIST_SHA=$latest_golang_dist_sha/g" "$DOCKERFILE"
  else
    sed -i "s/ARG GO_VERSION=$go_version_old/ARG GO_VERSION=$latest_go_version/g" "$DOCKERFILE"
    sed -i "s/ARG GOLANG_DIST_SHA=$golang_dist_sha_old/ARG GOLANG_DIST_SHA=$latest_golang_dist_sha/g" "$DOCKERFILE"
  fi

  echo -e "update golang from $go_version_old: $golang_dist_sha_old to ${latest_go_version}: ${latest_golang_dist_sha}"
}

update_repo() {
  local repo="$1"
  local file="$2"
  local version="$3"
  local hash="$4"
  local tmpfile=${TMP_DIR}/repo.json

  curl -fsSL https://api.github.com/repos/${repo}/releases/latest >"$tmpfile"

  if [[ ! -f "${tmpfile}" ]]; then
    echo "get release info failed!!!"
    exit 1
  fi

  latest_version=$(grep tag_name "${tmpfile}" | cut -d '"' -f 4)
  checksum_file=$(jq <"${tmpfile}" -r --arg name "${file}" '.assets[] | select(.name | endswith($name)).browser_download_url')

  if [[ "${checksum_file}" == *checksums.txt ]]; then
    local flag="$5"
    checksum=$(curl -fsSL "${checksum_file}" | grep -e "${flag}" | awk '{print $1}')
  else
    checksum=$(curl -fsSL "${checksum_file}" | cut -d ' ' -f 1)
  fi
  if is_darwin; then
    sed -i '' "s/ARG ${version}=\(.*\)/ARG ${version}=${latest_version}/g" "$DOCKERFILE"
    sed -i '' "s/ARG ${hash}=\(.*\)/ARG ${hash}=${checksum}/g" "$DOCKERFILE"
  else
    sed -i "s/ARG ${version}=\(.*\)/ARG ${version}=${latest_version}/g" "$DOCKERFILE"
    sed -i "s/ARG ${hash}=\(.*\)/ARG ${hash}=${checksum}/g" "$DOCKERFILE"
  fi

  echo "update ${repo}, ${latest_version}:${checksum}"
}

update_golang
update_repo 'sigstore/cosign' 'cosign_checksums.txt' 'COSIGN_VERSION' 'COSIGN_SHA' 'cosign-linux-amd64$'
update_repo 'anchore/syft' 'checksums.txt' 'SYFT_VERSION' 'SYFT_SHA' 'linux_amd64.tar.gz$'
update_repo 'goreleaser/goreleaser' 'checksums.txt' 'GORELEASER_VERSION' 'GORELEASER_SHA' 'Linux_x86_64.tar.gz$'
update_repo 'ko-build/ko' 'checksums.txt' 'KO_VERSION' 'KO_SHA' 'ko_Linux_x86_64.tar.gz$'
update_repo 'git-chglog/git-chglog' 'checksums.txt' 'GIT_CHGLOG_VERSION' 'GIT_CHGLOG_SHA' 'linux_amd64.tar.gz'
update_repo 'docker/buildx' 'checksums.txt' 'BUILDX_VERSION' 'BUILDX_SHA' 'linux-amd64$'
update_repo 'buildpacks/pack' 'linux.tgz.sha256' 'PACK_VERSION' 'PACK_SHA'

# clean tmp files
rm -rf ${TMP_DIR}

popd || exit
