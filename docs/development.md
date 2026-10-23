# Development guide

How to work on the images themselves: repository layout, local builds, smoke
tests, bumping Go and publishing a release.

- Using the images → [README](../README.md)
- The legacy osxcross toolchain → [osxcross.md](osxcross.md)

## Repository layout

| path | what it is |
| --- | --- |
| `versions.json` | source of truth: supported majors, Go patch + tarball `sha256`, codenames, builders |
| `Dockerfile.tools` | shared base per codename: Go + release tools (goreleaser, cosign, syft, gcloud, …) |
| `Dockerfile.zig` | the supported toolchain, FROM the tools image |
| `Dockerfile.builder` | osxcross builder, FROM the tools image (legacy, 1.24 only) |
| `Dockerfile` | osxcross main image, FROM the builder image |
| `entrypoint.sh` | imports `PRIVATE_KEY` when set, then runs `goreleaser "$@"` |
| `scripts/` | `check-update.sh`, `check-os-compat.sh`, `clean-cache.sh`, `llvm.sh`, `registry-tags.sh`, `release-drift.sh`, `release.sh` (cut a release) |
| `example/` | `sqlite-example` (cgo + sqlite3) and `openssl-example` (cgo + OpenSSL), each with a smoke test |
| `.github/workflows/` | publishing, the nightly bump PR, the drift check, the SDK build, housekeeping |
| `docs/` | this guide and the legacy osxcross notes |

## Prerequisites

Docker with buildx, `bash`, `jq`, and `gh` for the Actions side. The published
zig images are multi-arch (`linux/amd64` + `linux/arm64`); the osxcross images
are `linux/amd64` only. Building the zig image is minutes with a warm layer
cache, the osxcross builder is ~20–30 minutes per codename because it compiles
clang/cctools against the macOS SDK.

## Build the images locally

```sh
# 1. shared tools base
docker build --platform linux/amd64 -f Dockerfile.tools \
  --build-arg GO_VERSION=1.27.2 --build-arg OS_CODENAME=trixie \
  -t golang-cross-tools:dev .

# 2. zig image, FROM that base
docker build --platform linux/amd64 -f Dockerfile.zig \
  --build-arg GO_VERSION=1.27.2 --build-arg OS_CODENAME=trixie \
  -t golang-cross-zig-test:goreleaser .
```

Both `bookworm` and `trixie` work as `OS_CODENAME`. The osxcross pair
(`Dockerfile.builder` → `Dockerfile`) needs the SDK stage and is documented in
[osxcross.md#build-your-own](osxcross.md#build-your-own).

Two things that surprise people:

- `ARG GO_VERSION` is the **bare** version (`1.27.2`), while `versions.json`
  stores it with the `go` prefix (`go1.27.2`).
- The image tags you build locally are just for testing; CI derives them from
  `versions.json` + the release tag.

## Run an example

`example/sqlite-example` wraps the usual goreleaser invocation:

```sh
cd example/sqlite-example
make snapshot IMAGE=golang-cross-zig-test:goreleaser CONFIG=.goreleaser.zig.yml
```

The target is a `docker run` with the project mounted at
`/golang-cross-example`, the docker socket passed through, and `PRIVATE_KEY`
forwarded when set; the arguments after the image name go straight to
`goreleaser` (see `entrypoint.sh`). The same command without the Makefile:

```sh
docker run --rm --privileged \
  -e PRIVATE_KEY="$(PRIVATE_KEY)" \
  -v "$(pwd)":/golang-cross-example \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -w /golang-cross-example \
  golang-cross-zig-test:goreleaser \
  --snapshot --clean --config .goreleaser.zig.yml
```

`make lint` runs `golangci-lint` on the example code; `make release` is the
non-snapshot variant (it wants `GITHUB_TOKEN` and a `CHANGELOG.md`).

## Smoke tests

A smoke test is not a unit test: it runs `goreleaser` **inside the image** and
then exercises the produced binaries, so it proves the image can really
cross-compile cgo for the targets it advertises.

| example | what it proves | command |
| --- | --- | --- |
| `sqlite-example` | `go-sqlite3` (CGO) builds for linux/darwin/windows through the image's `CC`/`CXX` | `make smoke-test IMAGE=… CONFIG=.goreleaser.zig.yml` |
| `openssl-example` | static libcrypto is compiled with `zig cc`, linked through cgo, and the binary runs (checks the SHA-256 output) | `make smoke-test IMAGE=…` (wraps `smoke-test.sh`) |

Pass any image tag you have — a published one or a locally built
`golang-cross-zig-test:goreleaser`:

```sh
cd example/sqlite-example
make smoke-test IMAGE=ghcr.io/gythialy/golang-cross:v1.27.2-0-trixie-zig CONFIG=.goreleaser.zig.yml

cd example/openssl-example
make smoke-test IMAGE=ghcr.io/gythialy/golang-cross:v1.27.2-0-trixie-zig
```

Where CI runs them:

- `builder.yml`, PR stage (`push_images=false`): builds the zig image with
  `--load` and runs **both** smoke tests against that local image — this is the
  only functional check a PR gets.
- `release-golang-cross.yml` (osxcross, trixie leg only): runs the sqlite smoke
  test against the just-published image, after signing.

The osxcross configs are `example/sqlite-example/.goreleaser.yml`; the zig ones
are `.goreleaser.zig.yml` and `.goreleaser.zig-openssl.yml`.

## Bumping Go

The daily `auto-release` workflow does the mechanical part:

1. `scripts/check-update.sh` reads the go.dev release list, appends a **new
   major** to `supported`, refreshes the patch + `sha256` of every supported
   major, and rewrites `Dockerfile.tools`' `ARG GO_VERSION` for the newest one.
   A brand-new major gets `codenames: ["bookworm", "trixie"]` and
   `builders: ["zig"]` by default.
2. The workflow then syncs the defaults that cannot be derived from
   `versions.json` alone: `Dockerfile.zig` follows the newest major, while
   `Dockerfile.builder` and the main image's `ARG BUILDER_TAG` follow the
   **osxcross** baseline (1.24), not the newest.
3. It commits to the auto-release branch and opens/updates one PR.

Merging that PR changes nothing in the registry — publishing still needs a
release tag (§ next). Two manual paths exist: `workflow_dispatch` with
`tools_only=true` bumps only the tool versions, and editing `versions.json` by
hand is fine as long as the shape matches:

```json
{
  "supported": ["1.24", "1.25"],
  "releases": {
    "1.25": {
      "version": "go1.25.14",
      "sha256": "a21ae5633a269bcd7e90cf767e48225633795e99d831742cbf3397064fee7712",
      "codenames": ["bookworm", "trixie"],
      "builders": ["zig"]
    }
  }
}
```

`supported` is also the build order; `codenames` and `builders` drive the matrix
(`builders` may be `["zig"]` or `["osxcross", "zig"]`, the latter only for 1.24).
Do not hand-write `sha256` — take it from the `go.dev/dl/?mode=json` entry for
that version.

## Cutting a release

A published release on a tag `vX.Y.Z-N` is the only trigger that publishes, so
cutting one is a normal step after a manifest bump. `scripts/release.sh` does the
bookkeeping and stops before pushing:

```sh
scripts/release.sh 1.27.2                     # dry run, tags the current commit
scripts/release.sh 1.26.9 1.27.2 --execute    # one release per major
scripts/release.sh 1.27 -t origin/main        # tag a specific commit/ref
```

The target defaults to **the current commit** (`HEAD`), so switch to or verify
the commit you mean to publish first; `-t/--target` overrides it. One release
publishes one major, so several bumped majors are passed as several versions.

It reads `versions.json` and the tag list, then:

- resolves the major from the version (`1.27.2`, `go1.27.2` or just `1.27` all
  work) and refuses a major that is not `supported` (publishing an EOL line only
  creates drift);
- checks that the version matches the manifest — including at the target commit,
  so tagging the wrong sha fails locally instead of in `resolve`;
- picks the first free revision `N` for each version (`--revision N` to be
  explicit — with several versions it applies to all of them) and refuses a tag
  that already exists;
- decides `--latest`: on only for the newest supported major;
- generates English notes from the manifest: the tags each repository will get,
  the trixie ownership rule, and `cosign verify` snippets with the right identity
  per builder (written to `.git/release-notes-<tag>.md`, editable before hand).

Options: `-t/--target REF` (default `HEAD`), `-n/--revision N`, `--previous TAG`
(changelog base), `--notes FILE` (single version only), `--latest` /
`--no-latest`, `--execute`. A major may appear only once, and a duplicate is
refused before anything is printed.

The raw command it ends up running is:

```sh
gh release create vX.Y.Z-N --target <full-sha> --title vX.Y.Z-N \
  --notes-file .git/release-notes-vX.Y.Z-N.md --latest=false
```

Things that stay manual:

- `N` is the build revision: the same Go version rebuilt (tool bump, signing
  fix). Cut the next free `N` rather than rebuilding an existing one — a rebuild
  moves the tags and orphans the old digests.
- One release publishes one major; several majors bumped together means several
  releases, possibly on the same commit. Run the script once per major.

What runs ([`builder.yml`](../.github/workflows/builder.yml),
[`release-golang-cross.yml`](../.github/workflows/release-golang-cross.yml)): the
zig and tools images for that one major, plus — for a major that still lists the
`osxcross` builder — the builder and main osxcross images. Every image is
keylessly signed at the tag; `release-golang-cross.yml` also verifies its own
signature by tag after signing.

The codename-less aliases (`latest`, `{major}-zig`, `{major}`, `vX.Y.Z-N`) are
owned by exactly one codename (trixie), so the two legs cannot race for them.

`release-drift.yml` then re-checks `versions.json` against the registry (weekly,
after every release, and on `workflow_dispatch`) and keeps a single tracking
issue open while any supported major is not properly released. The issue body
carries copy-pasteable publish commands, pinned to the commit the check read so a
release cut later still tags the manifest that pins the patch, and the issue
closes itself once the publish run finishes with the full expected tag set. Run
the check by hand with:

```sh
bash scripts/release-drift.sh --markdown   # 0 ok, 1 drift, 2 registry unreadable
```

## Validating a change

The repository has no PR build other than `welcome`, so run these locally before
pushing:

```sh
jq empty versions.json
bash -n scripts/*.sh
shellcheck scripts/*.sh
for f in .github/workflows/*.y*ml; do ruby -ryaml -e 'YAML.load_file(ARGV[0])' "$f"; done
```

`actionlint` is worth running on workflow changes; the repo currently reports 10
pre-existing shellcheck *style/info* findings (grouped redirects, backticks in
single-quoted markdown) and no errors. For a change to an image or a Dockerfile,
the real check is a local build plus a smoke test (§ above).

## Documentation map

| file | audience |
| --- | --- |
| [README](../README.md) | users: pulling, pinning, verifying, migrating |
| [osxcross.md](osxcross.md) | the legacy toolchain's images, signatures and publishing |
| this file | maintainers: building, testing, bumping, releasing |

The README is deliberately version-agnostic — supported versions live in
`versions.json`, so adding a Go version must never require a README edit.
