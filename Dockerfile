FROM ghcr.io/gythialy/golang-cross-builder:v1.16.2

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

ARG GO_VERSION=1.16.5
ARG GOLANG_DIST_SHA=b12c23023b68de22f74c0524f10b753e7b08b1504cb7e417eccebdd3fae49061

# update golang
RUN \
	GOLANG_DIST=https://storage.googleapis.com/golang/go${GO_VERSION}.linux-amd64.tar.gz && \
	wget -O go.tgz "$GOLANG_DIST" && \
	echo "${GOLANG_DIST_SHA} *go.tgz" | sha256sum -c - && \
	rm -rf /usr/local/go && \
	tar -C /usr/local -xzf go.tgz && \
	rm go.tgz && \
	go version;

# install goreleaser
ARG GORELEASER_VERSION=0.169.0
ARG GORELEASER_SHA=f139fe6191da2209192f43c3a77220067f99c623c78096c2315cbe93facb5455
RUN  \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	wget ${GORELEASER_DOWNLOAD_URL}; \
	echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1; \
	tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser; \
	rm $GORELEASER_DOWNLOAD_FILE; \
	goreleaser -v;

# install git-chglog
ARG GIT_CHGLOG_VERSION=0.14.2
ARG GIT_CHGLOG_SHA=90a940f47ae6fedce5b5995f22dcae6159e54b86418e08a9a911705d36dbd52e
RUN \
	GIT_CHGLOG_DOWNLOAD_FILE=git-chglog_linux_amd64.tar.gz && \
	GIT_CHGLOG_DOWNLOAD_URL=https://github.com/git-chglog/git-chglog/releases/download/v${GIT_CHGLOG_VERSION}/git-chglog_${GIT_CHGLOG_VERSION}_linux_amd64.tar.gz && \
	wget -O ${GIT_CHGLOG_DOWNLOAD_FILE} ${GIT_CHGLOG_DOWNLOAD_URL}; \
	echo "$GIT_CHGLOG_SHA $GIT_CHGLOG_DOWNLOAD_FILE" | sha256sum -c - || exit 1; \
	tar -xzf $GIT_CHGLOG_DOWNLOAD_FILE -C /usr/bin/ git-chglog; \
	rm $GIT_CHGLOG_DOWNLOAD_FILE; \
	git-chglog -v; \
	chmod +x /entrypoint.sh

ENTRYPOINT ["bash", "/entrypoint.sh"]

# CMD ["goreleaser", "-v"]
