FROM ghcr.io/gythialy/golang-cross-builder:v1.16.2

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

ARG GO_VERSION=1.17
ARG GOLANG_DIST_SHA=6bf89fc4f5ad763871cf7eac80a2d594492de7a818303283f1366a7f6a30372d

# update golang
RUN \
	GOLANG_DIST=https://storage.googleapis.com/golang/go${GO_VERSION}.linux-amd64.tar.gz && \
	wget -O go.tgz "$GOLANG_DIST" && \
	echo "${GOLANG_DIST_SHA} *go.tgz" | sha256sum -c - && \
	rm -rf /usr/local/go && \
	tar -C /usr/local -xzf go.tgz && \
	rm go.tgz && \
	go version

# install goreleaser
ARG GORELEASER_VERSION=0.177.0
ARG GORELEASER_SHA=8dd5fff1d04eff3789d200920bf280391f96fd5cc1565dd0d6e0db2b9a710854
RUN  \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	wget ${GORELEASER_DOWNLOAD_URL} && \
	echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser && \
	rm $GORELEASER_DOWNLOAD_FILE && \
	goreleaser -v

# install git-chglog
ARG GIT_CHGLOG_VERSION=0.14.2
ARG GIT_CHGLOG_SHA=90a940f47ae6fedce5b5995f22dcae6159e54b86418e08a9a911705d36dbd52e
RUN \
	GIT_CHGLOG_DOWNLOAD_FILE=git-chglog_linux_amd64.tar.gz && \
	GIT_CHGLOG_DOWNLOAD_URL=https://github.com/git-chglog/git-chglog/releases/download/v${GIT_CHGLOG_VERSION}/git-chglog_${GIT_CHGLOG_VERSION}_linux_amd64.tar.gz && \
	wget -O ${GIT_CHGLOG_DOWNLOAD_FILE} ${GIT_CHGLOG_DOWNLOAD_URL} && \
	echo "$GIT_CHGLOG_SHA $GIT_CHGLOG_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $GIT_CHGLOG_DOWNLOAD_FILE -C /usr/bin/ git-chglog && \
	rm $GIT_CHGLOG_DOWNLOAD_FILE && \
	git-chglog -v && \
	chmod +x /entrypoint.sh

# install Docker CLI
ARG DOCKER_CLI_VERSION=20.10.8
ARG DOCKER_CLI_SHA=7ea11ecb100fdc085dbfd9ab1ff380e7f99733c890ed815510a5952e5d6dd7e0
RUN  \
    DOCKER_CLI_DOWNLOAD_FILE=docker-${DOCKER_CLI_VERSION}.tgz && \
    curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz && \
    echo "$DOCKER_CLI_SHA $DOCKER_CLI_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
    tar xzvf docker-${DOCKER_CLI_VERSION}.tgz --strip 1 -C /usr/local/bin docker/docker && \
    rm docker-${DOCKER_CLI_VERSION}.tgz && \
    docker -v

# install Buildx
ARG BUILDX_VERSION=0.6.2
ARG BUILDX_SHA=c2b374eb2f9cb71d6968059623d4ec3b53aa5873fce24595ff23c061c21d5384
RUN \
    BUILDX_DOWNLOAD_FILE=buildx-v${BUILDX_VERSION}.linux-amd64 && \
    wget https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64 && \
    echo "${BUILDX_SHA} ${BUILDX_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
    chmod a+x buildx-v${BUILDX_VERSION}.linux-amd64 && \
    mkdir -p ~/.docker/cli-plugins && \
    mv buildx-v${BUILDX_VERSION}.linux-amd64 ~/.docker/cli-plugins/docker-buildx

ENTRYPOINT ["bash", "/entrypoint.sh"]

# CMD ["goreleaser", "-v"]
