ARG OS_CODENAME=bookworm

FROM ghcr.io/gythialy/golang-cross-builder:v1.26.5-0-${OS_CODENAME:-trixie}

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source=https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# install cosign
ARG COSIGN_VERSION=v3.1.1
ARG COSIGN_SHA=ae1ecd212663f3693ad9edf8b1a183900c9a52d3155ba6e354237f9a0f6463fc
RUN \
	COSIGN_DOWNLOAD_FILE=cosign-linux-amd64 && \
	wget -O $COSIGN_DOWNLOAD_FILE https://github.com/sigstore/cosign/releases/download/${COSIGN_VERSION}/${COSIGN_DOWNLOAD_FILE} && \
	echo "$COSIGN_SHA $COSIGN_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	mv $COSIGN_DOWNLOAD_FILE /usr/local/bin/cosign && \
	chmod +x /usr/local/bin/cosign && \
	cosign version

# install syft
ARG SYFT_VERSION=v1.46.0
ARG SYFT_SHA=d654f678b709eb53c393d38519d5ed7d2e57205529404018614cfefa0fb2b5ca
RUN  \
	SYFT_DOWNLOAD_FILE=syft_${SYFT_VERSION#v}_linux_amd64.tar.gz && \
	SYFT_DOWNLOAD_URL=https://github.com/anchore/syft/releases/download/${SYFT_VERSION}/${SYFT_DOWNLOAD_FILE} && \
	wget ${SYFT_DOWNLOAD_URL} && \
	echo "$SYFT_SHA $SYFT_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $SYFT_DOWNLOAD_FILE -C /usr/bin/ syft && \
	rm $SYFT_DOWNLOAD_FILE

ARG GO_VERSION=go1.26.5
ARG GOLANG_DIST_SHA=5c2c3b16caefa1d968a94c1daca04a7ca301a496d9b086e17ad77bb81393f053
# update golang
RUN \
	GOLANG_DIST=https://go.dev/dl/${GO_VERSION}.linux-amd64.tar.gz && \
	wget -O go.tgz "$GOLANG_DIST" && \
	echo "${GOLANG_DIST_SHA} *go.tgz" | sha256sum -c - && \
	rm -rf /usr/local/go && \
	tar -C /usr/local -xzf go.tgz && \
	rm go.tgz && \
	go version

# install goreleaser
ARG GORELEASER_VERSION=v2.17.0
ARG GORELEASER_SHA=dde10e2d5a13cef969c0eec00c74f359c0ac306d702b1bd291ad9337b4e54c1d
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
ARG KO_VERSION=v0.19.1
ARG KO_SHA=635ac6ea3fd376c935fee597fbb29ab2c2449f49ef1655085fe3aa9c25fed7a5
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
ARG DOCKER_CLI_VERSION=29.5.1
# ARG DOCKER_CLI_SHA=7ea11ecb100fdc085dbfd9ab1ff380e7f99733c890ed815510a5952e5d6dd7e0
RUN  \
	DOCKER_CLI_DOWNLOAD_FILE=docker-${DOCKER_CLI_VERSION}.tgz && \
	curl -fsSLO https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_CLI_VERSION}.tgz && \
	# echo "$DOCKER_CLI_SHA $DOCKER_CLI_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar xzvf ${DOCKER_CLI_DOWNLOAD_FILE} --strip 1 -C /usr/local/bin docker/docker && \
	rm ${DOCKER_CLI_DOWNLOAD_FILE} && \
	docker -v

# install Buildx
ARG BUILDX_VERSION=v0.35.0
ARG BUILDX_SHA=d41ece72044243b4f58b343441ae37446d9c29a7d6b5e11c61847bbcf8f7dfda
RUN \
	BUILDX_DOWNLOAD_FILE=buildx-${BUILDX_VERSION}.linux-amd64 && \
	wget https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64 && \
	echo "${BUILDX_SHA} ${BUILDX_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
	chmod a+x buildx-${BUILDX_VERSION}.linux-amd64 && \
	mkdir -p ~/.docker/cli-plugins && \
	mv buildx-${BUILDX_VERSION}.linux-amd64 ~/.docker/cli-plugins/docker-buildx

# install Pack CLI
ARG PACK_VERSION=v0.40.7
ARG PACK_SHA=0e458f37e177b6764f3ddcec542bd77bf18cd6f64f00525e0a4589bd7895d747
RUN \
	PACK_DOWNLOAD_FILE=pack-${PACK_VERSION}-linux.tgz && \
	wget https://github.com/buildpacks/pack/releases/download/${PACK_VERSION}/pack-${PACK_VERSION}-linux.tgz && \
	echo "${PACK_SHA} ${PACK_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
	tar xzvf ${PACK_DOWNLOAD_FILE} -C /usr/local/bin pack --no-same-owner  && \
	rm $PACK_DOWNLOAD_FILE

# install gcloud sdk
RUN apt-get update && apt-get install -y -q apt-transport-https ca-certificates gnupg \
	&& curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg \
	&& echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] http://packages.cloud.google.com/apt cloud-sdk main" | tee -a /etc/apt/sources.list.d/google-cloud-sdk.list \
	&& apt-get update -y && apt-get install google-cloud-cli -y \
	&& apt -y autoremove && apt-get clean

# install goimports
RUN go install golang.org/x/tools/cmd/goimports@latest

ENTRYPOINT ["bash", "/entrypoint.sh"]
