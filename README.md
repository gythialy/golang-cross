# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo.

## Docker images

- Find it on docker hub

  - [golang-cross](https://hub.docker.com/r/goreng/golang-cross)
    ```
    docker pull goreng/golang-cross
    ```
  - [golang-cross-builder](https://hub.docker.com/r/goreng/golang-cross-builder)
    ```
    docker pull goreng/golang-cross-builder
    ```

- Build your own images
  - Build base image (optional)
    ```
     docker build -f Dockerfile_builder -t goreng/golang-cross-builder:1.15.1 .
    ```
    > Please follow the guide to [pack the SDK](https://github.com/tpoechtrager/osxcross#packaging-the-sdk) first
  - Build golang-cross image
    ```
    docker build --build-arg GOLANG_VERSION=1.15.6 --build-arg GOLANG_DIST_SHA=3918e6cc85e7eaaa6f859f1bdbaac772e7a825b0eb423c63d3ae68b21f84b844 --build-arg GORELEASER_VERSION=0.149.0 --build-arg GORELEASER_SHA=a227362d734cda47f7ebed9762e6904edcd115a65084384ecfbad2baebc4c775 -f Dockerfile -t goreng/golang-cross .
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
  docker run --rm --privileged \
    -e PRIVATE_KEY=${PRIVATE_KEY} \
    -v $PWD:/go/src/github.com/qlcchain/go-qlc \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -w /go/src/github.com/qlcchain/go-qlc \
    goreng/golang-cross:latest --snapshot --rm-dist
  ```

## Practical Examples

- [.goreleaser.yml](https://github.com/qlcchain/go-qlc/blob/master/.goreleaser.yml)
- [Makefile](https://github.com/qlcchain/go-qlc/blob/master/Makefile#L50-L67)

## Thanks

[![Jetbrains](assets/jetbrains-variant-3.svg)](https://www.jetbrains.com/?from=golang-cross)
