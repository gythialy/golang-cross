# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Forked from https://github.com/gythialy/golang-cross. 

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo. Upstream had some optimisations for updating just go and goreleaser that is dispensed with inthis repo. 

This image is carefully tuned for go 1.15. Buster has glibc 2.28 and this is too new for many distros which are currently supported. So we use 1.15 based on stretch which needs version 1000.10.18 of https://github.com/tpoechtrager/apple-libtapi.

`Dockerfile.tapi` is checked in that can make the process of finding the correct apple-libtapi version.

## Automation

[release.yml](.github/workflows/release.yml) matrix builds images based on the latest go 1.12 and 1.15. The images on Hub are tagged with the same version as the go version.
