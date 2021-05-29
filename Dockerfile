FROM docker.pkg.github.com/gythialy/golang-cross/golang-cross-builder:v1.16.2

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"

COPY entrypoint.sh /

ARG GO_VERSION=1.16.4
ARG GOLANG_DIST_SHA=7154e88f5a8047aad4b80ebace58a059e36e7e2e4eb3b383127a28c711b4ff59

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
ARG GORELEASER_VERSION=0.166.1
ARG GORELEASER_SHA=229d76cbb306225aa1af884692ad8e34315846c81a352ddc59d02afd8fbcf647
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
