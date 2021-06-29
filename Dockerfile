# Tested for arm64 osx (sdk ver below) amd64 
ARG GO_VERSION=1.15.13

# OS-X SDK parameters
ARG OSX_SDK=MacOSX10.15.sdk
ARG OSX_SDK_SUM=aee7b132a4b10cc26ab9904706412fd0907f5b8b660251e465647d8763f9f009

# osxcross parameters
ARG OSX_VERSION_MIN=10.12
ARG OSX_CROSS_COMMIT=c2ad5e859d12

FROM golang:${GO_VERSION}-stretch AS base

ARG APT_MIRROR
RUN sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
 && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list
ENV OSX_CROSS_PATH=/osxcross

FROM base AS osx-sdk
ARG OSX_SDK
ARG OSX_SDK_SUM

COPY ${OSX_SDK}.tar.xz "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz"
RUN echo "${OSX_SDK_SUM}"  "${OSX_CROSS_PATH}/tarballs/${OSX_SDK}.tar.xz" | sha256sum -c -

FROM base AS osx-cross-base
ARG DEBIAN_FRONTEND=noninteractive
# Install deps
RUN set -x; echo "Starting image build for $(grep PRETTY_NAME /etc/os-release)" \
 && dpkg --add-architecture arm64                      \
 && apt-get update                                     \
 && apt-get dist-upgrade -y -q                         \
        autoconf                                       \
        automake                                       \
        autotools-dev                                  \
        bc                                             \
        binfmt-support                                 \
        binutils-multiarch                             \
        binutils-multiarch-dev                         \
        build-essential                                \
        clang                                          \
        crossbuild-essential-arm64                     \
        curl                                           \
        git-core                                       \
        libtool                                        \
        multistrap                                     \
        patch                                          \
        wget                                           \
        xz-utils                                       \
        lsb-release                                    \
        cmake                                          \
        apt-transport-https                            \
        qemu-user-static                               \
        libxml2-dev                                    \
        lzma-dev                                       \
        openssl                                        \
	libssl-dev                                     \
	unzip                                          \
	sudo                                           \
	jq                                             \
&& apt -y autoremove                                   \
&& apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# FIXME: install gcc-multilib

FROM osx-cross-base AS osx-cross
ARG OSX_CROSS_COMMIT
WORKDIR "${OSX_CROSS_PATH}"
# install osxcross:
RUN git clone https://github.com/tpoechtrager/osxcross.git . \
 && git checkout -q "${OSX_CROSS_COMMIT}" \
 && rm -rf ./.git
COPY --from=osx-sdk "${OSX_CROSS_PATH}/." "${OSX_CROSS_PATH}/"
ARG OSX_VERSION_MIN
RUN UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN} ./build.sh

FROM osx-cross-base AS final
LABEL maintainer="Alok G Singh <alephnull@gmail.com>"
ARG DEBIAN_FRONTEND=noninteractive

COPY --from=osx-cross "${OSX_CROSS_PATH}/." "${OSX_CROSS_PATH}/"
ENV PATH=${OSX_CROSS_PATH}/target/bin:$PATH

# install docker cli and upgrade git so that it is new enough for the github action
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
	echo "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
	echo "deb http://deb.debian.org/debian stretch-backports main" > /etc/apt/sources.list.d/backports.list && \
	apt-get update && apt-get install -y docker-ce-cli git/stretch-backports

# install goreleaser that does not try docker manifest rm
# https://github.com/goreleaser/goreleaser/issues/2192
ARG GORELEASER_VERSION=0.160.0
ARG GORELEASER_SHA=651b1f5891b23dc5ea554d62dbef87954922dfdd187e662e09b47556e0744c70
RUN GORELEASER_DOWNLOAD_FILE=goreleaser_Linux_x86_64.tar.gz && \
	GORELEASER_DOWNLOAD_URL=https://github.com/goreleaser/goreleaser/releases/download/v${GORELEASER_VERSION}/${GORELEASER_DOWNLOAD_FILE} && \
	wget ${GORELEASER_DOWNLOAD_URL}; \
			echo "$GORELEASER_SHA $GORELEASER_DOWNLOAD_FILE" | sha256sum -c - || exit 1; \
			tar -xzf $GORELEASER_DOWNLOAD_FILE -C /usr/bin/ goreleaser; \
			rm $GORELEASER_DOWNLOAD_FILE;

COPY unlock-agent.sh /
COPY daemon.json /etc/docker/daemon.json
