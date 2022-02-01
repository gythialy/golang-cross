# Committs to master will trigger a push to Dockerhub

ARG GO_VERSION=1.15.15
ARG DEB_VERSION=stretch

FROM golang:${GO_VERSION}-${DEB_VERSION} AS base

ARG DEB_VERSION
ARG DEBIAN_FRONTEND=noninteractive
# Install deps
RUN echo "Starting image build for $(grep PRETTY_NAME /etc/os-release)" \
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
        git-core                                       \
        crossbuild-essential-arm64                     \
        curl                                           \
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
        ruby-dev

# install docker cli
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && \
    echo "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list && \
    apt-get update && apt-get install -y docker-ce-cli

COPY upgrade-git-on-stretch.sh /
RUN /upgrade-git-on-stretch.sh ${DEB_VERSION}
RUN apt-get -y autoremove && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Used only when building locally, else the latest goreleaser is installed by GHA
RUN curl -fsSL https://github.com/goreleaser/goreleaser/releases/latest/download/goreleaser_Linux_x86_64.tar.gz  | tar -C /usr/bin/ -xzf - goreleaser

# Seems like there's an issue with buildx while running docker cli from within the container - the
# experimental features are not enabled for the  CLI - to mitigate that.
ENV DOCKER_CLI_EXPERIMENTAL=enabled

# Upload to packagecloud.io
RUN gem install rake package_cloud

COPY unlock-agent.sh pc.sh /
COPY daemon.json /etc/docker/daemon.json
