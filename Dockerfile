ARG OS_CODENAME=bookworm

FROM ghcr.io/gythialy/golang-cross-builder:v1.22.2-0-${OS_CODENAME:-bookworm}

LABEL maintainer="Goren G<gythialy.koo+github@gmail.com>"
LABEL org.opencontainers.image.source https://github.com/gythialy/golang-cross

COPY entrypoint.sh /

# install cosign
COPY --from=ghcr.io/sigstore/cosign/cosign:v2.2.3@sha256:8fc9cad121611e8479f65f79f2e5bea58949e8a87ffac2a42cb99cf0ff079ba7 /ko-app/cosign /usr/local/bin/cosign
# install syft
COPY --from=docker.io/anchore/syft:v0.102.0@sha256:fbbdb5f60a9db9400d49801bf70b19c29ac054b370dbccf538399918bbdf38a7 /syft /usr/local/bin/syft

ARG GO_VERSION=go1.22.3
ARG GOLANG_DIST_SHA=8920ea521bad8f6b7bc377b4824982e011c19af27df88a815e3586ea895f1b36
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
ARG GORELEASER_VERSION=v1.26.0
ARG GORELEASER_SHA=e3368a2209fb7ea3a253184ce64ed1251ed36a37ea4476c43582e9381de3dfc7
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
ARG KO_VERSION=v0.15.2
ARG KO_SHA=d11f03f23261d16f9e7802291e9d098e84f5daecc7931e8573bece9025b6a2c5
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
ARG BUILDX_VERSION=v0.14.0
ARG BUILDX_SHA=32f8f17eca35bf2efe6c0e47f40e4692a876f34531b421efc984799a5b41226e
RUN \
	BUILDX_DOWNLOAD_FILE=buildx-${BUILDX_VERSION}.linux-amd64 && \
	wget https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64 && \
	echo "${BUILDX_SHA} ${BUILDX_DOWNLOAD_FILE}" | sha256sum -c - || exit 1 && \
	chmod a+x buildx-${BUILDX_VERSION}.linux-amd64 && \
	mkdir -p ~/.docker/cli-plugins && \
	mv buildx-${BUILDX_VERSION}.linux-amd64 ~/.docker/cli-plugins/docker-buildx

# install Pack CLI
ARG PACK_VERSION=v0.33.2
ARG PACK_SHA=76eafc80fdf8caa3904be65acac7e6e1f674420555bac44cd0cb1cd1ac8b47e0
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
