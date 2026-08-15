ARG OS_CODENAME=bookworm
ARG BUILDER_TAG=v1.24.13-0

FROM ghcr.io/gythialy/golang-cross-builder:${BUILDER_TAG}-${OS_CODENAME:-trixie}

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source=https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# The builder image already ships the cross toolchain (osxcross) AND the
# release tools (cosign/syft/goreleaser/.../gcloud) via the shared
# golang-cross-tools base, so the main image only adds the entrypoint.
ENTRYPOINT ["bash", "/entrypoint.sh"]
