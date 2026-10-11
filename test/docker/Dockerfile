# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
#
# Full test image: Ubuntu 24.04 (same base as KDE Neon) with every optional tool
# fdwam can use. bats itself is NOT installed here; the pinned submodule in
# test/bats is used so that local, CI and in-container runs share one version.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash coreutils curl wget ca-certificates \
      desktop-file-utils libglib2.0-bin \
      imagemagick librsvg2-bin file jq python3 shellcheck \
      bsdutils util-linux make \
 && rm -rf /var/lib/apt/lists/* \
 && if command -v gawk >/dev/null 2>&1; then echo "gawk must not be installed (KDE Neon ships mawk)" >&2; exit 1; fi \
 && useradd -m -u 1001 -s /bin/bash tester \
 && mkdir -p /tmp/home && chmod 1777 /tmp/home

WORKDIR /src
