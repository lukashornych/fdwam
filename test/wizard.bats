#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Interactive wizard. Answers are fed through stdin with
# FDWAM_FORCE_INTERACTIVE=1; one smoke test uses a real PTY via script(1).

load test_helper

setup() {
  fdwam_setup
  export FDWAM_FORCE_INTERACTIVE=1
}

# Runs the wizard with the given answers (one per argument; "" = Enter).
wizard() {
  local input="" a
  for a in "$@"; do input+="$a"$'\n'; done
  run --separate-stderr "$FDWAM" create <<< "$input"
}

@test "all defaults: Enter everywhere creates the app" {
  # URL is mandatory, everything else defaults; network is unavailable -> generic icon.
  wizard "www.netflix.com" "" "" "" "" "" "" "" "" ""
  assert_success
  assert_output "Created 'netflix' -> $APPS_DIR/fdwam-netflix.desktop"
  [[ "$stderr" == *"URL: "* ]]
  [[ "$stderr" == *"Browser:"* ]]
  [[ "$stderr" == *"1) brave"* ]]
  [[ "$stderr" == *"Name [Netflix]: "* ]]
  [[ "$stderr" == *"ID [netflix]: "* ]]
  [[ "$stderr" == *"Category (AudioVideo, Development, Education, Game, Graphics, Network, Office, Science, Settings, System, Utility) [Network]: "* ]]
  [[ "$stderr" == *"Icon:"* ]]
  [[ "$stderr" == *"Window mode (auto, wayland, x11) [auto]: "* ]]
  [[ "$stderr" == *"Extra browser flags []: "* ]]
  [[ "$stderr" == *"Create? [Y/n/e]: "* ]]
  [[ "$stderr" == *"Launch now? [y/N]:"* ]]
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" browser)" brave
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" category)" Network
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" StartupWMClass)" "brave-www.netflix.com__-fdwam-netflix"
  [[ ! -s "$FDWAM_TEST_LOG" ]]
}

@test "browser can be chosen by number and by name; non-installed browsers are not listed" {
  remove_fake_browser google-chrome-stable
  wizard "example.com" "2" "" "" "" "" "" "" "y" ""
  assert_success
  [[ "$stderr" != *"chrome "* ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser)" chromium
  wizard "example.org" "firefox" "" "" "" "" "" "" "" ""
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/example-2.conf" browser)" firefox
  [[ "$stderr" != *"Window mode"* ]]
}

@test "secondary browsers are marked best effort" {
  wizard "example.com" "" "" "" "" "" "" "" "n"
  [[ "$stderr" == *"falkon     (native, best effort)"* ]]
}

@test "invalid URL and category are asked again" {
  wizard "ftp://nope" "" "example.com" "" "" "" "sports" "4" "" "" "" "" ""
  assert_success
  [[ "$stderr" == *"invalid URL 'ftp://nope'"* ]]
  [[ "$stderr" == *"'sports' is not a main category"* ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" category)" Game
}

@test "empty URL is asked again" {
  wizard "" "example.com" "" "" "" "" "" "" "" "" ""
  assert_success
  [[ "$stderr" == *"a value is required"* ]]
}

@test "category accepts a name case-insensitively" {
  wizard "example.com" "" "" "" "audiovideo" "" "" "" "" ""
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/example.conf" category)" AudioVideo
}

@test "colliding ID is rejected and asked again; default is already unique" {
  create_offline https://example.com/ brave --name One
  wizard "example.com" "" "" "example" "example-9" "" "" "" "" "" ""
  assert_success
  [[ "$stderr" == *"id 'example' already exists"* ]]
  [[ "$stderr" == *"ID [example-2]: "* ]]
  [[ -f "$REG_DIR/example-9.conf" ]]
}

@test "n in the summary writes nothing" {
  wizard "example.com" "" "" "" "" "" "" "" "n"
  assert_success
  [[ "$stderr" == *"not created"* ]]
  [[ ! -e "$REG_DIR/example.conf" ]]
  [[ ! -e "$APPS_DIR/fdwam-example.desktop" ]]
  [[ ! -e "$PROFILES_DIR/example" ]]
}

@test "EOF in the middle writes nothing and exits 1" {
  wizard "example.com" "" "My App"
  assert_equal "$status" 1
  [[ "$stderr" == *"aborted, nothing was written"* ]]
  [[ ! -e "$REG_DIR" ]]
  [[ ! -e "$APPS_DIR" ]]
  [[ ! -e "$PROFILES_DIR" ]]
}

@test "e in the summary returns to a step" {
  wizard "example.com" "" "" "" "" "" "" "" "e" "3" "Renamed" "" ""
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/example.conf" name)" Renamed
  [[ "$stderr" == *"Edit step (1 URL, 2 browser"* ]]
}

@test "summary shows the values and the Exec line" {
  wizard "example.com" "" "" "" "" "" "" "--kiosk" "n"
  [[ "$stderr" == *"  Name      Example"* ]]
  [[ "$stderr" == *"  ID        example"* ]]
  [[ "$stderr" == *"  Browser   brave ($BIN/brave, native)"* ]]
  [[ "$stderr" == *"  Flags     --kiosk"* ]]
  [[ "$stderr" == *"  Exec      $BIN/brave --user-data-dir="* ]]
  [[ "$stderr" == *"--kiosk --app=https://example.com/"* ]]
}

@test "Launch now? y starts the app" {
  wizard "example.com" "" "" "" "" "" "" "" "" "y"
  assert_success
  assert_equal "$(browser_log_argv0)" "$BIN/brave"
}

@test "arguments skip the corresponding steps; -i pre-fills" {
  run --separate-stderr "$FDWAM" create https://example.com/ firefox --name Fixed --category Office -i <<< $'\n\n\n\n'
  assert_success
  [[ "$stderr" != *"URL: "* ]]
  [[ "$stderr" != *"Browser:"* ]]
  [[ "$stderr" != *"Name ["* ]]
  [[ "$stderr" != *"Category ("* ]]
  [[ "$stderr" == *"ID [example]: "* ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" name)" Fixed
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser)" firefox
}

@test "-y with arguments never asks" {
  run --separate-stderr "$FDWAM" create example.com brave --category AudioVideo -y </dev/null
  assert_success
  [[ "$stderr" != *"Create?"* ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" category)" AudioVideo
}

@test "create without URL and without a terminal exits 2" {
  unset FDWAM_FORCE_INTERACTIVE
  run "$FDWAM" create </dev/null
  assert_equal "$status" 2
}

@test "icon step lists candidates and allows a custom path" {
  cp "$FIXTURES_DIR/icons/icon.png" "$T/custom.png"
  # no network: only the /favicon.ico guess, "custom path or URL" and "generic icon" are offered
  wizard "example.com" "" "" "" "" "2" "$T/custom.png" "" "" "" ""
  assert_success
  [[ "$stderr" == *"1) favicon.ico (https://example.com/favicon.ico)"* ]]
  [[ "$stderr" == *"2) custom path or URL"* ]]
  [[ "$stderr" == *"3) generic icon"* ]]
  [[ "$stderr" == *"Choose [1]: "* ]]
  cmp "$ICON_DIR/example.png" "$T/custom.png"
}

@test "modify wizard changes only the edited values" {
  create_offline https://example.com/ brave --name Example --category Office --flags "--kiosk"
  run --separate-stderr "$FDWAM" modify example <<< $'\n\nNew Name\n\n\n\n\n\n'
  assert_success
  [[ "$stderr" == *"URL [https://example.com/]: "* ]]
  [[ "$stderr" == *"Name [Example]: "* ]]
  [[ "$stderr" == *"Category ("*"[Office]: "* ]]
  [[ "$stderr" == *"1) keep current icon"* ]] || [[ "$stderr" == *"generic icon"* ]]
  [[ "$stderr" == *"Extra browser flags [--kiosk]: "* ]]
  [[ "$stderr" == *"Save changes? [Y/n/e]:"* ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" name)" "New Name"
  assert_equal "$(desktop_value "$REG_DIR/example.conf" category)" Office
  assert_equal "$(desktop_value "$REG_DIR/example.conf" flags)" "--kiosk"
  assert_equal "$(desktop_value "$REG_DIR/example.conf" url)" "https://example.com/"
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser)" brave
}

@test "modify wizard: all Enters change nothing, '-' clears the flags" {
  create_offline https://example.com/ brave --name Example --flags "--kiosk"
  run --separate-stderr "$FDWAM" modify example <<< $'\n\n\n\n\n\n\n\n'
  assert_success
  [[ "$stderr" == *"nothing changed"* ]]
  run --separate-stderr "$FDWAM" modify example <<< $'\n\n\n\n\n\n-\n\n'
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/example.conf" flags)" ""
}

@test "modify wizard: n saves nothing" {
  create_offline https://example.com/ brave --name Example
  run --separate-stderr "$FDWAM" modify example <<< $'\n\nChanged\n\n\n\n\nn\n'
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/example.conf" name)" Example
}

# --- PTY smoke test ----------------------------------------------------------
# Exercises readline (read -e -i) which the stdin tests cannot reach.

pty_modify() {
  # Usage: pty_modify <id> <keystroke-line>...  Each line is sent with a short
  # delay so that readline is already waiting when the keys arrive (otherwise
  # the tty line discipline would process Ctrl+U before readline starts).
  local id="$1"; shift
  local lines=("$@")
  (
    sleep 0.5
    for l in "${lines[@]}"; do printf '%b\n' "$l"; sleep 0.3; done
    sleep 0.5
  ) | script -qec "FDWAM_FORCE_INTERACTIVE=1 '$FDWAM' modify $id" /dev/null
}

@test "PTY: modify with Enter keeps values; Ctrl+U replaces a pre-filled value" {
  skip_without script
  create_offline https://example.com/ brave --name Example --flags "--kiosk"
  run pty_modify example '' '' '' '' '' '' '' ''
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/example.conf" name)" Example
  assert_equal "$(desktop_value "$REG_DIR/example.conf" flags)" "--kiosk"
  # URL Enter, browser Enter, name: Ctrl+U + new value, then Enters, confirm
  run pty_modify example '' '' '\x15Replaced' '' '' '' '' ''
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/example.conf" name)" Replaced
  assert_equal "$(desktop_value "$REG_DIR/example.conf" flags)" "--kiosk"
}
