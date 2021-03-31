FROM goreng/golang-cross-builder:v1.15.1

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"

COPY entrypoint.sh /

ARG GOLANG_VERSION=1.16.2
ARG GOLANG_DIST_SHA=542e936b19542e62679766194364f45141fde55169db2d8d01046555ca9eb4b8

# update golang
RUN \
	GOLANG_DIST=https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz && \
	wget -O go.tgz "$GOLANG_DIST"; \
	echo "${GOLANG_DIST_SHA} *go.tgz" | sha256sum -c -; \
	rm -rf /usr/local/go; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; 

# install goreleaser
ARG GORELEASER_VERSION=0.162.0
ARG GORELEASER_SHA=4b7d2f1e59ead8047fcef795d66236ff6f8cfe7302c1ff8fb31bd360a3c6f32e
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
