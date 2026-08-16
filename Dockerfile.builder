# golang parameters
# GO_VERSION is bare (no "go" prefix). It selects the golang-cross-tools base
# image tag for the osxcross builder — which tracks the osxcross baseline
# (1.24), NOT the newest major (1.26 is zig and has no builder image).
ARG GO_VERSION=1.24.13
ARG OS_CODENAME=trixie
ARG OSK_SDK=macos-13

FROM ghcr.io/gythialy/osx-sdk:${OSK_SDK:-macos-13} AS osx-sdk

# ============================================================
# Stage 1: build osxcross (build-time deps stay in this stage)
# ============================================================
# NOTE: based on buildpack-deps, NOT golang:${GO_VERSION}. osxcross
# compilation (clang + cctools) does not need Go, and tying it to the
# golang image invalidated this ~30min stage on every Go patch bump.
FROM buildpack-deps:${OS_CODENAME:-trixie} AS osxcross-builder

# Re-declare ARG after FROM to make it available in this stage
ARG OS_CODENAME=trixie
ARG TARGETARCH

# osxcross parameters
ARG OSX_VERSION_MIN=10.13
ARG OSX_CROSS_COMMIT=ff8d100f3f026b4ffbe4ce96d8aac4ce06f1278b

ENV OSX_CROSS_PATH=/osxcross

ENV DEBIAN_FRONTEND=noninteractive
# Install deps
RUN set -x \
  && dpkg --add-architecture arm64                     \
  && dpkg --add-architecture armhf                     \
  && dpkg --add-architecture i386                      \
  && apt-get update -o Acquire::Retries=3              \
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

# install osxcross (shallow fetch of the pinned commit only, not the whole history)
RUN \
  git init -q . \
  && git remote add origin https://github.com/tpoechtrager/osxcross.git \
  && git fetch -q --depth 1 origin "${OSX_CROSS_COMMIT:-ff8d100f3f026b4ffbe4ce96d8aac4ce06f1278b}" \
  && git checkout -q FETCH_HEAD

# install osx sdk (copy the SDK tarball from the osx-sdk image into
# osxcross's tarballs/ dir; build.sh unpacks it automatically)
COPY --from=osx-sdk /osxcross/tarballs/ "${OSX_CROSS_PATH}/tarballs/"

# install cmake (host-arch-specific tarball: x86_64 / aarch64)
ARG CMAKE_VERSION=4.1.0
RUN \
  case "$TARGETARCH" in arm64) CMAKE_ARCH=aarch64 ;; *) CMAKE_ARCH=x86_64 ;; esac; \
  wget -qO- --tries=3 "https://github.com/Kitware/CMake/releases/download/v${CMAKE_VERSION}/cmake-${CMAKE_VERSION}-linux-${CMAKE_ARCH}.tar.gz" | tar --strip-components=1 -xz -C /usr/local \
  && cmake --version

# https://github.com/tpoechtrager/osxcross/issues/313
COPY patch/osxcross-08-52-08.patch "${OSX_CROSS_PATH}/"
RUN  patch -p1 < osxcross-08-52-08.patch

COPY scripts/llvm.sh "${OSX_CROSS_PATH}/"

RUN \
  # install clang: Debian >= trixie (13) gets clang-18, older gets clang-16.
  # Compare by VERSION_ID so future codenames (fork, ...) don't fall back to 16.
  if [ "$(sed -n 's/^VERSION_ID="\?\([0-9][0-9]*\).*/\1/p' /etc/os-release)" -ge 13 ] 2>/dev/null; then \
    apt-get update -o Acquire::Retries=3 && apt-get install -y --no-install-recommends clang-18 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-18 100; \
    sed -i 's/BRANCH=main/BRANCH=release\/18.x/g' build_compiler_rt.sh; \
  else \
  # install clang-16
    ./llvm.sh 16 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100; \
    sed -i 's/BRANCH=main/BRANCH=release\/16.x/g' build_compiler_rt.sh; \
  fi \
  && clang --version \
  && clang++ --version \
  && UNATTENDED=yes OSX_VERSION_MIN=${OSX_VERSION_MIN:-10.13} ./build.sh \
  && DISABLE_PARALLEL_ARCH_BUILD=1 ./build_compiler_rt.sh \
  && rm -rf *~ build *.tar.xz \
  && rm -rf ./.git \
  && ls -al "${OSX_CROSS_PATH}/target/bin" \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# ============================================================
# Stage 2: runtime image (only what end users need at build time)
# ============================================================
# Based on the shared tools image (golang + cosign/syft/goreleaser/.../gcloud),
# so the release toolchain is defined in one place (Dockerfile.tools).
FROM ghcr.io/gythialy/golang-cross-tools:v${GO_VERSION:-1.24.13}-0-${OS_CODENAME:-trixie}

# Re-declare ARG after FROM to make it available in this stage
ARG OS_CODENAME=trixie

ENV OSX_CROSS_PATH=/osxcross
ENV DEBIAN_FRONTEND=noninteractive

# Install runtime deps: clang (osxcross wrappers call it), cross
# compilers for the other targets (linux-arm/windows/musl) and the
# tools needed to run/verify foreign binaries. Build-time only deps
# (autoconf, cmake, llvm, libxml2-dev, ...) stay in stage 1.
# NOTE: clang version must match the one used in stage 1 (compiler-rt
# is installed under /osxcross/target/lib/clang/<version>).
RUN set -x \
  && dpkg --add-architecture arm64                     \
  && dpkg --add-architecture armhf                     \
  && apt-get update -o Acquire::Retries=3              \
  && apt-get install -y -q                             \
  binfmt-support                                 \
  crossbuild-essential-arm64                     \
  crossbuild-essential-armhf                     \
  file                                           \
  gdb                                            \
  git-core                                       \
  mingw-w64                                      \
  musl-tools                                     \
  openssl                                        \
  libssl-dev                                     \
  qemu-user-static                               \
  unzip                                          \
  xz-utils                                       \
  && if [ "$(sed -n 's/^VERSION_ID="\?\([0-9][0-9]*\).*/\1/p' /etc/os-release)" -ge 13 ] 2>/dev/null; then \
    apt-get install -y --no-install-recommends clang-18 llvm-18 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-18 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-18 100 && \
    ln -sf /usr/lib/llvm-18/bin/dsymutil /usr/bin/dsymutil; \
  else \
    apt-get install -y --no-install-recommends clang-16 llvm-16 && \
    update-alternatives --install /usr/bin/clang clang /usr/bin/clang-16 100 && \
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-16 100 && \
    ln -sf /usr/lib/llvm-16/bin/dsymutil /usr/bin/dsymutil; \
  fi \
  && dsymutil --version | head -1 \
  && clang --version \
  && apt -y autoremove                           \
  && apt-get clean                               \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy the osxcross toolchain built in stage 1
COPY --from=osxcross-builder /osxcross /osxcross

ENV PATH=/usr/local/bin:${OSX_CROSS_PATH}/target/bin:$PATH

# Basic test: the toolchain must produce Mach-O binaries
RUN cd /tmp \
  && printf '#include <stdio.h>\nint main(void){puts("hello darwin");return 0;}\n' > hello.c \
  && o64-clang hello.c -o hello.x86_64 \
  && oa64-clang hello.c -o hello.arm64 \
  && file hello.x86_64 hello.arm64 \
  && file hello.x86_64 | grep -q 'Mach-O 64-bit x86_64' \
  && file hello.arm64 | grep -q 'Mach-O 64-bit arm64' \
  && rm -f hello.c hello.x86_64 hello.arm64
