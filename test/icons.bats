#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Favicon pipeline and name detection against a local HTTP server.
# These tests check only the icon and the name, never golden .desktop files
# (a 127.0.0.1:<port> URL would change the app_id).

load test_helper

PORT=18791
BASE="http://127.0.0.1:$PORT"

setup_file() {
  cd "$BATS_TEST_DIRNAME/fixtures/html"
  python3 -m http.server --bind 127.0.0.1 "$PORT" >/dev/null 2>&1 &
  echo $! > "$BATS_FILE_TMPDIR/server.pid"
  local i=0
  until curl -fs "$BASE/noicon/index.html" >/dev/null 2>&1; do
    sleep 0.1; i=$((i + 1)); (( i < 100 )) || { echo "fixture server did not start"; return 1; }
  done
}

teardown_file() {
  kill "$(cat "$BATS_FILE_TMPDIR/server.pid")" 2>/dev/null || true
}

has_imagemagick() { command -v magick >/dev/null 2>&1 || command -v convert >/dev/null 2>&1; }

png_size() {
  # prints WxH of a PNG from its IHDR
  python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print("%dx%d"%struct.unpack(">II",d[16:24]))' "$1"
}

@test "manifest: largest manifest icon wins and name comes from og:site_name" {
  run "$FDWAM" create "$BASE/manifest/index.html" brave -y
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/127-0-0.conf" name)" "Mani & Fest"
  [[ -f "$ICON_DIR/127-0-0.png" ]]
  assert_equal "$(png_size "$ICON_DIR/127-0-0.png")" 192x192
}

@test "manifest name is used when the page has no og:site_name/application-name" {
  source_fdwam
  META_NAME=""
  local raw=()
  manifest_collect "$BASE/manifest/site.webmanifest" raw
  assert_equal "$META_NAME" "ManiApp"
  assert_equal "${#raw[@]}" 2
  [[ "${raw[1]}" == "1|192|manifest 192x192 512x512|$BASE/manifest/big.png" ]]
  [[ "${raw[0]}" == "1|48|manifest 48x48|$BASE/manifest/small.png" ]]
}

@test "manifest fallback parser (without jq) finds the same icons" {
  source_fdwam
  local nojq="$T/nojq"
  mkdir -p "$nojq"
  for t in bash curl wget python3 sed grep tr head cat sort awk od mktemp mv cp rm mkdir; do
    p="$(command -v $t 2>/dev/null)" && ln -sf "$p" "$nojq/$t"
  done
  META_NAME=""
  local raw=()
  PATH="$nojq" manifest_collect "$BASE/manifest/site.webmanifest" raw
  assert_equal "${#raw[@]}" 2
  [[ "${raw[1]}" == *"|$BASE/manifest/big.png" ]]
  assert_equal "$META_NAME" "ManiApp"
}

@test "candidate order: manifest > apple-touch-icon > icon > favicon.ico" {
  source_fdwam
  site_fetch_metadata "$BASE/manifest/index.html"
  assert_equal "$META_NAME" "Mani & Fest"
  assert_equal "${#META_CANDIDATES[@]}" 5
  [[ "${META_CANDIDATES[0]}" == "1|192|manifest 192x192 512x512|$BASE/manifest/big.png" ]]
  [[ "${META_CANDIDATES[1]}" == "1|48|manifest 48x48|$BASE/manifest/small.png" ]]
  [[ "${META_CANDIDATES[2]}" == "2|180|apple-touch-icon 180x180|$BASE/manifest/touch.png" ]]
  [[ "${META_CANDIDATES[3]}" == "3|32|icon 32x32|$BASE/manifest/icon32.png" ]]
  # the explicit <link rel="shortcut icon"> and the implicit /favicon.ico guess are deduplicated
  [[ "${META_CANDIDATES[4]}" == "3|0|icon|$BASE/favicon.ico" ]]
}

@test "apple-touch-icon only (protocol-relative URL, upper-case tag) and application-name" {
  run "$FDWAM" create "$BASE/touch/index.html" brave -y
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/127-0-0.conf" name)" "Touchy"
  assert_equal "$(png_size "$ICON_DIR/127-0-0.png")" 180x180
}

@test "relative links resolve against the page URL" {
  source_fdwam
  site_fetch_metadata "$BASE/relative/sub/index.html"
  [[ "${META_CANDIDATES[0]}" == "3|64|icon 64x64|$BASE/relative/sub/img/rel.png" ]]
  [[ "${META_CANDIDATES[1]}" == "3|16|icon 16x16|$BASE/relative/sub/../root.png" ]]
  run "$FDWAM" create "$BASE/relative/sub/index.html" brave --name Rel -y
  assert_success
  assert_equal "$(png_size "$ICON_DIR/127-0-0.png")" 64x64
}

@test "SVG icons are preferred and kept as SVG" {
  run "$FDWAM" create "$BASE/svg/index.html" brave --name Svg -y
  assert_success
  [[ -f "$ICON_DIR/127-0-0.svg" ]]
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-127-0-0.desktop" Icon)" "$ICON_DIR/127-0-0.svg"
}

@test "only /favicon.ico: converted with ImageMagick, largest layer, else generic icon" {
  run "$FDWAM" create "$BASE/ico/index.html" brave --name Ico -y
  assert_success
  if has_imagemagick; then
    [[ -f "$ICON_DIR/127-0-0.png" ]]
    assert_equal "$(png_size "$ICON_DIR/127-0-0.png")" 48x48
  else
    assert_output --partial "install ImageMagick"
    assert_equal "$(desktop_value "$APPS_DIR/fdwam-127-0-0.desktop" Icon)" applications-internet
  fi
}

@test "no icon links and no favicon.ico: generic icon, create succeeds" {
  run "$FDWAM" create "$BASE/noicon/index.html" brave --name NoIcon --id noicon -y
  assert_success
  # /favicon.ico exists at the server root, so hide it by using a path that 404s
  source_fdwam
  META_CANDIDATES=("4|0|favicon.ico|$BASE/does-not-exist.ico")
  ! icon_pick_best
}

@test "unreachable server: create succeeds with generic icon and host-derived name" {
  run "$FDWAM" create "http://127.0.0.1:1/" brave -y
  assert_success
  assert_output --partial "could not download"
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-127-0-0.desktop" Icon)" applications-internet
  assert_equal "$(desktop_value "$REG_DIR/127-0-0.conf" name)" "127 0 0"
}

@test "--icon URL downloads the icon" {
  run "$FDWAM" create https://example.com/ brave --name Example --icon "$BASE/manifest/touch.png" -y
  assert_success
  assert_equal "$(png_size "$ICON_DIR/example.png")" 180x180
}

@test "modify --refresh-icon downloads again" {
  run "$FDWAM" create "$BASE/touch/index.html" brave --name T --no-icon -y
  assert_success
  [[ ! -e "$ICON_DIR/127-0-0.png" ]]
  run "$FDWAM" modify 127-0-0 --refresh-icon
  assert_success
  assert_equal "$(png_size "$ICON_DIR/127-0-0.png")" 180x180
}

@test "image_type detects formats by magic bytes" {
  source_fdwam
  assert_equal "$(image_type "$FIXTURES_DIR/icons/icon.png")" png
  assert_equal "$(image_type "$FIXTURES_DIR/icons/favicon.ico")" ico
  assert_equal "$(image_type "$FIXTURES_DIR/icons/photo.jpg")" jpeg
  assert_equal "$(image_type "$FIXTURES_DIR/html/svg/logo.svg")" svg
  assert_equal "$(image_type "$FIXTURES_DIR/html/noicon/index.html")" unknown
}

@test "local ICO via --icon is converted or skipped depending on ImageMagick" {
  run "$FDWAM" create https://example.com/ brave --name Example --icon "$FIXTURES_DIR/icons/favicon.ico" -y
  if has_imagemagick; then
    assert_success
    assert_equal "$(png_size "$ICON_DIR/example.png")" 32x32
  else
    # an explicit --icon is never silently replaced by the generic icon
    assert_equal "$status" 1
    assert_output --partial "install ImageMagick"
    [[ ! -e "$REG_DIR/example.conf" ]]
  fi
}

@test "wget fallback works when curl is absent" {
  skip_without wget
  local nocurl="$T/nocurl"
  mkdir -p "$nocurl"
  for t in bash wget python3 sed grep tr head cat sort awk od mktemp mv cp rm mkdir chmod basename dirname readlink date tail cut ln touch id uname env; do
    p="$(command -v $t 2>/dev/null)" && ln -sf "$p" "$nocurl/$t"
  done
  PATH="$STUBS_DIR:$BIN:$nocurl" run "$FDWAM" create "$BASE/touch/index.html" brave -y
  assert_success
  assert_equal "$(png_size "$ICON_DIR/127-0-0.png")" 180x180
}

@test "create with an unreachable --icon URL exits 1 and writes nothing" {
  run "$FDWAM" create https://example.com/ brave --name Example --icon "http://127.0.0.1:1/x.png" -y
  assert_equal "$status" 1
  assert_output --partial "could not use icon 'http://127.0.0.1:1/x.png'"
  refute_output --partial "generic icon"
  refute_output --partial "rolling back"
  [[ ! -e "$APPS_DIR/fdwam-example.desktop" ]]
  [[ ! -e "$REG_DIR/example.conf" ]]
  [[ ! -e "$PROFILES_DIR/example" ]]
  [[ ! -e "$ICON_DIR/example.png" ]]
}

@test "--name with an --icon URL downloads only the icon, not the page" {
  local fake="$T/fakecurl" real
  real="$(command -v curl)"
  mkdir -p "$fake"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s"\nexec "%s" "$@"\n' "$T/curl.log" "$real" > "$fake/curl"
  chmod +x "$fake/curl"
  PATH="$fake:$PATH" run "$FDWAM" create "$BASE/noicon/index.html" brave --name N9 --id n9 --icon "$BASE/manifest/touch.png" -y
  assert_success
  refute_output --partial "Fetching site metadata"
  assert_equal "$(png_size "$ICON_DIR/n9.png")" 180x180
  assert_equal "$(wc -l < "$T/curl.log")" 1
  grep -q -- "$BASE/manifest/touch.png" "$T/curl.log"
}
