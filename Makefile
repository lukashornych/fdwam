# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
#
# Tests run in Docker by default (Ubuntu 24.04, non-root, --network none).
# See docs/dev/testing.md.

IMAGE        ?= fdwam-test
IMAGE_MIN    ?= fdwam-test-minimal
PREFIX       ?= $(HOME)/.local
# Release version stamped into dist/fdwam ("v1.2.3" or "1.2.3"; the repository copy says "development").
VERSION      ?= development
DIST         ?= dist
BATS         := ./test/bats/bin/bats
TESTS        ?= test/
NO_BUILD     ?=
SHELL_FILES  := bin/fdwam install.sh completions/fdwam.bash test/test_helper.bash test/stubs/fake-browser test/stubs/kbuildsycoca6 test/stubs/kbuildsycoca5 test/stubs/update-desktop-database

DOCKER_RUN = docker run --rm --network none \
  --user "$$(id -u):$$(id -g)" \
  -e HOME=/tmp/home -e FDWAM_UPDATE_GOLDEN \
  -v "$(CURDIR):/src" -w /src

.PHONY: all test test-minimal test-local lint lint-local image image-minimal golden dist install uninstall clean

all: lint test

image:
ifeq ($(NO_BUILD),)
	docker build -t $(IMAGE) -f test/docker/Dockerfile test/docker
endif

image-minimal:
ifeq ($(NO_BUILD),)
	docker build -t $(IMAGE_MIN) -f test/docker/Dockerfile.minimal test/docker
endif

## Full test suite in the full image (all optional tools present).
test: image
	$(DOCKER_RUN) $(IMAGE) $(BATS) $(TESTS)

## Degradation tests in the minimal image (only bash, coreutils, curl, python3).
test-minimal: image-minimal
	$(DOCKER_RUN) $(IMAGE_MIN) $(BATS) $(TESTS)

## Fast loop without Docker (Linux only).
test-local:
	$(BATS) $(TESTS)

## Rewrites the golden files with the current output (review the git diff!).
golden: image
	FDWAM_UPDATE_GOLDEN=1 $(DOCKER_RUN) $(IMAGE) $(BATS) test/desktop.bats

lint: image
	$(DOCKER_RUN) $(IMAGE) shellcheck -S warning $(SHELL_FILES)
	$(DOCKER_RUN) $(IMAGE) bash -n bin/fdwam install.sh

lint-local:
	shellcheck -S warning $(SHELL_FILES)

## Release assets: version-stamped script, completion and SHA256SUMS (used by release.yml).
dist:
	mkdir -p "$(DIST)"
	sed 's/^readonly FDWAM_VERSION="development"$$/readonly FDWAM_VERSION="$(patsubst v%,%,$(VERSION))"/' bin/fdwam > "$(DIST)/fdwam"
	grep -q '^readonly FDWAM_VERSION="$(patsubst v%,%,$(VERSION))"$$' "$(DIST)/fdwam"
	chmod 0755 "$(DIST)/fdwam"
	bash -n "$(DIST)/fdwam"
	cp completions/fdwam.bash "$(DIST)/fdwam.bash"
	cd "$(DIST)" && sha256sum fdwam fdwam.bash > SHA256SUMS

install:
	install -Dm755 bin/fdwam "$(PREFIX)/bin/fdwam"
	install -Dm644 completions/fdwam.bash "$(PREFIX)/share/bash-completion/completions/fdwam"
	@echo "installed $(PREFIX)/bin/fdwam"

uninstall:
	rm -f "$(PREFIX)/bin/fdwam" "$(PREFIX)/share/bash-completion/completions/fdwam"

clean:
	rm -rf "$(DIST)"
	-docker rmi $(IMAGE) $(IMAGE_MIN) 2>/dev/null
