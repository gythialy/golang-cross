# golang-cross [![Actions Status](https://github.com/gythialy/golang-cross/workflows/Docker%20Image%20CI/badge.svg)](https://github.com/gythialy/golang-cross/actions)

Docker container to do cross compilation (Linux, windows, macOS, ARM, ARM64) of go packages including support for cgo.

The supported toolchain is **zig**: one self-contained image per Go major that
cross-compiles cgo for linux/darwin/windows and ships the release tools
(goreleaser, cosign, syft, gcloud, …). Go 1.24 additionally still carries the
older **osxcross** toolchain — it is frozen at that major and being retired, so
its images and migration guide live in
**[docs/osxcross.md](docs/osxcross.md)**.

> [!WARNING]
> **⛔ EOL notice — Go 1.17 – 1.23 are end-of-life and no longer maintained.**
> Their branches are archived under `archive/go-1.x` tags and remain available
> for reference but receive no updates. Supported versions: **Go 1.24+** (see
> `versions.json`).

## Supported versions

`versions.json` is the source of truth: it lists the supported Go majors, the Go
patch (and tarball `sha256`) each one builds from, the Debian codenames to build
for, and which builders to publish. No list is duplicated here — a new major
lands in that file first, which is why this section never needs an edit.

The supported floor is **Go 1.24**; older majors are EOL (see the notice above).
How a bump in that file becomes a published image is described in
[Publishing](#publishing) and, step by step, in
[docs/development.md#bumping-go](docs/development.md#bumping-go).

## Quick start

```sh
docker pull ghcr.io/gythialy/golang-cross:latest

cd your-project
docker run --rm --privileged \
  -v "$(pwd)":/golang-cross-example \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /golang-cross-example \
  ghcr.io/gythialy/golang-cross:v1.27.2-0-trixie-zig \
  release --snapshot --clean --config .goreleaser.zig.yml
```

The entrypoint imports `PRIVATE_KEY` (a base64-encoded GPG key) when it is set,
then runs `goreleaser` with whatever arguments you pass. `--privileged` and the
docker socket are only needed when your config builds through docker; drop them
otherwise. Pin a tag rather than `latest` when you care about reproducibility; the
`example/sqlite-example` Makefile wraps the same command (`make snapshot
IMAGE=… CONFIG=.goreleaser.zig.yml`).

## Zig images

### Pre-built

`latest` follows the newest Go major's `-trixie-zig` image. Patch-level tags
below are examples, not a fixed list — `versions.json` holds the currently
supported majors, and the [package
tags](https://github.com/gythialy/golang-cross/pkgs/container/golang-cross) are
the source of truth for what exists.

```
docker pull ghcr.io/gythialy/golang-cross:latest            # = newest -trixie-zig
docker pull ghcr.io/gythialy/golang-cross:1.27-zig
docker pull ghcr.io/gythialy/golang-cross:1.26-zig
docker pull ghcr.io/gythialy/golang-cross:1.25-zig
docker pull ghcr.io/gythialy/golang-cross:1.24-zig
docker pull ghcr.io/gythialy/golang-cross:v1.27.2-0-trixie-zig
docker pull ghcr.io/gythialy/golang-cross:v1.27.2-0         # = the git release tag
```

| tag | meaning |
| --- | --- |
| `vX.Y.Z-N-trixie-zig`, `vX.Y.Z-N-bookworm-zig` | one release revision of one codename |
| `vX.Y.Z-N` | alias of the **trixie** zig build — the same string as the git tag and the GitHub release |
| `{major}-zig` | newest published trixie build of that major |
| `{major}-trixie-zig`, `{major}-bookworm-zig` | per-codename float (landed in the 2026-10 releases; 1.26 and 1.27 get theirs on their next release) |
| `latest` | newest published trixie build overall |

`N` is the **build revision**: the same Go version rebuilt, for instance after a
tool bump. A fresh Go bump publishes `-0`; releasing `vX.Y.Z-1` afterwards
publishes `vX.Y.Z-1-trixie-zig`, `vX.Y.Z-1-bookworm-zig` and the `vX.Y.Z-1`
alias alongside the `-0` ones, which stay pullable.

Floating tags (`latest`, `1.27-zig`, `1.25-trixie-zig`) follow the most recently
**published** revision, not the numerically highest — re-releasing an older
revision moves them back to it. Cut the next free `N` rather than rebuilding an
existing one.

1.24 is the only major that also ships osxcross, and its codename-less names are
split between the two toolchains. If you are on 1.24 and need osxcross, read
[docs/osxcross.md](docs/osxcross.md) first — `1.24` is the osxcross image while
`v1.24.13-1` is the zig one.

### Verifying images

Every published image is keylessly signed with cosign. For images published from
September 2026 onward the signing identity is the workflow that pushed them, at
the **release tag** — `builder.yml@refs/tags/vX.Y.Z-N` for zig. Both workflows
that can publish refuse to do so from a branch ref, so a tag identity is the only
one they can produce. (The internal `golang-cross-tools` base image is also
published during pre-merge builds and can legitimately carry a branch identity —
it is not meant to be pinned.)

Substitute the version you are actually pinning — the example uses `v1.27.2-0`,
which is only current as of writing:

```sh
cosign verify ghcr.io/gythialy/golang-cross:v1.27.2-0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "https://github.com/gythialy/golang-cross/.github/workflows/builder.yml@refs/tags/v1.27.2-0"
```

Two things to watch when pinning a digest:

- Use the `-N` build revision in the identity (`v1.27.2-0`), not the bare Go
  version (`v1.27.2`). A bare `vX.Y.Z` release does not publish anything.
- Resolve the digest from the tag at the moment you pin it
  (`crane digest ghcr.io/gythialy/golang-cross:v1.27.2-0-trixie-zig`). Images
  published before September 2026 were built more than once per release, so some
  digests from that era are still pullable and validly signed but are no longer
  what the tag points at — and a few carry an `@refs/heads/main` identity instead
  of a tag.

### Build your own

Both stages come from the same manifests CI uses:

```sh
# 1. shared tools base (golang + cosign/syft/goreleaser/…/gcloud)
docker build --platform linux/amd64 -f Dockerfile.tools \
  --build-arg GO_VERSION=1.27.2 --build-arg OS_CODENAME=trixie \
  -t ghcr.io/gythialy/golang-cross-tools:v1.27.2-0-trixie .

# 2. zig image, FROM that base
docker build --platform linux/amd64 -f Dockerfile.zig \
  --build-arg GO_VERSION=1.27.2 --build-arg OS_CODENAME=trixie \
  -t ghcr.io/gythialy/golang-cross:v1.27.2-0-trixie-zig .
```

Override any default with `--build-arg`; `bookworm` works as a codename too.
The osxcross images are built differently and are documented in
[docs/osxcross.md](docs/osxcross.md#build-your-own).

## Migrating from osxcross to zig

> **⚠️ Breaking change**: the zig image uses a different C cross-compiler, so
> your goreleaser config's `CC`/`CXX` must change. osxcross images are frozen at
> Go 1.24 and receive no further Go updates — zig is the forward path.

Both toolchains ship the same release tools (goreleaser/cosign/syft/…) but
compile C with different compilers:

| target | osxcross (legacy) | zig (recommended) |
|---|---|---|
| darwin amd64 | `o64-clang` | `zig cc -target x86_64-macos` |
| darwin arm64 | `oa64-clang` | `zig cc -target aarch64-macos` |
| linux amd64 | (default gcc) | `zig cc -target x86_64-linux-gnu` |
| windows amd64 | `x86_64-w64-mingw32-gcc` | `zig cc -target x86_64-windows-gnu` |

Steps:

1. Switch the image tag — append `-zig` (e.g. `golang-cross:1.24` →
   `golang-cross:1.24-zig`, or `...:v1.24.13-1-trixie` →
   `...:v1.24.13-1-trixie-zig`).
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
[`example/sqlite-example/.goreleaser.zig.yml`](example/sqlite-example/.goreleaser.zig.yml)
(zig) — the zig config is the one the zig smoke test runs.

## Publishing

A published GitHub release on a tag `vX.Y.Z-N` is the **only** thing that
publishes images: draft releases never fire, a bare `vX.Y.Z` tag is skipped, and
the workflows refuse to publish from a branch ref.

Cut one with [`scripts/release.sh`](scripts/release.sh) — it derives the tag, the
next free revision and the release notes from `versions.json`, tags the current
commit (or `--target <ref>`), and prints the `gh release create` command:

```sh
scripts/release.sh 1.27.2                     # one line
scripts/release.sh 1.26.9 1.27.2 --execute    # several majors at once
```

Details in [docs/development.md#cutting-a-release](docs/development.md#cutting-a-release).

- One release publishes one major. Bump several majors and cut several releases
  — they may point at the same commit.
- `builder.yml` publishes the zig and `golang-cross-tools` images;
  `release-golang-cross.yml` publishes the osxcross ones (1.24 only).
- The codename-less aliases (`latest`, `{major}-zig`, `vX.Y.Z-N`, and `{major}`
  for the osxcross major) are owned by exactly one codename (trixie), so the two
  build legs cannot race for them.
- `release-drift.yml` checks weekly — and after every release — that every major
  in `versions.json` is properly released, and keeps a single tracking issue open
  while that is not true.

## GoReleaser configuration

The zig image ships `goreleaser` and the tooling, so the only thing your config
must get right is the C cross-compiler. Start from a working example:

- [`example/sqlite-example/.goreleaser.zig.yml`](example/sqlite-example/.goreleaser.zig.yml)
  — `go-sqlite3` on linux/darwin/windows; per-target `CC`/`CXX`
  (`zig cc -target …`), darwin SDK flags and `-ldflags "-s -w"`.
- [`example/openssl-example/.goreleaser.zig-openssl.yml`](example/openssl-example/.goreleaser.zig-openssl.yml)
  — OpenSSL EVP through cgo.

Migrating an existing osxcross config? The `CC`/`CXX` mapping, the darwin SDK
flags and the three-step procedure are in
[Migrating from osxcross to zig](#migrating-from-osxcross-to-zig) above.

Set up GPG signing (optional) if you enable goreleaser's
[signing](https://goreleaser.com/customization/sign/) feature:

```bash
export PRIVATE_KEY=$(cat ~/private_key.gpg | base64)
```

## Examples

- [sqlite-example](example/sqlite-example) — `go-sqlite3` cgo
  ([zig config](example/sqlite-example/.goreleaser.zig.yml); the osxcross
  [`config`](example/sqlite-example/.goreleaser.yml) is kept for the legacy
  image)
- [openssl-example](example/openssl-example) — OpenSSL EVP cgo via zig
  ([config](example/openssl-example/.goreleaser.zig-openssl.yml))
- [Makefile targets](example/sqlite-example/Makefile#L40-L51) — `snapshot`, `smoke-test`

Smoke tests (what they assert, how to run them against a published or a locally
built image) are part of the development guide:
[docs/development.md#smoke-tests](docs/development.md#smoke-tests).

## Development

Working on the images themselves — repo layout, local builds, smoke tests, bumping
Go and cutting a release — is covered in
[docs/development.md](docs/development.md).

## Alternative projects

- [goreleaser/goreleaser-cross](https://github.com/goreleaser/goreleaser-cross)
