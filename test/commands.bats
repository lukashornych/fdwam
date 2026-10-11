#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# End-to-end command scenarios over the fake browser.

load test_helper

@test "lifecycle: create -> list -> show -> launch -> modify -> regenerate -> delete" {
  create_offline https://www.netflix.com/ brave --name Netflix
  assert_output "Created 'netflix' -> $APPS_DIR/fdwam-netflix.desktop"

  run "$FDWAM" list
  assert_success
  assert_line --index 0 --regexp '^ID +NAME +BROWSER +URL$'
  assert_line --index 1 --regexp '^netflix +Netflix +brave +https://www.netflix.com/$'

  run "$FDWAM" list --long
  assert_success
  assert_output --partial "wm_class: brave-www.netflix.com__-fdwam-netflix"
  assert_output --partial "profile:  $PROFILES_DIR/netflix"

  run "$FDWAM" show netflix
  assert_success
  assert_line "id:           netflix"
  assert_line "browser_kind: native"
  assert_line "desktop:      $APPS_DIR/fdwam-netflix.desktop"
  assert_output --partial "exec:         $BIN/brave --user-data-dir="

  run "$FDWAM" launch netflix
  assert_success
  assert_equal "$(browser_log_argv0)" "$BIN/brave"
  run browser_log_args
  assert_line --index 0 "--user-data-dir=$PROFILES_DIR/netflix"
  assert_line --index 1 "--profile-directory=fdwam-netflix"
  assert_line --index 5 "--app=https://www.netflix.com/"

  run "$FDWAM" modify netflix --name "Netflix TV"
  assert_success
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" Name)" "Netflix TV"
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" name)" "Netflix TV"

  FDWAM_NOW=2026-10-12T00:00:00Z run "$FDWAM" modify netflix --url netflix.com/browse
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" url)" "https://netflix.com/browse"
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" StartupWMClass)" "brave-netflix.com__browse-fdwam-netflix"
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" modified)" "2026-10-12T00:00:00Z"
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" created)" "2026-10-11T10:00:00Z"

  run "$FDWAM" modify netflix --browser firefox -y
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" browser)" firefox
  assert_equal "$(desktop_value "$REG_DIR/netflix.conf" family)" firefox
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" StartupWMClass)" fdwam-netflix
  [[ -f "$PROFILES_DIR/netflix/user.js" ]]
  [[ ! -f "$PROFILES_DIR/netflix/First Run" ]]

  run "$FDWAM" modify netflix --category Office --flags "--kiosk" --x11
  assert_success
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" Categories)" "Office;"
  grep -q -- "--kiosk https://netflix.com/browse" "$APPS_DIR/fdwam-netflix.desktop"

  rm "$APPS_DIR/fdwam-netflix.desktop"
  run "$FDWAM" regenerate netflix
  assert_success
  assert_output "Regenerated 'netflix' -> $APPS_DIR/fdwam-netflix.desktop"
  [[ -f "$APPS_DIR/fdwam-netflix.desktop" ]]

  run "$FDWAM" delete netflix -y
  assert_success
  assert_output "Deleted 'netflix'"
  [[ ! -e "$APPS_DIR/fdwam-netflix.desktop" ]]
  [[ ! -e "$REG_DIR/netflix.conf" ]]
  [[ ! -e "$PROFILES_DIR/netflix" ]]
  run --separate-stderr "$FDWAM" list
  assert_success
  assert_output ""
  [[ "$stderr" == *"no web apps yet"* ]]
}

@test "create picks the default browser and derives name from the host" {
  remove_fake_browser brave
  remove_fake_browser google-chrome-stable
  run "$FDWAM" create mail.google.com --name "Gmail" --no-icon -y
  assert_success
  assert_output --partial "Created 'mail-google'"
  assert_equal "$(desktop_value "$REG_DIR/mail-google.conf" browser)" chromium
  # name derived from the slug when the network is unavailable
  run "$FDWAM" create https://app.slack.com/ --no-icon -y
  assert_success
  assert_equal "$(desktop_value "$REG_DIR/slack.conf" name)" "Slack"
}

@test "create without URL on a non-terminal exits 2" {
  run "$FDWAM" create </dev/null
  assert_equal "$status" 2
  assert_output --partial "missing <url>"
}

@test "create rejects invalid URL, category and too many arguments" {
  run "$FDWAM" create 'ftp://x.org' brave --name X --no-icon -y
  assert_equal "$status" 2
  run "$FDWAM" create https://x.org brave extra --name X --no-icon -y
  assert_equal "$status" 2
  run "$FDWAM" create https://x.org brave --name X --no-icon -y --category 'bad cat'
  assert_equal "$status" 2
  run "$FDWAM" create https://x.org brave --name X --no-icon -y --category 'Network;Office;'
  assert_success
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-x.desktop" Categories)" "Network;Office;"
}

@test "create with --icon local file installs it" {
  cp "$FIXTURES_DIR/icons/icon.png" "$T/my icon.png"
  run "$FDWAM" create https://example.com/ brave --name Example --icon "$T/my icon.png" -y
  assert_success
  [[ -f "$ICON_DIR/example.png" ]]
  cmp "$ICON_DIR/example.png" "$FIXTURES_DIR/icons/icon.png"
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-example.desktop" Icon)" "$ICON_DIR/example.png"
  run "$FDWAM" delete example -y
  [[ ! -e "$ICON_DIR/example.png" ]]
}

@test "create with --icon pointing to a missing file exits 2 and writes nothing" {
  run "$FDWAM" create https://example.com/ brave --name Example --icon "$T/nope.png" -y
  assert_equal "$status" 2
  assert_output --partial "icon file not found: $T/nope.png"
  refute_output --partial "generic icon"
  [[ ! -e "$APPS_DIR/fdwam-example.desktop" ]]
  [[ ! -e "$REG_DIR/example.conf" ]]
  [[ ! -e "$PROFILES_DIR/example" ]]
  create_offline https://example.com/ brave --name Example
  run "$FDWAM" modify example --icon "$T/nope.png"
  assert_equal "$status" 2
  assert_output --partial "icon file not found"
}

@test "create --launch starts the app" {
  run "$FDWAM" create https://example.com/ brave --name Example --no-icon -y --launch
  assert_success
  assert_equal "$(browser_log_argv0)" "$BIN/brave"
}

@test "create with a failure in the middle leaves nothing behind (rollback)" {
  [[ "$(id -u)" != 0 ]] || skip "rollback test needs a non-root user"
  mkdir -p "$APPS_DIR"
  chmod 0555 "$APPS_DIR"
  run "$FDWAM" create https://example.com/ falkon --name Example --no-icon -y
  chmod 0755 "$APPS_DIR"
  assert_failure
  assert_output --partial "rolling back"
  [[ ! -e "$REG_DIR/example.conf" ]]
  [[ ! -e "$PROFILES_DIR/example" ]]
  [[ ! -e "$APPS_DIR/fdwam-example.desktop" ]]
  [[ ! -L "$XDG_CONFIG_HOME/falkon/profiles/fdwam-example" ]]
  run --separate-stderr "$FDWAM" list
  assert_output ""
}

@test "rollback does not delete a pre-existing profile directory" {
  [[ "$(id -u)" != 0 ]] || skip "rollback test needs a non-root user"
  mkdir -p "$PROFILES_DIR/example"
  echo keep > "$PROFILES_DIR/example/cookies"
  mkdir -p "$APPS_DIR"
  chmod 0555 "$APPS_DIR"
  run "$FDWAM" create https://example.com/ brave --name Example --no-icon -y
  chmod 0755 "$APPS_DIR"
  assert_failure
  [[ -f "$PROFILES_DIR/example/cookies" ]]
}

@test "menu refresh tools are called after create, modify, regenerate and delete" {
  create_offline https://example.com/ brave --name Example
  run cat "$FDWAM_TEST_CALLS"
  assert_line "update-desktop-database $APPS_DIR"
  assert_line "kbuildsycoca6 "
  : > "$FDWAM_TEST_CALLS"
  run "$FDWAM" modify example --name Y
  grep -q kbuildsycoca6 "$FDWAM_TEST_CALLS"
  : > "$FDWAM_TEST_CALLS"
  run "$FDWAM" regenerate --all
  grep -q kbuildsycoca6 "$FDWAM_TEST_CALLS"
  : > "$FDWAM_TEST_CALLS"
  run "$FDWAM" delete example -y
  grep -q update-desktop-database "$FDWAM_TEST_CALLS"
}

@test "regenerate --all re-detects the binary and applies config changes" {
  create_offline https://example.com/ brave --name Example
  create_offline https://other.example/ firefox --name Other
  # brave moved: brave -> brave-browser
  remove_fake_browser brave
  ln -s "$STUBS_DIR/fake-browser" "$BIN/brave-browser"
  write_config "flags.firefox=--kiosk"
  run "$FDWAM" regenerate --all
  assert_success
  assert_line "Regenerated 'example' -> $APPS_DIR/fdwam-example.desktop"
  assert_line "Regenerated 'other' -> $APPS_DIR/fdwam-other.desktop"
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser_exec)" "$BIN/brave-browser"
  grep -q "^Exec=$BIN/brave-browser " "$APPS_DIR/fdwam-example.desktop"
  grep -q -- "--kiosk https://other.example/" "$APPS_DIR/fdwam-other.desktop"
}

@test "regenerate keeps the stored binary and warns when the browser is gone" {
  create_offline https://example.com/ brave --name Example
  remove_fake_browser brave
  run "$FDWAM" regenerate example
  assert_success
  assert_output --partial "not found, keeping"
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser_exec)" "$BIN/brave"
}

@test "regenerate warns when the installation kind changed" {
  create_offline https://example.com/ brave --name Example
  remove_fake_browser brave
  make_fake_snap brave
  run "$FDWAM" regenerate example
  assert_success
  assert_output --partial "now installed as snap"
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser_kind)" snap
}

@test "modify --browser keeps the old profile with --keep-profile or without confirmation" {
  create_offline https://example.com/ brave --name Example
  echo cookie > "$PROFILES_DIR/example/Cookies"
  run "$FDWAM" modify example --browser firefox --keep-profile
  assert_success
  assert_output --partial "old profile kept"
  # same path for native browsers: the old profile is moved aside, the new one is a firefox profile
  [[ -f "$PROFILES_DIR/example/user.js" ]]
  [[ ! -e "$PROFILES_DIR/example/Cookies" ]]
  compgen -G "$PROFILES_DIR/example.*/Cookies" >/dev/null
  run "$FDWAM" modify example --browser falkon </dev/null
  assert_success
  assert_output --partial "old profile kept"
  [[ -L "$XDG_CONFIG_HOME/falkon/profiles/fdwam-example" ]]
  # same browser again: nothing happens to the profile
  run "$FDWAM" modify example --browser falkon -y
  assert_success
  refute_output --partial "profile"
}

@test "modify --browser to a snap browser moves the profile and deletes the old one with -y" {
  create_offline https://example.com/ brave --name Example
  make_fake_snap chromium
  remove_fake_browser chromium
  run "$FDWAM" modify example --browser chromium -y
  assert_success
  [[ ! -e "$PROFILES_DIR/example" ]]
  [[ -f "$HOME/snap/chromium/common/fdwam-profiles/example/First Run" ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser_kind)" snap
}

@test "modify --no-icon removes the icon, --icon sets a new one" {
  cp "$FIXTURES_DIR/icons/icon.png" "$T/a.png"
  cp "$FIXTURES_DIR/icons/big.png" "$T/b.png"
  run "$FDWAM" create https://example.com/ brave --name Example --icon "$T/a.png" -y
  assert_success
  run "$FDWAM" modify example --icon "$T/b.png"
  assert_success
  cmp "$ICON_DIR/example.png" "$T/b.png"
  run "$FDWAM" modify example --no-icon
  assert_success
  [[ ! -e "$ICON_DIR/example.png" ]]
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-example.desktop" Icon)" applications-internet
}

@test "modify without options on a non-terminal exits 2" {
  create_offline https://example.com/ brave --name Example
  run "$FDWAM" modify example </dev/null
  assert_equal "$status" 2
}

@test "launch --browser-mode opens the URL in a normal window on the app profile" {
  create_offline https://www.netflix.com/ brave --name Netflix --flags "--lang=cs"
  run "$FDWAM" launch netflix --browser-mode
  assert_success
  run browser_log_args
  assert_line --index 0 "--user-data-dir=$PROFILES_DIR/netflix"
  assert_line --index 1 "--profile-directory=fdwam-netflix"
  assert_line --index 5 "--lang=cs"
  assert_line --index 6 "https://www.netflix.com/"
  refute_output --partial -- "--app="
  # -b before the id is accepted too
  run "$FDWAM" launch -b netflix
  assert_success
}

@test "launch --browser-mode is refused for firefox and epiphany, usage errors exit 2" {
  create_offline https://example.com/ firefox --name Example
  run "$FDWAM" launch example --browser-mode
  assert_equal "$status" 1
  assert_output --partial "hover the top edge"
  [[ ! -s "$FDWAM_TEST_LOG" ]]
  run "$FDWAM" launch example --bogus
  assert_equal "$status" 2
  run "$FDWAM" launch example other
  assert_equal "$status" 2
  run "$FDWAM" launch --browser-mode
  assert_equal "$status" 2
}

@test "launch with a missing binary exits 4" {
  create_offline https://example.com/ brave --name Example
  remove_fake_browser brave
  run "$FDWAM" launch example
  assert_equal "$status" 4
  assert_output --partial "browser executable not found"
}

@test "doctor reports OK for a healthy setup and problems for a broken one" {
  create_offline https://example.com/ brave --name Example
  run "$FDWAM" doctor
  assert_success
  assert_output --partial "== Result: OK"
  assert_output --partial "wm_class: brave-example.com__-fdwam-example"
  remove_fake_browser brave
  rm "$APPS_DIR/fdwam-example.desktop"
  printf '[Desktop Entry]\nType=Application\nName=Orphan\nExec=true\nX-Fdwam-Id=ghost\n' > "$APPS_DIR/fdwam-ghost.desktop"
  run "$FDWAM" doctor
  assert_equal "$status" 1
  assert_output --partial "browser executable missing"
  assert_output --partial ".desktop missing or foreign"
  assert_output --partial "orphan .desktop"
  assert_output --partial "== Result: problems found"
}

@test "doctor prints the KDE hint on Plasma" {
  XDG_CURRENT_DESKTOP=KDE run "$FDWAM" doctor
  assert_success
  assert_output --partial "queryWindowInfo"
}

@test "NO_COLOR and non-tty stderr produce no escape sequences" {
  run "$FDWAM" show nope
  refute_output --partial $'\033['
}

# --- regressions ---------------------------------------------------------------

@test "modify --browser with an unusable --icon fails before touching the profile" {
  create_offline https://example.com/ brave --name Example
  echo cookie > "$PROFILES_DIR/example/Cookies"
  run "$FDWAM" modify example --browser firefox --icon "$T/nope.png" -y
  assert_failure
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser)" brave
  [[ -f "$PROFILES_DIR/example/Cookies" ]]
  [[ ! -e "$PROFILES_DIR/example/user.js" ]]
  run compgen -G "$PROFILES_DIR/example.*"
  assert_failure
}

@test "modify --icon with a missing file changes nothing" {
  cp "$FIXTURES_DIR/icons/icon.png" "$T/a.png"
  run "$FDWAM" create https://example.com/ brave --name Example --icon "$T/a.png" -y
  assert_success
  cp "$REG_DIR/example.conf" "$T/before.conf"
  run "$FDWAM" modify example --icon "$T/nope.png"
  assert_failure
  cmp "$REG_DIR/example.conf" "$T/before.conf"
  cmp "$ICON_DIR/example.png" "$T/a.png"
}

@test "create --icon --launch leaves no temp directory behind" {
  mkdir -p "$T/tmp"
  cp "$FIXTURES_DIR/icons/icon.png" "$T/a.png"
  TMPDIR="$T/tmp" run "$FDWAM" create https://example.com/ brave --name Example --icon "$T/a.png" -y --launch
  assert_success
  assert_equal "$(browser_log_argv0)" "$BIN/brave"
  assert_equal "$(ls -A "$T/tmp")" ""
}

@test "modify --icon leaves no temp directory behind" {
  mkdir -p "$T/tmp"
  cp "$FIXTURES_DIR/icons/icon.png" "$T/a.png"
  create_offline https://example.com/ brave --name Example
  TMPDIR="$T/tmp" run "$FDWAM" modify example --icon "$T/a.png"
  assert_success
  cmp "$ICON_DIR/example.png" "$T/a.png"
  assert_equal "$(ls -A "$T/tmp")" ""
}

@test "create --id refuses to overwrite a foreign .desktop file" {
  mkdir -p "$APPS_DIR"
  printf '[Desktop Entry]\nType=Application\nName=Mine\nExec=true\n' > "$APPS_DIR/fdwam-mine.desktop"
  cp "$APPS_DIR/fdwam-mine.desktop" "$T/before.desktop"
  run "$FDWAM" create https://example.com/ brave --name X --no-icon -y --id mine
  assert_equal "$status" 2
  assert_output --partial "already exists"
  cmp "$APPS_DIR/fdwam-mine.desktop" "$T/before.desktop"
  [[ ! -e "$REG_DIR/mine.conf" ]]
  [[ ! -e "$PROFILES_DIR/mine" ]]
}

@test "rollback never removes files that existed before create" {
  [[ "$(id -u)" != 0 ]] || skip "rollback test needs a non-root user"
  mkdir -p "$APPS_DIR" "$ICON_DIR" "$REG_DIR"
  printf '[Desktop Entry]\nType=Application\nName=Mine\nExec=true\n' > "$APPS_DIR/fdwam-mine.desktop"
  echo foreign > "$ICON_DIR/mine.svg"
  # registry_write fails -> the EXIT trap rolls back
  chmod 0555 "$REG_DIR"
  run bash -c '
    source "$1"
    set -Eeuo pipefail
    shopt -s extglob nullglob inherit_errexit
    install_traps
    config_load
    W=([url]=https://example.com/ [browser]=brave [id]=mine [name]=X [icon]=- [category]=Network [ozone]=auto [flags]=)
    browser_resolve brave
    create_commit
  ' _ "$FDWAM"
  chmod 0755 "$REG_DIR"
  assert_failure
  assert_output --partial "rolling back"
  [[ -f "$APPS_DIR/fdwam-mine.desktop" ]]
  grep -q '^Name=Mine$' "$APPS_DIR/fdwam-mine.desktop"
  [[ -f "$ICON_DIR/mine.svg" ]]
  [[ ! -e "$PROFILES_DIR/mine" ]]
}
