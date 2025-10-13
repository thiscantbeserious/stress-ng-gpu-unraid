.PHONY: all build dist pack repo clean doctor help

-include .env

# Configurable via environment:
REF ?= master
OUT ?= dist
PLATFORM ?= linux/amd64
REPO ?= repo   # repo output directory (for PACKAGES.TXT, CHECKSUMS.md5)

export REF OUT PLATFORM REPO ARCH BUILD PKGNAME

# Default: build artifacts into ./dist using docker run
all: dist

ensure-exec:
	chmod +x scripts/*.sh || true

## Build the GPU-enabled stress-ng bundle using docker run
build: ensure-exec
	./scripts/build.sh

## Build + show artifacts
dist: build
	@echo ""; echo "Artifacts in $(OUT)/"; ls -l $(OUT)

## Create a Slackware-style .txz from ./dist bundle (for un-get)
pack: ensure-exec
	./scripts/pack-txz.sh --in $(OUT)/stress-ng-gpu-glibc-bundle.tar.gz --ver $(REF)

## Build + create repo metadata (PACKAGES.TXT, CHECKSUMS.md5)
repo: ensure-exec dist
	./scripts/pack-txz.sh --in $(OUT)/stress-ng-gpu-glibc-bundle.tar.gz --ver $(REF) --repo $(REPO)

## Clean artifacts
clean:
	rm -rf $(OUT) $(REPO)

## Diagnostics
doctor:
	docker --version || true
	uname -a || true

help:
	@echo "Targets:"
	@echo "  make            -> same as 'make dist'"
	@echo "  make build      -> run scripts/build.sh (docker run) to create ./$(OUT) artifacts"
	@echo "  make dist       -> build then list artifacts"
	@echo "  make pack       -> create Slackware .txz from the bundle (for un-get)"
	@echo "  make repo       -> build package + generate PACKAGES.TXT & CHECKSUMS.md5 in ./$(REPO)"
	@echo "  make clean      -> remove ./$(OUT) and ./$(REPO)"
	@echo "  make doctor     -> print basic diagnostics"
