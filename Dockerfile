FROM goreng/golang-cross-builder:v1.15.1

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"

COPY entrypoint.sh /

ARG GOLANG_VERSION=1.15.6
ARG GOLANG_DIST_SHA=3918e6cc85e7eaaa6f859f1bdbaac772e7a825b0eb423c63d3ae68b21f84b844

# update golang
RUN \
	GOLANG_DIST=https://storage.googleapis.com/golang/go${GOLANG_VERSION}.linux-amd64.tar.gz && \
	wget -O go.tgz "$GOLANG_DIST"; \
	echo "${GOLANG_DIST_SHA} *go.tgz" | sha256sum -c -; \
	rm -rf /usr/local/go; \
	tar -C /usr/local -xzf go.tgz; \
	rm go.tgz; 

# install goreleaser
ARG GORELEASER_VERSION=0.149.0
ARG GORELEASER_SHA=a227362d734cda47f7ebed9762e6904edcd115a65084384ecfbad2baebc4c775
RUN  \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	wget ${GORELEASER_DOWNLOAD_URL}; \
			echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1; \
			tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser; \
			rm $GORELEASER_DOWNLOAD_FILE;

# install git-chglog
RUN go get -u github.com/git-chglog/git-chglog/cmd/git-chglog && \
	chmod +x /entrypoint.sh

ENTRYPOINT ["bash", "/entrypoint.sh"]

# CMD ["goreleaser", "-v"]
