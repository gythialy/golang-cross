FROM goreng/golang-cross-builder:v1.16.2

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"

COPY entrypoint.sh /

ARG GO_VERSION=1.16.3
ARG GOLANG_DIST_SHA=951a3c7c6ce4e56ad883f97d9db74d3d6d80d5fec77455c6ada6c1f7ac4776d2

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
ARG GORELEASER_VERSION=0.162.0
ARG GORELEASER_SHA=4b7d2f1e59ead8047fcef795d66236ff6f8cfe7302c1ff8fb31bd360a3c6f32e
RUN  \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	wget ${GORELEASER_DOWNLOAD_URL}; \
	echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1; \
	tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser; \
	rm $GORELEASER_DOWNLOAD_FILE; \
	goreleaser -v;

# install git-chglog
ARG GIT_CHGLOG_VERSION=0.14.1
ARG GIT_CHGLOG_SHA=da787394f042603f7baf95183ea3914ac9a840429f5fd5e51caa0ce8848966ce
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
