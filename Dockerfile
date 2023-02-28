FROM ghcr.io/gythialy/golang-cross-builder:v1.20.1-0

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# install cosign
COPY --from=gcr.io/projectsigstore/cosign:v2.0.0@sha256:728944a9542a7235b4358c4ab2bcea855840e9d4b9594febca5c2207f5da7f38 /ko-app/cosign /usr/local/bin/cosign
# install syft
COPY --from=docker.io/anchore/syft:v0.73.0@sha256:6a13beb5cc8eedb2a42a5b91a69a36105880a2a1fdba75cc8c4dbcd61a0eed2b /syft /usr/local/bin/syft

ARG GO_VERSION=go1.20.1
ARG GOLANG_DIST_SHA=000a5b1fca4f75895f78befeb2eecf10bfff3c428597f3f1e69133b63b911b02
# update golang
RUN \
	GOLANG_DIST=https://storage.googleapis.com/golang/${GO_VERSION}.linux-amd64.tar.gz && \
	wget -O go.tgz "$GOLANG_DIST" && \
	echo "${GOLANG_DIST_SHA} *go.tgz" | sha256sum -c - && \
	rm -rf /usr/local/go && \
	tar -C /usr/local -xzf go.tgz && \
	rm go.tgz && \
	go version

# install goreleaser
ARG GORELEASER_VERSION=v1.15.2
ARG GORELEASER_SHA=1730c4455756d80725c36752e76a0e200ab26a8a62b6cdaabff002573c382aa9
RUN  \
	wget https://github.com/goreleaser/goreleaser/releases/download/$GORELEASER_VERSION/checksums.txt.pem && \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	# COSIGN_EXPERIMENTAL=1 cosign verify-blob --cert checksums.txt.pem \
	# --signature https://github.com/goreleaser/goreleaser/releases/download/$GORELEASER_VERSION/checksums.txt.sig \
	# https://github.com/goreleaser/goreleaser/releases/download/$GORELEASER_VERSION/checksums.txt && \
	wget ${GORELEASER_DOWNLOAD_URL} && \
	echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser && \
	rm $GORELEASER_DOWNLOAD_FILE && \
	# rm checksums.txt.pem && \
	goreleaser -v

# install ko
ARG KO_VERSION=v0.12.0
ARG KO_SHA=05aa77182fa7c55386bd2a210fd41298542726f33bbfc9c549add3a66f7b90ad
RUN  \
	KO_DOWNLOAD_FILE=ko_${KO_VERSION#v}_Linux_x86_64.tar.gz && \
	KO_DOWNLOAD_URL=https://github.com/ko-build/ko/releases/download/${KO_VERSION}/${KO_DOWNLOAD_FILE} && \
	wget ${KO_DOWNLOAD_URL} && \
	echo "$KO_SHA $KO_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $KO_DOWNLOAD_FILE -C /usr/bin/ ko && \
	rm $KO_DOWNLOAD_FILE && \
	ko version

# install git-chglog
ARG GIT_CHGLOG_VERSION=v0.15.4
ARG GIT_CHGLOG_SHA=03cbeedbd1317289295e75016fa0acd26baeb2fc7810ed287361dd9bd8bc33a8
RUN \
	GIT_CHGLOG_DOWNLOAD_FILE=git-chglog_linux_amd64.tar.gz && \
	GIT_CHGLOG_DOWNLOAD_URL=https://github.com/git-chglog/git-chglog/releases/download/${GIT_CHGLOG_VERSION}/git-chglog_${GIT_CHGLOG_VERSION#v}_linux_amd64.tar.gz && \
	wget -O ${GIT_CHGLOG_DOWNLOAD_FILE} ${GIT_CHGLOG_DOWNLOAD_URL} && \
	echo "$GIT_CHGLOG_SHA $GIT_CHGLOG_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $GIT_CHGLOG_DOWNLOAD_FILE -C /usr/bin/ git-chglog && \
	rm $GIT_CHGLOG_DOWNLOAD_FILE && \
	git-chglog -v && \
	chmod +x /entrypoint.sh

# install Docker CLI
# docker no longer provides checksum
ARG DOCKER_CLI_VERSION=23.0.1
# ARG DOCKER_CLI_SHA=7ea11ecb100fdc085dbfd9ab1ff380e7f99733c890ed815510a5952e5d6dd7e0
RUN  \
    DOCKER_CLI_DOWNLOAD_FILE=docker-${DOCKER_CLI_VERSION}.tgz && \
    curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz && \
    # echo "$DOCKER_CLI_SHA $DOCKER_CLI_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
    tar xzvf ${DOCKER_CLI_DOWNLOAD_FILE} --strip 1 -C /usr/local/bin docker/docker && \
    rm ${DOCKER_CLI_DOWNLOAD_FILE} && \
    docker -v

# install Buildx
ARG BUILDX_VERSION=v0.10.3
ARG BUILDX_SHA=91f260c9879f8dc8b78912409f8d9f16a3429d457dbcfa0a67169f74837a9290
RUN \
    BUILDX_DOWNLOAD_FILE=buildx-${BUILDX_VERSION}.linux-amd64 && \
    wget https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64 && \
    echo "${BUILDX_SHA} ${BUILDX_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
    chmod a+x buildx-${BUILDX_VERSION}.linux-amd64 && \
    mkdir -p ~/.docker/cli-plugins && \
    mv buildx-${BUILDX_VERSION}.linux-amd64 ~/.docker/cli-plugins/docker-buildx

# install Pack CLI
ARG PACK_VERSION=v0.28.0
ARG PACK_SHA=4f51b82dea355cffc62b7588a2dfa461e26621dda3821034830702e5cae6f587
RUN \
    PACK_DOWNLOAD_FILE=pack-${PACK_VERSION}-linux.tgz && \
    wget https://github.com/buildpacks/pack/releases/download/${PACK_VERSION}/pack-${PACK_VERSION}-linux.tgz && \
    echo "${PACK_SHA} ${PACK_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
    tar xzvf ${PACK_DOWNLOAD_FILE} -C /usr/local/bin pack --no-same-owner  && \
	rm $PACK_DOWNLOAD_FILE


# install gcloud sdk
ENV PATH=/google-cloud-sdk/bin:${PATH} \
	CLOUDSDK_CORE_DISABLE_PROMPTS=1

RUN curl -O https://dl.google.com/dl/cloudsdk/channels/rapid/google-cloud-sdk.tar.gz && \
	tar xzf google-cloud-sdk.tar.gz -C / && \
	rm google-cloud-sdk.tar.gz && \
	/google-cloud-sdk/install.sh \
	--disable-installation-options \
	--bash-completion=false \
	--path-update=false \
	--usage-reporting=false && \
	gcloud info > /root/gcloud-info.txt

# install goimports
RUN go install golang.org/x/tools/cmd/goimports@latest

ENTRYPOINT ["bash", "/entrypoint.sh"]
