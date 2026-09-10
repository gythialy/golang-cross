# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo.

> **EOL notice**: Go 1.17 – 1.23 are end-of-life and no longer maintained.
> Their branches are archived under `archive/go-1.x` tags and remain
> available for reference but receive no updates. Supported versions:
> **Go 1.24+** (see `versions.json`).

## Docker images

### Pre-built Images

Two toolchains in one repo; `latest` points at the newest Go's **zig** image.
Go 1.24 ships **both** (osxcross + zig); the zig variant is recommended —
smaller, faster, native arm64. See the migration note below.

Patch-level tags below are examples, not a fixed list — `versions.json` holds
the currently supported majors, and the [package
tags](https://github.com/gythialy/golang-cross/pkgs/container/golang-cross) are
the source of truth for what exists.

- `golang-cross` — zig toolchain (Go 1.24+, self-contained)
  ```
  docker pull ghcr.io/gythialy/golang-cross:latest            # = newest -trixie-zig
  docker pull ghcr.io/gythialy/golang-cross:1.26-zig
  docker pull ghcr.io/gythialy/golang-cross:1.25-zig
  docker pull ghcr.io/gythialy/golang-cross:1.24-zig          # Go 1.24 on zig
  docker pull ghcr.io/gythialy/golang-cross:v1.27.1-0-trixie-zig
  docker pull ghcr.io/gythialy/golang-cross:v1.27.1-0         # = the git release tag
  ```
  `vX.Y.Z-N` (no codename) is an alias for `vX.Y.Z-N-trixie-zig`, named to match
  the git tag and GitHub release that published it — the tag to use when you
  want the image and its cosign identity to reference the same string.
- `golang-cross` — osxcross toolchain (Go 1.24 only, legacy)
  ```
  docker pull ghcr.io/gythialy/golang-cross:1.24
  docker pull ghcr.io/gythialy/golang-cross:v1.24.13-0-trixie
  ```
- `golang-cross-builder` — osxcross toolchain image (FROM base of the osxcross main image)
  ```
  docker pull ghcr.io/gythialy/golang-cross-builder:1.24
  docker pull ghcr.io/gythialy/golang-cross-builder:v1.24.13-0-trixie
  ```

### Verifying images

Every published image is keylessly signed with cosign. For `golang-cross` and
`golang-cross-builder` images published from September 2026 onward, the signing
identity is the workflow that pushed it, at the **release tag** — `vX.Y.Z-N`,
with the build revision. Both workflows that can publish those images refuse to
do so from a branch ref, so a tag identity is the only one they can produce.
(Some older images predate that rule; see the pinning notes below. The internal
`golang-cross-tools` base image is also published during pre-merge builds and
can legitimately carry a branch identity — it is not meant to be pinned.)

Substitute the version you are actually pinning — the examples below use
`v1.27.1-0` / `v1.24.13-0`, which are only current as of writing:

```sh
# zig images (Go 1.24+) are published by builder.yml. The image tag, the git
# tag and the identity all read v1.27.1-0:
cosign verify ghcr.io/gythialy/golang-cross:v1.27.1-0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "https://github.com/gythialy/golang-cross/.github/workflows/builder.yml@refs/tags/v1.27.1-0"

# the osxcross main image (Go 1.24) is published by release-golang-cross.yml
cosign verify ghcr.io/gythialy/golang-cross:v1.24.13-0-trixie \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "https://github.com/gythialy/golang-cross/.github/workflows/release-golang-cross.yml@refs/tags/v1.24.13-0"
```

Two things to watch when pinning a digest:

- Use the `-N` build revision in the identity (`v1.27.1-0`), not the bare Go
  version (`v1.27.1`). A bare `vX.Y.Z` release does not publish anything.
- Resolve the digest from the tag at the moment you pin it
  (`crane digest ghcr.io/gythialy/golang-cross:v1.27.1-0-trixie-zig`). Images
  published before September 2026 were built more than once per release, so
  some digests from that era are still pullable and validly signed but are no
  longer what the tag points at — and a few carry an `@refs/heads/main`
  identity instead of a tag.

### Build your own
- Build the shared tools base image (golang + cosign/syft/goreleaser/.../gcloud)
  ```
  docker build --platform linux/amd64 -f Dockerfile.tools \
    --build-arg GO_VERSION=1.26.6 --build-arg OS_CODENAME=trixie \
    -t ghcr.io/gythialy/golang-cross-tools:v1.26.6-0-trixie .
  ```

- Build the osxcross builder image (from the tools image)
  ```
  docker build --platform linux/amd64 -f Dockerfile.builder \
    --build-arg GO_VERSION=1.24.13 --build-arg OS_CODENAME=trixie \
    -t ghcr.io/gythialy/golang-cross-builder:v1.24.13-0-trixie .
  ```
  > Note: [Pack the SDK](https://github.com/tpoechtrager/osxcross#packaging-the-sdk) first or use [GitHub Action](https://github.com/gythialy/golang-cross/actions/workflows/osx-sdk.yaml)

- Build the zig image (from the tools image)
  ```
  docker build --platform linux/amd64 -f Dockerfile.zig \
    --build-arg GO_VERSION=1.26.6 --build-arg OS_CODENAME=trixie \
    -t ghcr.io/gythialy/golang-cross:v1.26.6-0-trixie-zig .
  ```

- Build golang-cross image (osxcross toolchain, from the builder image)
  ```
  docker build --build-arg BUILDER_TAG=v1.24.13-0 \
    --build-arg OS_CODENAME=trixie \
    -f Dockerfile \
    -t ghcr.io/gythialy/golang-cross:v1.24.13-0-trixie .
  ```
  >  Override default arguments with `--build-arg`

## Migrating from osxcross to zig

> **⚠️ Breaking change**: the zig image uses a different C cross-compiler, so
> your goreleaser config's `CC`/`CXX` must change. osxcross images are frozen
> at Go 1.24 and receive no further Go updates — zig is the forward path.

Both toolchains ship the same release tools (goreleaser/cosign/syft/...) but
compile C with different compilers:

| target | osxcross (legacy) | zig (recommended) |
|---|---|---|
| darwin amd64 | `o64-clang` | `zig cc -target x86_64-macos` |
| darwin arm64 | `oa64-clang` | `zig cc -target aarch64-macos` |
| linux amd64 | (default gcc) | `zig cc -target x86_64-linux-gnu` |
| windows amd64 | `x86_64-w64-mingw32-gcc` | `zig cc -target x86_64-windows-gnu` |

Steps:

1. Switch the image tag — append `-zig` (e.g. `golang-cross:1.24` →
   `golang-cross:1.24-zig`, or `...:v1.24.13-0-trixie-zig`).
2. Replace `CC`/`CXX` per the table above.
3. For darwin targets, add the macOS SDK flags (the zig image exposes the SDK
   path as `OSX_SDK_PATH`) and `-ldflags "-s -w"` (skips dsymutil, which the
   zig image does not ship):

   ```yaml
   env:
     - CGO_ENABLED=1
     - CC=zig cc -target x86_64-macos
     - CXX=zig c++ -target x86_64-macos
     - CGO_CFLAGS=-isysroot {{ .Env.OSX_SDK_PATH }} -mmacosx-version-min=11.0
     - CGO_LDFLAGS=-isysroot {{ .Env.OSX_SDK_PATH }} -L{{ .Env.OSX_SDK_PATH }}/usr/lib -F{{ .Env.OSX_SDK_PATH }}/System/Library/Frameworks
   ldflags:
     - -s -w
   ```

Reference configs: `example/sqlite-example/.goreleaser.yml` (osxcross) vs
`example/sqlite-example/.goreleaser.zig.yml` (zig).

## Usage

- Prepare [GoReleaser](https://goreleaser.com/intro/) configuration

- Set up GPG signing (optional), if enable the [signing](https://goreleaser.com/customization/sign/) feature

  ```bash
  export PRIVATE_KEY=$(cat ~/private_key.gpg | base64)
  ```

- Build the binaries:
  ```bash
  export GO_BUILDER_VERSION=v1.17.1;
  docker run --rm --privileged \
    -e PRIVATE_KEY=$(PRIVATE_KEY) \
    -v $(CURDIR):/golang-cross-example \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v $(GOPATH)/src:/go/src \
    -w /golang-cross-example \
    ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --snapshot --rm-dist
  ```

## Examples

- [sqlite-example](example/sqlite-example) — go-sqlite3 cgo (osxcross: [.goreleaser.yml](example/sqlite-example/.goreleaser.yml), zig: [.goreleaser.zig.yml](example/sqlite-example/.goreleaser.zig.yml))
- [openssl-example](example/openssl-example) — OpenSSL EVP cgo via zig ([.goreleaser.zig-openssl.yml](example/openssl-example/.goreleaser.zig-openssl.yml))
- [Makefile](example/sqlite-example/Makefile#L35-L42)

Local smoke-test of a published image (also run in CI on release):

```sh
cd example/sqlite-example && make smoke-test IMAGE=ghcr.io/gythialy/golang-cross:v1.26.6-0-trixie-zig CONFIG=.goreleaser.zig.yml
cd example/openssl-example && make smoke-test IMAGE=ghcr.io/gythialy/golang-cross:v1.26.6-0-trixie-zig
```

## Alternative projects

- [goreleaser/goreleaser-cross](https://github.com/goreleaser/goreleaser-cross)
