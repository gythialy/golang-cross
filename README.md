# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Forked from https://github.com/gythialy/golang-cross. 

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo. Upstream had some optimisations for updating just go and goreleaser that is dispensed with inthis repo. 

## Automation

[release.yml](.github/workflows/release.yml) matrix builds images based on the latest go 1.12 and 1.15. The images on Hub are tagged with the same version as the go version.
