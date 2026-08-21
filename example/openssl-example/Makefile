.PHONY: smoke-test clean

# Smoke-test: verify the zig-based toolchain (Dockerfile.zig) can build this
# project end-to-end with goreleaser inside the image (see smoke-test.sh).
#
# Usage:
#   make smoke-test IMAGE=golang-cross-zig-test:goreleaser
#   IMAGE defaults to ghcr.io/gythialy/golang-cross:latest-zig

IMAGE ?= ghcr.io/gythialy/golang-cross:latest-zig

smoke-test:
	./smoke-test.sh $(IMAGE)

clean:
	rm -rf dist
