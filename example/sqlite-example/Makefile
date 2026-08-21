.PHONY: clean lint changelog snapshot release
.PHONY: build
.PHONY: deps

# Check for required command tools to build or stop immediately
EXECUTABLES = git go find pwd
K := $(foreach exec,$(EXECUTABLES),\
        $(if $(shell which $(exec)),some string,$(error "No $(exec) in PATH")))

VERSION ?= $(shell git describe --tags `git rev-list --tags --max-count=1`)
BINARY = golang-cross-example
MAIN = main.go

BUILDDIR = build
GITREV = $(shell git rev-parse --short HEAD)
BUILDTIME = $(shell date +'%FT%TZ%z')
GO_BUILDER_VERSION=latest
# Smoke-test image + goreleaser config. Defaults match the published
# osxcross image; override for zig, e.g.:
#   make smoke-test IMAGE=ghcr.io/gythialy/golang-cross:v1.26.6-zig CONFIG=.goreleaser.zig.yml
IMAGE ?= ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION)
CONFIG ?= .goreleaser.yml

deps:
	go get -u github.com/golangci/golangci-lint/cmd/golangci-lint
	go get -u github.com/git-chglog/git-chglog/cmd/git-chglog
	go get -u golang.org/x/tools/cmd/goimports

build:
	go build -o $(shell pwd)/$(BUILDDIR)/$(BINARY) $(shell pwd)/$(MAIN)
	@echo "Build $(BINARY) done."
	@echo "Run \"$(shell pwd)/$(BUILDDIR)/$(BINARY)\" to start $(BINARY)."

clean:
	rm -rf $(shell pwd)/$(BUILDDIR)/

changelog:
	git-chglog $(VERSION) > CHANGELOG.md

snapshot:
	docker run --rm --privileged \
		-e PRIVATE_KEY=$(PRIVATE_KEY) \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		$(IMAGE) --snapshot --clean --config $(CONFIG)

# Smoke-test: run goreleaser against the given image/config to verify the
# published image can cross-compile this project (osxcross or zig).
smoke-test: snapshot

release: changelog
	docker run --rm --privileged \
		-e GITHUB_TOKEN=$(GITHUB_TOKEN) \
		-e PRIVATE_KEY=$(PRIVATE_KEY) \
		-v $(CURDIR):/golang-cross-example \
		-v /var/run/docker.sock:/var/run/docker.sock \
		-v $(GOPATH)/src:/go/src \
		-w /golang-cross-example \
		ghcr.io/gythialy/golang-cross:$(GO_BUILDER_VERSION) --clean --release-notes=CHANGELOG.md

lint:
	golangci-lint run --fix

