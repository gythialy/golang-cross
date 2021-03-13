FROM goreng/golang-cross-builder:v1.15.1

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"

COPY entrypoint.sh /

ARG GO_VERSION=1.16
ARG GOLANG_DIST_SHA=013a489ebb3e24ef3d915abe5b94c3286c070dfe0818d5bca8108f1d6e8440d2

# update golang
RUN \
	GOLANG_DIST=https://storage.googleapis.com/golang/go${GO_VERSION}.linux-amd64.tar.gz && \
	wget -O go.tgz "$GOLANG_DIST"; \
	echo "${GOLANG_DIST_SHA} *go.tgz" | sha256sum -c -; \
	rm -rf /usr/local/go; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; \
	go version;

# install goreleaser
ARG GORELEASER_VERSION=0.156.2
ARG GORELEASER_SHA=875371b95da87218e4f06f084f5c5da72fde87013790132b41b1243f33e65745
RUN  \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	wget ${GORELEASER_DOWNLOAD_URL}; \
			echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1; \
			tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser; \
			rm $GORELEASER_DOWNLOAD_FILE;

# install git-chglog
ARG GIT_CHGLOG_VERSION=0.10.0
RUN \
	GIT_CHGLOG_DOWNLOAD_FILE=git-chglog_linux_amd64.tar.gz && \
	GIT_CHGLOG_DOWNLOAD_URL=https://github.com/git-chglog/git-chglog/releases/download/v${GIT_CHGLOG_VERSION}/git-chglog_${GIT_CHGLOG_VERSION}_linux_amd64.tar.gz &&\
	wget -O ${GIT_CHGLOG_DOWNLOAD_FILE} ${GIT_CHGLOG_DOWNLOAD_URL}; \
	tar -xzf $GIT_CHGLOG_DOWNLOAD_FILE -C /usr/bin/ git-chglog; \
	rm $GIT_CHGLOG_DOWNLOAD_FILE && \
	chmod +x /entrypoint.sh

ENTRYPOINT ["bash", "/entrypoint.sh"]

# CMD ["goreleaser", "-v"]
