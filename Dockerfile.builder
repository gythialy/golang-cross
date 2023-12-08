# golang parameters
ARG GO_VERSION=1.19.13

# osxcross parameters
ARG OSX_VERSION_MIN=10.12
ARG OSX_CROSS_COMMIT=50e86ebca7d14372febd0af8cd098705049161b9

FROM ghcr.io/gythialy/osx-sdk:v12 AS osx-sdk

FROM golang:${GO_VERSION:-1.19.13}-bullseye AS base

ARG APT_MIRROR
RUN sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
  && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list

ENV OSX_CROSS_PATH=/osxcross

ARG DEBIAN_FRONTEND=noninteractive
# Install deps
RUN set -x; echo "Starting image build for Debian    " \
  && dpkg --add-architecture arm64               \
  && dpkg --add-architecture armel               \
  && dpkg --add-architecture armhf               \
  && dpkg --add-architecture i386                \
  && dpkg --add-architecture mips                \
  && dpkg --add-architecture mipsel              \
  && dpkg --add-architecture powerpc             \
  && dpkg --add-architecture ppc64el             \
  && dpkg --add-architecture s390x               \
  && apt-get update                              \
  && apt-get install -y -q                       \
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
  crossbuild-essential-armel                     \
  crossbuild-essential-armhf                     \
  crossbuild-essential-mipsel                    \
  crossbuild-essential-ppc64el                   \
  crossbuild-essential-s390x                     \
  curl                                           \
  devscripts                                     \
  gdb                                            \
  git-core                                       \
  libtool                                        \
  llvm                                           \
  mercurial                                      \
  multistrap                                     \
  patch                                          \
  software-properties-common                     \
  subversion                                     \
  wget                                           \
  xz-utils                                       \
  cmake                                          \
  qemu-user-static                               \
  libxml2-dev                                    \
  lzma-dev                                       \
  openssl                                        \
  mingw-w64                                      \
  musl-tools                                     \
  libssl-dev                                     \
  && apt -y autoremove                           \
  && apt-get clean                               \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# FIXME: install gcc-multilib
# FIXME: add mips and powerpc architectures

WORKDIR "${OSX_CROSS_PATH}"
# install osxcross:
RUN git clone https://github.com/tpoechtrager/osxcross.git . \
  && git checkout -q "${OSX_CROSS_COMMIT:-50e86ebca7d14372febd0af8cd098705049161b9}"

# install osx sdk
COPY --from=osx-sdk "${OSX_CROSS_PATH}/." "${OSX_CROSS_PATH}"

# https://github.com/tpoechtrager/osxcross/issues/313
COPY patch/osxcross-08-52-08.patch "${OSX_CROSS_PATH}/"
RUN  patch -p1 < osxcross-08-52-08.patch

RUN \
  UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN:-10.12} ./build.sh \
  && ./build_compiler_rt.sh \
  && rm -rf *~ build *.tar.xz \
  && rm -rf ./.git

ENV PATH=${OSX_CROSS_PATH}/target/bin:$PATH
