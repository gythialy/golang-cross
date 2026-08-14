ARG OS_CODENAME=bookworm

FROM ghcr.io/gythialy/golang-cross-builder:v1.26.6-0-${OS_CODENAME:-trixie}

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source=https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# ============================================================
# Tool versions - managed by scripts/check-update.sh
# ============================================================
ARG COSIGN_VERSION=v3.1.3
ARG COSIGN_SHA=4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71
ARG SYFT_VERSION=v1.51.0
ARG SYFT_SHA=2a2e837a2c8d59ec9af5472ee22d3b04ee463c4e44476ecf993fd1e5ab6ebc7f
ARG GO_VERSION=go1.26.6
ARG GOLANG_DIST_SHA=708effb774be8237570d0add163225abbdfaf4fca28b2611df167beba4feef89
ARG GORELEASER_VERSION=v2.17.1
ARG GORELEASER_SHA=a99bbc7ae0d8d897b07c4c497a9b62f222558804715ef219d1af05a7e417bc80
ARG KO_VERSION=v0.19.1
ARG KO_SHA=635ac6ea3fd376c935fee597fbb29ab2c2449f49ef1655085fe3aa9c25fed7a5
ARG GIT_CHGLOG_VERSION=v0.15.4
ARG GIT_CHGLOG_SHA=03cbeedbd1317289295e75016fa0acd26baeb2fc7810ed287361dd9bd8bc33a8
ARG DOCKER_CLI_VERSION=29.5.1
ARG BUILDX_VERSION=v0.36.1
ARG BUILDX_SHA=48af8a397ebd60178778bf63611dbcebe5f5e7a9be90eb9147b24b9587455778
ARG PACK_VERSION=v0.40.9
ARG PACK_SHA=dc0ee1e931cf8a106d7555a01a214864f9acb60b77adf15d69b74df4404758e9
ARG GOIMPORTS_VERSION=v0.49.0

# Download all tools in parallel (network-bound), verify checksums, then install.
# Parallel downloads cut the wall-clock time vs the old serial wget loop.
# wait with explicit pids so a failed background download fails the build.
RUN set -eux; \
    mkdir -p /tmp/dl && cd /tmp/dl; \
    wget -qO cosign https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/cosign-linux-amd64 & p1=$!; \
    wget -qO syft.tar.gz https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/syft_${SYFT_VERSION#v}_linux_amd64.tar.gz & p2=$!; \
    wget -qO go.tgz https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz & p3=$!; \
    wget -qO goreleaser.tar.gz https://github.com/goreleaser/goreleaser/releases/download/${GORELEASER_VERSION}/goreleaser_Linux_x86_64.tar.gz & p4=$!; \
    wget -qO ko.tar.gz https://github.com/ko-build/ko/releases/download/${KO_VERSION}/ko_${KO_VERSION#v}_Linux_x86_64.tar.gz & p5=$!; \
    wget -qO git-chglog.tar.gz https://github.com/git-chglog/git-chglog/releases/download/${GIT_CHGLOG_VERSION}/git-chglog_${GIT_CHGLOG_VERSION#v}_linux_amd64.tar.gz & p6=$!; \
    curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz & p7=$!; \
    wget -qO buildx https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64 & p8=$!; \
    wget -qO pack.tgz https://github.com/buildpacks/pack/releases/download/${PACK_VERSION}/pack-${PACK_VERSION}-linux.tgz & p9=$!; \
    wait $p1 $p2 $p3 $p4 $p5 $p6 $p7 $p8 $p9; \
    echo "${COSIGN_SHA}  cosign" | sha256sum -c -; \
    echo "${SYFT_SHA}  syft.tar.gz" | sha256sum -c -; \
    echo "${GOLANG_DIST_SHA}  go.tgz" | sha256sum -c -; \
    echo "${GORELEASER_SHA}  goreleaser.tar.gz" | sha256sum -c -; \
    echo "${KO_SHA}  ko.tar.gz" | sha256sum -c -; \
    echo "${GIT_CHGLOG_SHA}  git-chglog.tar.gz" | sha256sum -c -; \
    echo "${BUILDX_SHA}  buildx" | sha256sum -c -; \
    echo "${PACK_SHA}  pack.tgz" | sha256sum -c -; \
    mv cosign /usr/local/bin/cosign && chmod +x /usr/local/bin/cosign; \
    tar -xzf syft.tar.gz -C /usr/bin/ syft; \
    rm -rf /usr/local/go && tar -C /usr/local -xzf go.tgz; \
    tar -xzf goreleaser.tar.gz -C /usr/bin/ goreleaser; \
    tar -xzf ko.tar.gz -C /usr/bin/ ko; \
    tar -xzf git-chglog.tar.gz -C /usr/bin/ git-chglog; \
    tar xzf docker-${DOCKER_CLI_VERSION}.tgz --strip 1 -C /usr/local/bin docker/docker; \
    chmod a+x buildx && mkdir -p ~/.docker/cli-plugins && mv buildx ~/.docker/cli-plugins/docker-buildx; \
    tar xzf pack.tgz -C /usr/local/bin pack --no-same-owner; \
    rm -rf /tmp/dl; \
    cd /; \
    cosign version && syft version && go version && goreleaser -v && ko version && git-chglog -v && docker -v && pack version

# install gcloud sdk (single apt cycle, https source, clean lists to slim the image)
RUN apt-get update -y && apt-get install -y -q --no-install-recommends apt-transport-https ca-certificates gnupg \
	&& curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
	&& echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
	&& apt-get update -y && apt-get install -y -q google-cloud-cli \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

# install goimports (pinned version so the layer cache hits across builds; drop the go build cache afterwards)
RUN go install golang.org/x/tools/cmd/goimports@${GOIMPORTS_VERSION} && go clean -cache

ENTRYPOINT ["bash", "/entrypoint.sh"]
