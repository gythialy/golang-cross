# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo.

## Docker images

### Pre-built Images

- golang-cross
  ```
  docker pull ghcr.io/gythialy/golang-cross:latest
  ```
- golang-cross-builder
  ```
  docker pull ghcr.io/gythialy/golang-cross-builder:v1.22.0-0-bullseye
  docker pull ghcr.io/gythialy/golang-cross-builder:v1.17.1
  ```

### Build your own
- Build base image (optional)
  ```
  docker build -f Dockerfile_builder -t ghcr.io/gythialy/golang-cross-builder:v1.17.1 .
  # if running docker on M1 (arm64) macOS:
  docker build --platform linux/amd64 -f Dockerfile.builder -t ghcr.io/gythialy/golang-cross-builder:v1.18 .
  ```
  > Note: [Pack the SDK](https://github.com/tpoechtrager/osxcross#packaging-the-sdk) first or use [GitHub Action](https://github.com/gythialy/golang-cross/actions/workflows/osx-sdk.yaml)

- Build golang-cross image
  ```
  docker build --build-arg GO_VERSION=1.22.0 \
    --build-arg OS_CODENAME=bullseye \
    --build-arg GOLANG_DIST_SHA=542e936b19542e62679766194364f45141fde55169db2d8d01046555ca9eb4b8 \
    --build-arg GORELEASER_VERSION=1.24.0 \
    --build-arg GORELEASER_SHA=4b7d2f1e59ead8047fcef795d66236ff6f8cfe7302c1ff8fb31bd360a3c6f32e \
    -f Dockerfile \
    -t ghcr.io/gythialy/golang-cross:latest .
  ```
  >  Override default arguments with `--build-arg`

## Usage

- Prepare [GoReleaser](https://goreleaser.com/intro/) configuration

- Set up GPG signing (optional), if enable the [signing](https://goreleaser.com/customization/sign/) feature

  ```bash
  export PRIVATE_KEY=$(cat ~/private_key.gpg | base64)
  ```

- Build the binaries:
  ```bash
  export GO_BUILDER_VERSION=v1.17.1;
  docker run --rm --privileged \
    -e PRIVATE_KEY=$(PRIVATE_KEY) \
    -v $(CURDIR):/golang-cross-example \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(GOPATH)/src:/go/src \
    -w /golang-cross-example \
    ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --snapshot --rm-dist
  ```

## Examples

- [.goreleaser.yml](example/.goreleaser.yml)
- [Makefile](example/Makefile#L35-L42)

## Alternative projects

- [goreleaser/goreleaser-cross](https://github.com/goreleaser/goreleaser-cross)
