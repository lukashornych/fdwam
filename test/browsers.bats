#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Browser detection (native -> snap -> flatpak), shim detection,
# overrides, unresolved paths in Exec=, missing browsers.

load test_helper

@test "browsers lists all 12 enum values with family and support" {
  run "$FDWAM" browsers --porcelain
  assert_success
  assert_equal "${#lines[@]}" 12
  assert_line --index 0 --regexp '^brave[|]chromium[|]primary[|]native[|].*/bin/brave[|]KDE Neon'
  for b in brave chrome chromium firefox vivaldi edge librewolf floorp waterfox zen epiphany falkon; do
    assert_line --regexp "^$b[|]"
  done
  assert_line --regexp '^chrome[|]chromium[|]primary[|]native[|]'
  assert_line --regexp '^firefox[|]firefox[|]primary[|]native[|]'
  assert_line --regexp '^edge[|]chromium[|]secondary[|]'
  assert_line --regexp '^epiphany[|]epiphany[|]secondary[|]'
  assert_line --regexp '^falkon[|]falkon[|]secondary[|]'
}

@test "browsers marks only brave and firefox as verified" {
  run "$FDWAM" browsers --porcelain
  verified=$(printf '%s\n' "${lines[@]}" | awk -F'|' '$6 != "" {print $1}')
  assert_equal "$verified" "$(printf 'brave\nfirefox')"
}

@test "browsers table shows (not found) for missing browsers" {
  remove_all_fake_browsers
  run "$FDWAM" browsers
  assert_success
  assert_output --partial "BROWSER"
  assert_output --regexp 'brave +chromium +primary +- +\(not found\)'
}

@test "native candidates are tried in table order" {
  remove_fake_browser brave
  ln -s "$STUBS_DIR/fake-browser" "$BIN/brave-browser-stable"
  source_fdwam
  browser_resolve brave
  assert_equal "$BR_KIND" native
  assert_equal "$BR_EXEC" "$BIN/brave-browser-stable"
  # brave-browser (earlier in the table) wins over brave-browser-stable
  ln -s "$STUBS_DIR/fake-browser" "$BIN/brave-browser"
  browser_resolve brave
  assert_equal "$BR_EXEC" "$BIN/brave-browser"
}

@test "priority: native before snap before flatpak" {
  make_fake_snap chromium
  make_fake_flatpak system org.chromium.Chromium
  source_fdwam
  browser_resolve chromium
  assert_equal "$BR_KIND" native
  remove_fake_browser chromium
  browser_resolve chromium
  assert_equal "$BR_KIND" snap
  assert_equal "$BR_EXEC" "$SNAP_ROOT/bin/chromium"
  assert_equal "$BR_SNAP_NAME" chromium
  rm "$SNAP_ROOT/bin/chromium"
  browser_resolve chromium
  assert_equal "$BR_KIND" flatpak
  assert_equal "$BR_EXEC" "$FLATPAK_ROOT/system/org.chromium.Chromium"
  assert_equal "$BR_FLATPAK_ID" org.chromium.Chromium
}

@test "flatpak: system export wins over user export" {
  remove_fake_browser brave
  make_fake_flatpak user com.brave.Browser
  source_fdwam
  browser_resolve brave
  assert_equal "$BR_KIND" flatpak
  assert_equal "$BR_EXEC" "$FLATPAK_ROOT/user/com.brave.Browser"
  make_fake_flatpak system com.brave.Browser
  browser_resolve brave
  assert_equal "$BR_EXEC" "$FLATPAK_ROOT/system/com.brave.Browser"
}

@test "snap shim: symlink in PATH into the snap prefix is classified as snap, Exec keeps the unresolved path" {
  remove_fake_browser brave
  make_fake_snap brave
  # Ubuntu style: /usr/bin/brave -> /snap/bin/brave (resolves under the snap prefix)
  ln -s "$SNAP_ROOT/bin/brave" "$BIN/brave"
  source_fdwam
  browser_resolve brave
  assert_equal "$BR_KIND" snap
  assert_equal "$BR_SNAP_NAME" brave
  assert_equal "$BR_EXEC" "$BIN/brave"
  # the fake browser must be started under its original name, not the resolved one
  run "$FDWAM" create https://example.com/ brave --name Example --no-icon -y
  assert_success
  run "$FDWAM" launch example
  assert_success
  assert_equal "$(browser_log_argv0)" "$BIN/brave"
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-example.desktop" Exec | cut -d' ' -f1)" "$BIN/brave"
}

@test "snap shim: shell script wrapper containing /snap/bin/ is classified as snap" {
  remove_fake_browser chromium
  make_fake_snap chromium
  cat > "$BIN/chromium-browser" <<SH
#!/bin/sh
# transitional package shim
exec $SNAP_ROOT/bin/chromium "\$@"
SH
  chmod +x "$BIN/chromium-browser"
  source_fdwam
  browser_resolve chromium
  assert_equal "$BR_KIND" snap
  assert_equal "$BR_SNAP_NAME" chromium
  assert_equal "$BR_EXEC" "$BIN/chromium-browser"
}

@test "snap shim: symlink to the snap launcher binary is classified as snap" {
  remove_fake_browser firefox
  mkdir -p "$T/usrbin"
  cp "$STUBS_DIR/fake-browser" "$T/usrbin/snap"
  ln -s "$T/usrbin/snap" "$SNAP_ROOT/bin/firefox"
  ln -s "$SNAP_ROOT/bin/firefox" "$BIN/firefox"
  source_fdwam
  browser_resolve firefox
  assert_equal "$BR_KIND" snap
  assert_equal "$BR_SNAP_NAME" firefox
  assert_equal "$BR_EXEC" "$BIN/firefox"
}

@test "snap name derives from /snap/bin/<snap>.<app>" {
  source_fdwam
  assert_equal "$(snap_name_from_bin "$SNAP_ROOT/bin/brave.foo")" brave
  assert_equal "$(snap_name_from_bin "$SNAP_ROOT/bin/chromium")" chromium
}

@test "override via environment variable" {
  mkdir -p "$T/opt"
  cp "$STUBS_DIR/fake-browser" "$T/opt/my-brave"
  FDWAM_BROWSER_BRAVE="$T/opt/my-brave" run "$FDWAM" browsers --porcelain
  assert_success
  assert_line --index 0 "brave|chromium|primary|native|$T/opt/my-brave|KDE Neon, Plasma 6.6.6, Wayland, Brave 155 snap, 2026-10-11"
}

@test "override via config file" {
  mkdir -p "$T/opt"
  cp "$STUBS_DIR/fake-browser" "$T/opt/cfg-chrome"
  write_config "browser.chrome=$T/opt/cfg-chrome"
  run "$FDWAM" browsers --porcelain
  assert_output --partial "chrome|chromium|primary|native|$T/opt/cfg-chrome|"
}

@test "override pointing to a missing file exits 4" {
  FDWAM_BROWSER_BRAVE="$T/nope" run "$FDWAM" create https://example.com/ brave --name X --no-icon -y
  assert_equal "$status" 4
  assert_output --partial "not executable"
}

@test "missing browser exits 4 with a helpful message" {
  remove_fake_browser brave
  run "$FDWAM" create https://example.com/ brave --name X --no-icon -y
  assert_equal "$status" 4
  assert_output --partial "browser 'brave' not found"
  assert_output --partial "brave-browser"
}

@test "no browser at all exits 4" {
  remove_all_fake_browsers
  run "$FDWAM" create https://example.com/ --name X --no-icon -y
  assert_equal "$status" 4
  assert_output --partial "no supported browser found"
}

@test "unknown browser enum exits 2" {
  run "$FDWAM" create https://example.com/ opera --name X --no-icon -y
  assert_equal "$status" 2
  assert_output --partial "unknown browser 'opera'"
}

@test "flatpak epiphany is refused" {
  remove_fake_browser epiphany
  make_fake_flatpak system org.gnome.Epiphany
  run "$FDWAM" create https://example.com/ epiphany --name X --no-icon -y
  assert_equal "$status" 4
  assert_output --partial "flatpak Epiphany"
}

@test "default browser: first installed primary browser in enum order, config overrides" {
  remove_fake_browser brave
  remove_fake_browser google-chrome-stable
  source_fdwam
  browser_default
  assert_equal "$BR_ENUM" chromium
  remove_fake_browser chromium
  remove_fake_browser firefox
  browser_default
  assert_equal "$BR_ENUM" vivaldi
  write_config "default_browser=falkon"
  config_load
  browser_default
  assert_equal "$BR_ENUM" falkon
}

@test "snap name follows the whole symlink chain (alternatives -> /snap/bin/<snap> -> snap)" {
  remove_fake_browser brave
  mkdir -p "$T/usrbin" "$T/alternatives"
  cp "$STUBS_DIR/fake-browser" "$T/usrbin/snap"
  ln -s "$T/usrbin/snap" "$SNAP_ROOT/bin/brave"
  ln -s "$SNAP_ROOT/bin/brave" "$T/alternatives/brave-browser"
  ln -s "$T/alternatives/brave-browser" "$BIN/brave-browser"
  source_fdwam
  browser_resolve brave
  assert_equal "$BR_KIND" snap
  assert_equal "$BR_SNAP_NAME" brave
  assert_equal "$BR_EXEC" "$BIN/brave-browser"
  profile_locate example
  assert_equal "$PROFILE_PATH" "$HOME/snap/brave/common/fdwam-profiles/example"
  # relative link targets are resolved against the directory of the link
  rm "$BIN/brave-browser"
  ln -s "../alternatives/brave-browser" "$BIN/brave-browser"
  browser_resolve brave
  assert_equal "$BR_SNAP_NAME" brave
  # snapd alias: /snap/bin/<alias> -> <snap>.<app> uses the target name
  ln -s brave.browser "$SNAP_ROOT/bin/bravo"
  assert_equal "$(snap_name_from_bin "$SNAP_ROOT/bin/bravo")" brave
}
