#!/bin/bash
# Smoke-test: verify the zig-based toolchain (Dockerfile.zig) can build this
# project end-to-end with goreleaser inside the image.
#
# Compiles OpenSSL from source with zig cc into a static libcrypto (the distro
# .so fails on glibc symbol-versioning mismatches), runs goreleaser with
# .goreleaser.zig-openssl.yml, then executes the produced binary to verify the
# SHA-256 output.
#
# Usage:
#   ./smoke-test.sh [IMAGE]
#   IMAGE defaults to golang-cross-zig-test:goreleaser (local dev); CI passes
#   the published image, e.g. ghcr.io/gythialy/golang-cross:v1.26.6-zig
set -euo pipefail

cd "$(dirname "$0")"

IMAGE="${1:-golang-cross-zig-test:goreleaser}"

docker run --rm --platform linux/amd64 --entrypoint bash \
  -v "$(pwd):/w" -w /w \
  "${IMAGE}" -c '
    set -eux
    # build static libcrypto with zig cc, reused by goreleaser via CGO_LDFLAGS
    cd /tmp
    wget -q https://www.openssl.org/source/openssl-3.4.1.tar.gz
    echo "002a2d6b30b58bf4bea46c43bdd96365aaf8daa6c428782aa4feee06da197df3  openssl-3.4.1.tar.gz" | sha256sum -c -
    tar -xzf openssl-3.4.1.tar.gz && cd openssl-3.4.1
    printf "#!/bin/sh\nexec zig cc -target x86_64-linux-gnu \"\$@\"\n" > /usr/local/bin/zig-cc
    chmod +x /usr/local/bin/zig-cc
    ./Configure linux-x86_64 --prefix=/opt/openssl --libdir=lib -no-shared CC=/usr/local/bin/zig-cc
    make -j"$(nproc)" >/dev/null && make install_sw >/dev/null
    cd /w
    # run goreleaser inside the image (goreleaser + zig are preinstalled)
    CGO_ENABLED=1 \
    CGO_CFLAGS="-I/opt/openssl/include" \
    CGO_LDFLAGS="/opt/openssl/lib/libcrypto.a -lpthread -ldl" \
    goreleaser release --snapshot --clean --config .goreleaser.zig-openssl.yml
    # run the produced binary (layout includes GOAMD64: ..._linux_amd64_v1/)
    BIN=$(find dist -type f -name openssl-example | head -1)
    echo "running ${BIN}"
    "${BIN}" "hello from zig"
  '
