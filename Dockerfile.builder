# golang parameters
ARG GO_VERSION=1.22.2
ARG OS_CODENAME=bookworm
ARG OSK_SDK=macos-13

FROM ghcr.io/gythialy/osx-sdk:${OSK_SDK:-macos-13} AS osx-sdk

FROM golang:${GO_VERSION:-1.22.2}-${OS_CODENAME:-bookworm} AS base

# osxcross parameters
ARG OSX_VERSION_MIN=10.13
ARG OSX_CROSS_COMMIT=ff8d100f3f026b4ffbe4ce96d8aac4ce06f1278b
# ARG APT_MIRROR
# RUN sed -ri "s/(httpredir|deb).debian.org/${APT_MIRROR:-deb.debian.org}/g" /etc/apt/sources.list \
#   && sed -ri "s/(security).debian.org/${APT_MIRROR:-security.debian.org}/g" /etc/apt/sources.list

ENV OSX_CROSS_PATH=/osxcross

ARG DEBIAN_FRONTEND=noninteractive
# Install deps
RUN set -x; echo "Starting image build for Debian    " \
  && dpkg --add-architecture arm64                     \
  && dpkg --add-architecture armel                     \
  && dpkg --add-architecture armhf                     \
  && dpkg --add-architecture i386                      \
  && dpkg --add-architecture mips                      \
  && dpkg --add-architecture mipsel                    \
  && dpkg --add-architecture powerpc                   \
  && dpkg --add-architecture ppc64el                   \
  && dpkg --add-architecture s390x                     \
  && apt-get update                                    \
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
  # cmake                                          \
  qemu-user-static                               \
  libxml2-dev                                    \
  lzma-dev                                       \
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

# FIXME: install gcc-multilib
# FIXME: add mips and powerpc architectures

ENV PATH=/usr/local/bin:${OSX_CROSS_PATH}/target/bin:$PATH

WORKDIR "${OSX_CROSS_PATH}"

# install osxcross:
RUN \
  git clone https://github.com/tpoechtrager/osxcross.git . \
  && git checkout -q "${OSX_CROSS_COMMIT:-ff8d100f3f026b4ffbe4ce96d8aac4ce06f1278b}"

# install osx sdk
COPY --from=osx-sdk "${OSX_CROSS_PATH}/." "${OSX_CROSS_PATH}"

# install cmake
ARG CMAKE_VERSION=3.28.3
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
  ./llvm.sh 16 \
  && update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100 \
  && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100 \
  && clang --version \
  && clang++ --version \
  && UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN:-10.13} ./build.sh \
  && DISABLE_PARALLEL_ARCH_BUILD=1 ./build_compiler_rt.sh \
  && rm -rf *~ build *.tar.xz \
  && rm -rf ./.git \
  && ls -al "${OSX_CROSS_PATH}/target/bin" \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

