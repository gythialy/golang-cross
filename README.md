# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo.

## Docker images

- Find it on GitHub packages

  - golang-cross
    ```
    docker pull ghcr.io/gythialy/golang-cross:latest
    ```
  - golang-cross-builder
    ```
    docker pull ghcr.io/gythialy/golang-cross-builder:v1.17.1
    ```

- Build your own images
  - Build base image (optional)
    ```
     docker build -f Dockerfile_builder -t ghcr.io/gythialy/golang-cross-builder:v1.17.1 .
    ```
    if running docker on M1 (arm64) macbook:
    ```
     docker build --platform linux/amd64 -f Dockerfile.builder -t ghcr.io/gythialy/golang-cross-builder:v1.18 .
    ```
    > Please follow the guide to [pack the SDK](https://github.com/tpoechtrager/osxcross#packaging-the-sdk) first
  - Build golang-cross image
    ```
    docker build --build-arg GO_VERSION=1.16.2 \
      --build-arg GOLANG_DIST_SHA=542e936b19542e62679766194364f45141fde55169db2d8d01046555ca9eb4b8 \
      --build-arg GORELEASER_VERSION=0.162.0 \
      --build-arg GORELEASER_SHA=4b7d2f1e59ead8047fcef795d66236ff6f8cfe7302c1ff8fb31bd360a3c6f32e \
      -f Dockerfile \
      -t ghcr.io/gythialy/golang-cross:latest .
    ```
    > The default arguments can be overridden with `--build-arg`
## How to use

- Prepare [GoReleaser](https://goreleaser.com/intro/) configuration

- Generate environment variable `PRIVATE_KEY` from the GPG private key (optional), if enable the [signing](https://goreleaser.com/customization/sign/) feature

  ```bash
  export PRIVATE_KEY=$(cat ~/private_key.gpg | base64)
  ```

- Run docker container to build the binaries

  ```bash
    export GO_BUILDER_VERSION=v1.17.1
    docker run --rm --privileged \
      -e PRIVATE_KEY=$(PRIVATE_KEY) \
      -v $(CURDIR):/golang-cross-example \
      -v /var/run/docker.sock:/var/run/docker.sock \
      -v $(GOPATH)/src:/go/src \
      -w /golang-cross-example \
      ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --snapshot --rm-dist
  ```

## Practical example

- [.goreleaser.yml](example/.goreleaser.yml)
- [Makefile](example/Makefile#L35-L42)

## Thanks

[![Jetbrains](assets/jetbrains-variant-3.svg)](https://www.jetbrains.com/?from=golang-cross)
