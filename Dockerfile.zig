# EXPERIMENTAL: zig-based cross-compilation toolchain
#
# Goal: replace Dockerfile.builder (golang-cross-builder, 8.53GB) with
# golang official image + zig (single ~100MB binary) + macOS SDK.
# zig cc replaces: mingw-w64 (windows), musl-tools (linux static),
# crossbuild-essential-arm64/armhf (arm), and osxcross (darwin).
#
# Image size: ~8.5GB (current builder) -> ~2GB (this image).
#
# Usage:
#   docker build --platform linux/amd64 -f Dockerfile.zig -t ghcr.io/gythialy/golang-cross:zig-experimental .
#
# Notes / known limitations (verified 2026-08-14 with go-sqlite3 cgo):
#   - darwin targets require explicit -isysroot / -L / -F (zig does NOT
#     auto-attach the SDK); paths are exposed as OSX_SDK_PATH
#   - darwin linking requires -ldflags "-s -w" (skips dsymutil which is
#     not shipped here; goreleaser defaults to -s -w)
#   - zig target must be version-less ("x86_64-macos"); "x86_64-macos.13"
#     fails with InvalidOperatingSystemVersion on zig 0.16

# NOTE: GO_VERSION is WITHOUT the "go" prefix. It selects the shared
# golang-cross-tools base image tag (v<GO_VERSION>-0-<OS_CODENAME>).
ARG GO_VERSION=1.26.6
ARG OS_CODENAME=trixie
ARG OSK_SDK=macos-13

FROM ghcr.io/gythialy/osx-sdk:${OSK_SDK:-macos-13} AS osx-sdk

# The release tools (cosign/syft/goreleaser/.../gcloud) come from the shared
# golang-cross-tools base; this image only adds zig + the macOS SDK.
FROM ghcr.io/gythialy/golang-cross-tools:v${GO_VERSION}-0-${OS_CODENAME:-trixie}

# Re-declare ARG after FROM to make it available in this stage
ARG OS_CODENAME=trixie
ARG ZIG_VERSION=0.16.0

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source=https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# install zig (single binary, replaces mingw-w64 + musl-tools + arm cross toolchains + osxcross)
RUN \
	apt-get update && apt-get install -y --no-install-recommends xz-utils ca-certificates wget && \
	rm -rf /var/lib/apt/lists/* && \
	ZIG_DOWNLOAD_FILE=zig-x86_64-linux-${ZIG_VERSION}.tar.xz && \
	wget -q https://ziglang.org/download/${ZIG_VERSION}/${ZIG_DOWNLOAD_FILE} && \
	tar -xf ${ZIG_DOWNLOAD_FILE} -C /opt && \
	ln -s /opt/zig-x86_64-linux-${ZIG_VERSION}/zig /usr/local/bin/zig && \
	rm ${ZIG_DOWNLOAD_FILE} && \
	zig version

# install macOS SDK (same SDK tarball used by osxcross; required for darwin cgo targets)
# The SDK name is NOT hardcoded: whatever the pinned osx-sdk:<OSK_SDK> image ships
# (e.g. macos-13 -> MacOSX14.sdk.tar.xz, v13 -> MacOSX13.sdk.tar.xz) is unpacked
# and normalized to a fixed path exposed via OSX_SDK_PATH (used as -isysroot).
COPY --from=osx-sdk /osxcross/tarballs/ /tmp/sdk-tarballs/
RUN set -eux; \
	mkdir -p /osxcross; \
	tar -xf /tmp/sdk-tarballs/*.sdk.tar.xz -C /osxcross; \
	rm -rf /tmp/sdk-tarballs; \
	mv /osxcross/*.sdk /osxcross/MacOSX.sdk

ENV OSX_SDK_PATH=/osxcross/MacOSX.sdk

ENTRYPOINT ["bash", "/entrypoint.sh"]
