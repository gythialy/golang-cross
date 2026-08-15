# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo.

> **EOL notice**: Go 1.17 – 1.23 are end-of-life and no longer maintained.
> Their branches are archived under `archive/go-1.x` tags and remain
> available for reference but receive no updates. Supported versions:
> **Go 1.24+** (see `versions.json`).

## Docker images

### Pre-built Images

Two toolchains in one repo; `latest` points at the newest Go's **zig** image.

- `golang-cross` — zig toolchain (Go 1.25+, self-contained)
  ```
  docker pull ghcr.io/gythialy/golang-cross:latest            # = v1.26.6-0-trixie-zig
  docker pull ghcr.io/gythialy/golang-cross:1.26-zig
  docker pull ghcr.io/gythialy/golang-cross:v1.26.6-0-trixie-zig
  ```
- `golang-cross` — osxcross toolchain (Go 1.24 baseline)
  ```
  docker pull ghcr.io/gythialy/golang-cross:1.24
  docker pull ghcr.io/gythialy/golang-cross:v1.24.13-0-trixie
  ```
- `golang-cross-builder` — osxcross toolchain image (FROM base of the osxcross main image)
  ```
  docker pull ghcr.io/gythialy/golang-cross-builder:1.24
  docker pull ghcr.io/gythialy/golang-cross-builder:v1.24.13-0-trixie
  ```

### Build your own
- Build the shared tools base image (golang + cosign/syft/goreleaser/.../gcloud)
  ```
  docker build --platform linux/amd64 -f Dockerfile.tools \
    --build-arg GO_VERSION=1.26.6 --build-arg OS_CODENAME=trixie \
    -t ghcr.io/gythialy/golang-cross-tools:v1.26.6-0-trixie .
  ```

- Build the osxcross builder image (from the tools image)
  ```
  docker build --platform linux/amd64 -f Dockerfile.builder \
    --build-arg GO_VERSION=1.24.13 --build-arg OS_CODENAME=trixie \
    -t ghcr.io/gythialy/golang-cross-builder:v1.24.13-0-trixie .
  ```
  > Note: [Pack the SDK](https://github.com/tpoechtrager/osxcross#packaging-the-sdk) first or use [GitHub Action](https://github.com/gythialy/golang-cross/actions/workflows/osx-sdk.yaml)

- Build the zig image (from the tools image)
  ```
  docker build --platform linux/amd64 -f Dockerfile.zig \
    --build-arg GO_VERSION=1.26.6 --build-arg OS_CODENAME=trixie \
    -t ghcr.io/gythialy/golang-cross:v1.26.6-0-trixie-zig .
  ```

- Build golang-cross image (osxcross toolchain, from the builder image)
  ```
  docker build --build-arg BUILDER_TAG=v1.24.13-0 \
    --build-arg OS_CODENAME=trixie \
    -f Dockerfile \
    -t ghcr.io/gythialy/golang-cross:v1.24.13-0-trixie .
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

- [sqlite-example](example/sqlite-example) — go-sqlite3 cgo (osxcross: [.goreleaser.yml](example/sqlite-example/.goreleaser.yml), zig: [.goreleaser.zig.yml](example/sqlite-example/.goreleaser.zig.yml))
- [openssl-example](example/openssl-example) — OpenSSL EVP cgo via zig ([.goreleaser.zig-openssl.yml](example/openssl-example/.goreleaser.zig-openssl.yml))
- [Makefile](example/sqlite-example/Makefile#L35-L42)

Local smoke-test of a published image (also run in CI on release):

```sh
cd example/sqlite-example && make smoke-test IMAGE=ghcr.io/gythialy/golang-cross:v1.26.6-0-trixie-zig CONFIG=.goreleaser.zig.yml
cd example/openssl-example && make smoke-test IMAGE=ghcr.io/gythialy/golang-cross:v1.26.6-0-trixie-zig
```

## Alternative projects

- [goreleaser/goreleaser-cross](https://github.com/goreleaser/goreleaser-cross)
