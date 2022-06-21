FROM ghcr.io/gythialy/golang-cross-builder:v1.17.11-0

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# install cosign
COPY --from=gcr.io/projectsigstore/cosign:v1.9.0@sha256:ef2d14e16dbb7786d8713e4898a8512e69ace4105f5b371a9c115ffcc3e85d84 /ko-app/cosign /usr/local/bin/cosign
# install syft
COPY --from=docker.io/anchore/syft:v0.48.1@sha256:78421757823e55a1dd6f4c1e00f9754b41f714e3b2f2cd8aed04279fa84e75c7 /syft /usr/local/bin/syft

ARG GO_VERSION=1.17.11
ARG GOLANG_DIST_SHA=d69a4fe2694f795d8e525c72b497ededc209cb7185f4c3b62d7a98dd6227b3fe
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
ARG GORELEASER_VERSION=1.9.2
ARG GORELEASER_SHA=6089679e325a4cfc1d1374710dca99cd6f1f5ae4f351ceffa460d599432963d7
RUN  \
	wget https://github.com/goreleaser/goreleaser/releases/download/v$GORELEASER_VERSION/checksums.txt.pem && \
	GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	cosign verify-blob --cert checksums.txt.pem \
	--signature https://github.com/goreleaser/goreleaser/releases/download/v$GORELEASER_VERSION/checksums.txt.sig \
	https://github.com/goreleaser/goreleaser/releases/download/v$GORELEASER_VERSION/checksums.txt && \
	wget ${GORELEASER_DOWNLOAD_URL} && \
	echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser && \
	rm $GORELEASER_DOWNLOAD_FILE && \
	rm checksums.txt.pem && \
	goreleaser -v

# install ko
ARG KO_VERSION=0.11.2
ARG KO_SHA=afb5dacb44bfeafdc53c6de03d9ff74f4a6003c5617381d3139038aa25f3fb66
RUN  \
	KO_DOWNLOAD_FILE=ko_${KO_VERSION}_Linux_x86_64.tar.gz && \
	KO_DOWNLOAD_URL=https://github.com/google/ko/releases/download/v${KO_VERSION}/${KO_DOWNLOAD_FILE} && \
	wget ${KO_DOWNLOAD_URL} && \
	echo "$KO_SHA $KO_DOWNLOAD_FILE" | sha256sum -c - || exit 1 && \
	tar -xzf $KO_DOWNLOAD_FILE -C /usr/bin/ ko && \
	rm $KO_DOWNLOAD_FILE && \
	ko version

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
ARG BUILDX_VERSION=0.8.2
ARG BUILDX_SHA=c64de4f3c30f7a73ff9db637660c7aa0f00234368105b0a09fa8e24eebe910c3
RUN \
    BUILDX_DOWNLOAD_FILE=buildx-v${BUILDX_VERSION}.linux-amd64 && \
    wget https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-amd64 && \
    echo "${BUILDX_SHA} ${BUILDX_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
    chmod a+x buildx-v${BUILDX_VERSION}.linux-amd64 && \
    mkdir -p ~/.docker/cli-plugins && \
    mv buildx-v${BUILDX_VERSION}.linux-amd64 ~/.docker/cli-plugins/docker-buildx

# install Pack CLI
ARG PACK_VERSION=0.21.0-rc1
ARG PACK_SHA=2a70e946f7a86d96e72292fc1a2209972d0fa7901d758a1a3fc3d4d272e78efe
RUN \
    PACK_DOWNLOAD_FILE=pack-v${PACK_VERSION}-linux.tgz && \
    wget https://github.com/buildpacks/pack/releases/download/v${PACK_VERSION}/pack-v${PACK_VERSION}-linux.tgz && \
    echo "${PACK_SHA} ${PACK_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
    tar xzvf ${PACK_DOWNLOAD_FILE} -C /usr/local/bin pack --no-same-owner  && \
	rm $PACK_DOWNLOAD_FILE


# install Kustomize
ARG KUSTOMIZE_VERSION=4.5.4
ARG KUSTOMIZE_SHA=1159c5c17c964257123b10e7d8864e9fe7f9a580d4124a388e746e4003added3
RUN \
	KUSTOMIZE_DOWNLOAD_FILE=kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz && \
	wget https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}/${KUSTOMIZE_DOWNLOAD_FILE} && \
	echo "${KUSTOMIZE_SHA} ${KUSTOMIZE_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
	tar xzvf ${KUSTOMIZE_DOWNLOAD_FILE} -C /usr/local/bin kustomize && \
	rm $KUSTOMIZE_DOWNLOAD_FILE && \
	kustomize version

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
