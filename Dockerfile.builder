# golang parameters
ARG GO_VERSION=1.25.0
ARG OS_CODENAME=trixie
ARG OSK_SDK=macos-13

FROM ghcr.io/gythialy/osx-sdk:${OSK_SDK:-macos-13} AS osx-sdk

FROM golang:${GO_VERSION:-1.25.0}-${OS_CODENAME:-trixie} AS base

# Re-declare ARG after FROM to make it available in this stage
ARG OS_CODENAME=trixie

# osxcross parameters
ARG OSX_VERSION_MIN=10.13
ARG OSX_CROSS_COMMIT=f873f534c6cdb0776e457af8c7513da1e02abe59
# ARG APT_MIRROR
# RUN sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
#   && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list

ENV OSX_CROSS_PATH=/osxcross

ARG DEBIAN_FRONTEND=noninteractive
# Install deps
RUN set -x; echo "Starting image build for Debian    " \
  && dpkg --add-architecture arm64                     \
  && dpkg --add-architecture armhf                     \
  && dpkg --add-architecture i386                      \
  && apt-get update                                    \
  && if [ "${OS_CODENAME}" != "trixie" ]; then \
   apt-get install -y -q software-properties-common multistrap lzma-dev; \
  fi \
  && apt-get install -y -q                             \
  autoconf                                       \
  automake                                       \
  autotools-dev                                  \
  bc                                             \
  binfmt-support                                 \
  binutils-multiarch                             \
  binutils-multiarch-dev                         \
  build-essential                                \
  # clang                                          \
  crossbuild-essential-arm64                     \
  crossbuild-essential-armhf                     \
  curl                                           \
  devscripts                                     \
  gdb                                            \
  git-core                                       \
  libtool                                        \
  llvm                                           \
  mercurial                                      \
  mmdebstrap                                     \
  patch                                          \
  subversion                                     \
  wget                                           \
  xz-utils                                       \
  # cmake                                          \
  qemu-user-static                               \
  libxml2-dev                                    \
  liblzma-dev                                    \
  zlib1g-dev                                     \
  openssl                                        \
  mingw-w64                                      \
  musl-tools                                     \
  libssl-dev                                     \
  unzip                                          \
  gnupg                                          \
  lsb-release                                    \
  && apt -y autoremove                           \
  && apt-get clean                               \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

ENV PATH=/usr/local/bin:${OSX_CROSS_PATH}/target/bin:$PATH

WORKDIR "${OSX_CROSS_PATH}"

# install osxcross:
RUN \
  git clone https://github.com/tpoechtrager/osxcross.git . \
  && git checkout -q "${OSX_CROSS_COMMIT:-f873f534c6cdb0776e457af8c7513da1e02abe59}"

# install osx sdk
COPY --from=osx-sdk "${OSX_CROSS_PATH}/." "${OSX_CROSS_PATH}"

# install cmake
ARG CMAKE_VERSION=4.1.0
RUN \
  # wget https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}.tar.gz \
  # && tar -xf cmake-${CMAKE_VERSION}.tar.gz \
  # && cd cmake-${CMAKE_VERSION} \
  # && ./bootstrap \
  # && make \
  # && make install \
  # && cmake --version \
  # && cd .. \
  # && rm -rf cmake-${CMAKE_VERSION}.tar.gz cmake-${CMAKE_VERSION}
  wget -qO- "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-x86_64.tar.gz" | tar --strip-components=1 -xz -C /usr/local \
  && cmake --version

# https://github.com/tpoechtrager/osxcross/issues/313
COPY patch/osxcross-08-52-08.patch "${OSX_CROSS_PATH}/"
RUN  patch -p1 < osxcross-08-52-08.patch

COPY scripts/llvm.sh "${OSX_CROSS_PATH}/"
RUN \
  # install clang-16
  if [ "${OS_CODENAME}" = "trixie" ]; then \
    apt-get update && apt-get install -y --no-install-recommends clang-18 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-18 100; \
  else \
    ./llvm.sh 16 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100; \
  fi \
  && clang --version \
  && clang++ --version \
  && UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN:-10.13} ./build.sh \
  && DISABLE_PARALLEL_ARCH_BUILD=1 ./build_compiler_rt.sh \
  && rm -rf *~ build *.tar.xz \
  && rm -rf ./.git \
  && ls -al "${OSX_CROSS_PATH}/target/bin" \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

