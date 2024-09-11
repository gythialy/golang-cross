ARG OS_CODENAME=bookworm

FROM ghcr.io/gythialy/golang-cross-builder:v1.23.1-0-${OS_CODENAME:-bookworm}

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# install cosign
ARG COSIGN_VERSION=v2.4.0
ARG COSIGN_SHA=cd7636b3586a3bdac2d9c8f3b421ed119edcb20499107887fd929211110e8418
RUN \
	COSIGN_DOWNLOAD_FILE=cosign-linux-amd64 && \
	wget -O $COSIGN_DOWNLOAD_FILE https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/${COSIGN_DOWNLOAD_FILE} && \
	echo "$COSIGN_SHA $COSIGN_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	mv $COSIGN_DOWNLOAD_FILE /usr/local/bin/cosign && \
	chmod +x /usr/local/bin/cosign && \
	cosign version

# install syft
ARG SYFT_VERSION=v1.12.2
ARG SYFT_SHA=a41c86cc51a15dbacdf431418b96ee051171b487fdddb7591f275b2d7a7ace1c
RUN  \
	SYFT_DOWNLOAD_FILE=syft_${SYFT_VERSION#v}_linux_amd64.tar.gz && \
	SYFT_DOWNLOAD_URL=https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/${SYFT_DOWNLOAD_FILE} && \
	wget ${SYFT_DOWNLOAD_URL} && \
	echo "$SYFT_SHA $SYFT_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $SYFT_DOWNLOAD_FILE -C /usr/bin/ syft && \
	rm $SYFT_DOWNLOAD_FILE

ARG GO_VERSION=go1.23.1
ARG GOLANG_DIST_SHA=49bbb517cfa9eee677e1e7897f7cf9cfdbcf49e05f61984a2789136de359f9bd
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
ARG GORELEASER_VERSION=v2.2.0
ARG GORELEASER_SHA=1bf8909fa556599f29045b0b015ee75f6aec789e92f17343cb136e45499da98a
# RUN \
# 		wget https://github.com/goreleaser/goreleaser/releases/download/$GORELEASER_VERSION/checksums.txt.pem && \
# 		cosign verify-blob --certificate checksums.txt.pem --signature https://github.com/goreleaser/goreleaser/releases/download/$GORELEASER_VERSION/checksums.txt.sig https://github.com/goreleaser/goreleaser/releases/download/$GORELEASER_VERSION/checksums.txt && \
# 		rm -rf checksums.txt.pem
RUN  \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	wget ${GORELEASER_DOWNLOAD_URL} && \
	echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser && \
	rm $GORELEASER_DOWNLOAD_FILE && \
	goreleaser -v

# install ko
ARG KO_VERSION=v0.16.0
ARG KO_SHA=aee2caeced511e60c6889a4cfaf9ebe28ec35acb49531b7a90b09e0a963bcff7
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
ARG DOCKER_CLI_VERSION=24.0.7
# ARG DOCKER_CLI_SHA=7ea11ecb100fdc085dbfd9ab1ff380e7f99733c890ed815510a5952e5d6dd7e0
RUN  \
	DOCKER_CLI_DOWNLOAD_FILE=docker-${DOCKER_CLI_VERSION}.tgz && \
	curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz && \
	# echo "$DOCKER_CLI_SHA $DOCKER_CLI_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar xzvf ${DOCKER_CLI_DOWNLOAD_FILE} --strip 1 -C /usr/local/bin docker/docker && \
	rm ${DOCKER_CLI_DOWNLOAD_FILE} && \
	docker -v

# install Buildx
ARG BUILDX_VERSION=v0.17.0
ARG BUILDX_SHA=6c65b3a80fd65312ed4949b76d10077c304ea013e78251a91cb0990562ee82a6
RUN \
	BUILDX_DOWNLOAD_FILE=buildx-${BUILDX_VERSION}.linux-amd64 && \
	wget https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64 && \
	echo "${BUILDX_SHA} ${BUILDX_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
	chmod a+x buildx-${BUILDX_VERSION}.linux-amd64 && \
	mkdir -p ~/.docker/cli-plugins && \
	mv buildx-${BUILDX_VERSION}.linux-amd64 ~/.docker/cli-plugins/docker-buildx

# install Pack CLI
ARG PACK_VERSION=v0.35.1
ARG PACK_SHA=2adfa09946e9fba221d656e45d5aa6ee44e62f382c0aff75ea7168c21d4d8f33
RUN \
	PACK_DOWNLOAD_FILE=pack-${PACK_VERSION}-linux.tgz && \
	wget https://github.com/buildpacks/pack/releases/download/${PACK_VERSION}/pack-${PACK_VERSION}-linux.tgz && \
	echo "${PACK_SHA} ${PACK_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
	tar xzvf ${PACK_DOWNLOAD_FILE} -C /usr/local/bin pack --no-same-owner  && \
	rm $PACK_DOWNLOAD_FILE

# install gcloud sdk
RUN apt-get update && apt-get install -y -q apt-transport-https ca-certificates gnupg \
	&& echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
	&& curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key --keyring /usr/share/keyrings/cloud.google.gpg  add - && apt-get update -y && apt-get install google-cloud-cli -y \
	&& apt -y autoremove && apt-get clean

# install goimports
RUN go install golang.org/x/tools/cmd/goimports@latest

ENTRYPOINT ["bash", "/entrypoint.sh"]
