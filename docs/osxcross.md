# osxcross toolchain (legacy)

> **Status: legacy, being retired.** The zig toolchain is the supported path for
> every Go major. osxcross is only published for the **1.24** line — it is the
> only entry in `versions.json` whose `builders` still contains `osxcross` — and
> it receives no new Go versions. When 1.24 leaves `versions.json`, these images
> are retired with it. Nothing here is planned to change before then; this page
> exists so existing users can keep pinning, verifying and migrating.
>
> **New to this repo?** Use the zig images in the [README](../README.md) instead.

## Why it is going away

- It is frozen at Go 1.24: no newer Go patch will ever be built for it, while
  the zig toolchain tracks every supported major.
- The zig image is self-contained (no separate builder image), smaller, and
  builds natively on arm64.
- Both toolchains ship the same release tools (goreleaser, cosign, syft, gcloud,
  …), so migrating is a tag change plus a `CC`/`CXX` change — not a rework.

## Images

`golang-cross` (the osxcross main image) and `golang-cross-builder` (the image it
is built FROM) exist for 1.24 only, one per codename:

```
docker pull ghcr.io/gythialy/golang-cross:1.24                  # = 1.24-trixie
docker pull ghcr.io/gythialy/golang-cross:1.24-bookworm
docker pull ghcr.io/gythialy/golang-cross:v1.24.13-1-trixie
docker pull ghcr.io/gythialy/golang-cross:v1.24.13-1-bookworm

docker pull ghcr.io/gythialy/golang-cross-builder:1.24
docker pull ghcr.io/gythialy/golang-cross-builder:v1.24.13-1-trixie
```

Both are built on `golang-cross-tools:v1.24.13-1-<codename>`, which is published
in the same run.

### Mind the codename-less aliases

1.24 is the only major that ships **both** toolchains, so the codename-less
names are split between them:

| name | points at |
| --- | --- |
| `1.24` | osxcross, trixie |
| `v1.24.13-1` | **zig**, trixie (the alias rule says a dual-toolchain major resolves its `vX.Y.Z-N` to zig) |

The upshot: pin osxcross by a codename-suffixed tag (`v1.24.13-1-trixie`), and do
not assume `v1.24.13-1` is osxcross.

### Use revision `-1`, not `-0`

`v1.24.13-0` was the first 1.24 publication since 2025-08, but its osxcross
images were signed over the platform manifest instead of the OCI index the tags
resolve to (the workflow combined `push: true` with `load: true`; fixed in
[#489](https://github.com/gythialy/golang-cross/pull/489)). `cosign verify`
against `v1.24.13-0-trixie` therefore finds no signature. Revision `-1` is
correctly signed and all `1.24*` floats point at it.

### Verifying signatures

The osxcross main image is pushed by `release-golang-cross.yml`, so that is the
identity in the certificate:

```sh
cosign verify ghcr.io/gythialy/golang-cross:v1.24.13-1-trixie \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  --certificate-identity "https://github.com/gythialy/golang-cross/.github/workflows/release-golang-cross.yml@refs/tags/v1.24.13-1"
```

`golang-cross-builder` images answer to `builder.yml@refs/tags/v1.24.13-1`.
Images from `v1.24.6-0` (2025-08) and earlier are **key-signed** rather than
keyless: they carry no Fulcio certificate, so `--certificate-identity` does not
apply to them at all.

## Build your own

The builder image is the yak — it compiles the osxcross toolchain against the
macOS SDK, which takes ~20–30 minutes per codename.

```sh
# 1. builder image, FROM the tools image of the same Go version + revision
docker build --platform linux/amd64 -f Dockerfile.builder \
  --build-arg GO_VERSION=1.24.13 --build-arg OS_CODENAME=trixie \
  -t ghcr.io/gythialy/golang-cross-builder:v1.24.13-1-trixie .

# 2. main image, FROM the builder image (adds entrypoint only)
docker build --build-arg BUILDER_TAG=v1.24.13-1 \
  --build-arg OS_CODENAME=trixie \
  -f Dockerfile \
  -t ghcr.io/gythialy/golang-cross:v1.24.13-1-trixie .
```

The builder stage pulls the SDK tarball from the
[`osx-sdk`](https://github.com/gythialy/golang-cross/pkgs/container/osx-sdk)
image (`ARG OSK_SDK=macos-13`), so you do not need to
[pack the SDK](https://github.com/tpoechtrager/osxcross#packaging-the-sdk)
yourself; if you do want a different SDK, build one with the
[`osx-sdk` workflow](https://github.com/gythialy/golang-cross/actions/workflows/osx-sdk.yaml)
and pass `--build-arg OSK_SDK=macos-<n>`.

## Migrating to zig

Kept in one place so it cannot drift: the `CC`/`CXX` mapping, the darwin SDK
flags and the three-step procedure live in the README —
[Migrating from osxcross to zig](../README.md#migrating-from-osxcross-to-zig).

## How it is published

The release is cut like any other line — `scripts/release.sh 1.24` prints the
plan, `--execute` publishes it (see
[development.md#cutting-a-release](development.md#cutting-a-release)). It is the
same `vX.Y.Z-N` tag that triggers everything below.

`.github/workflows/release-golang-cross.yml` runs on a published release tag
(`vX.Y.Z-N`) and only builds the osxcross majors — currently just 1.24 — that
`versions.json` still lists:

1. `resolve` validates that `X.Y.Z` matches the manifest and derives the
   codename matrix.
2. A skip guard checks the expected tags for that revision and does nothing if
   they already exist; a `workflow_dispatch` always rebuilds.
3. Per codename: `build-builder` (tools + osxcross builder, via the reusable
   `builder.yml`), then `release` builds the main image, signs it, verifies the
   signature by tag and smoke-tests it with `example/sqlite-example` on trixie.

The codename-less `{major}` alias is owned by trixie, so the two build legs
cannot race for it.
