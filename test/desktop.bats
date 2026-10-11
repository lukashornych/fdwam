#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# .desktop generation: golden files per family x kind x ozone,
# Exec= quoting, compute_wm_class, desktop-file-validate, gio launch.

load test_helper

# --- golden files ------------------------------------------------------------
# All golden tests run offline: fixed https:// URL, --name and --no-icon.

golden_create() {
  # Usage: golden_create <golden-name> <create args...>
  local name="$1"; shift
  run "$FDWAM" create "$@" --no-icon -y
  assert_success
  local id
  id="$(printf '%s\n' "$output" | sed -n "s/^Created '\([^']*\)'.*/\1/p")"
  [[ -n "$id" ]]
  assert_golden "$APPS_DIR/fdwam-$id.desktop" "desktop-golden/$name.desktop"
  assert_golden "$REG_DIR/$id.conf" "registry-golden/$name.conf"
  validate_desktop "$APPS_DIR/fdwam-$id.desktop"
}

validate_desktop() {
  if command -v desktop-file-validate >/dev/null 2>&1; then
    run desktop-file-validate "$1"
    assert_success
  fi
}

@test "golden: brave native wayland (auto)" {
  golden_create brave-native-auto https://www.netflix.com/ brave --name Netflix
}

@test "golden: brave snap wayland (auto), profile inside snap common" {
  remove_fake_browser brave
  make_fake_snap brave
  golden_create brave-snap-auto https://www.netflix.com/ brave --name Netflix
  grep -q "user-data-dir=$HOME/snap/brave/common/fdwam-profiles/netflix" "$APPS_DIR/fdwam-netflix.desktop"
}

@test "golden: brave flatpak wayland (auto), profile inside flatpak data" {
  remove_fake_browser brave
  make_fake_flatpak system com.brave.Browser
  golden_create brave-flatpak-auto https://www.netflix.com/ brave --name Netflix
  grep -q "user-data-dir=$HOME/.var/app/com.brave.Browser/data/fdwam-profiles/netflix" "$APPS_DIR/fdwam-netflix.desktop"
}

@test "golden: chromium x11 mode uses --class and StartupWMClass=fdwam-<id>" {
  golden_create chromium-native-x11 https://www.netflix.com/ chromium --name Netflix --x11
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" StartupWMClass)" fdwam-netflix
}

@test "golden: chromium forced wayland" {
  golden_create chromium-native-wayland https://www.netflix.com/ chromium --name Netflix --wayland
}

@test "golden: chrome native, path and query in URL" {
  golden_create chrome-native-auto "https://netflix.com/browse?x=1#frag" chrome --name Netflix
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" StartupWMClass)" "chrome-netflix.com__browse-fdwam-netflix"
}

@test "golden: firefox native" {
  golden_create firefox-native https://www.netflix.com/ firefox --name Netflix
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" StartupWMClass)" fdwam-netflix
  [[ -f "$PROFILES_DIR/netflix/user.js" ]]
}

@test "golden: firefox snap" {
  remove_fake_browser firefox
  make_fake_snap firefox
  golden_create firefox-snap https://www.netflix.com/ firefox --name Netflix
}

@test "golden: firefox flatpak (user export)" {
  remove_fake_browser firefox
  make_fake_flatpak user org.mozilla.firefox
  golden_create firefox-flatpak https://www.netflix.com/ firefox --name Netflix
}

@test "golden: secondary browsers (vivaldi, edge, librewolf, floorp, waterfox, zen)" {
  golden_create vivaldi-native https://example.com/ vivaldi --name Example --id vivaldi-app
  golden_create edge-native https://example.com/ edge --name Example --id edge-app
  golden_create librewolf-native https://example.com/ librewolf --name Example --id librewolf-app
  golden_create floorp-native https://example.com/ floorp --name Example --id floorp-app
  golden_create waterfox-native https://example.com/ waterfox --name Example --id waterfox-app
  golden_create zen-native https://example.com/ zen --name Example --id zen-app
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-edge-app.desktop" StartupWMClass)" "msedge-example.com__-fdwam-edge-app"
}

@test "golden: epiphany" {
  golden_create epiphany-native https://example.com/ epiphany --name Example
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-example.desktop" StartupWMClass)" "org.gnome.Epiphany.WebApp_example"
  [[ -f "$PROFILES_DIR/org.gnome.Epiphany.WebApp_example/.app" ]]
  [[ -f "$PROFILES_DIR/org.gnome.Epiphany.WebApp_example/fdwam-example.desktop" ]]
}

@test "golden: falkon" {
  golden_create falkon-native https://example.com/ falkon --name Example
  [[ -L "$XDG_CONFIG_HOME/falkon/profiles/fdwam-example" ]]
  assert_equal "$(readlink "$XDG_CONFIG_HOME/falkon/profiles/fdwam-example")" "$PROFILES_DIR/example"
}

@test "golden: URL with %20, &, ;, quotes and extra flags" {
  golden_create special-chars 'https://example.com/a%20b/c?x=1&y=2;z=3&q="quoted"' brave --name 'Ex & "Co" 100%' --flags '--password-store=basic --enable-features="A,B" --lang="en US"' --category Office
  validate_desktop "$APPS_DIR/fdwam-example.desktop"
}

@test "golden: global flags from config and per-app flags" {
  write_config "flags.brave=--enable-wayland-ime --force-dark-mode"
  golden_create config-flags https://example.com/ brave --name Example --flags "--kiosk"
  grep -q -- '--enable-wayland-ime --force-dark-mode --kiosk --app=https://example.com/' "$APPS_DIR/fdwam-example.desktop"
}

# --- unit: quoting ------------------------------------------------------------

@test "desktop_exec_quote follows the Desktop Entry spec" {
  source_fdwam
  assert_equal "$(desktop_exec_quote plain)" 'plain'
  assert_equal "$(desktop_exec_quote '100%')" '100%%'
  assert_equal "$(desktop_exec_quote 'a b')" '"a b"'
  assert_equal "$(desktop_exec_quote 'say "hi"')" '"say \\"hi\\""'
  assert_equal "$(desktop_exec_quote '$HOME')" '"\\$HOME"'
  assert_equal "$(desktop_exec_quote 'back\slash')" '"back\\\\slash"'
  assert_equal "$(desktop_exec_quote 'tick`x`')" '"tick\\`x\\`"'
  assert_equal "$(desktop_exec_quote 'a&b;c')" '"a&b;c"'
  assert_equal "$(desktop_exec_quote '')" '""'
  assert_equal "$(desktop_exec_quote 'https://e.com/?a=b')" '"https://e.com/?a=b"'
}

# --- unit: wm_class -----------------------------------------------------------

@test "compute_wm_class matches the Brave 155 measurements" {
  source_fdwam
  assert_equal "$(compute_wm_class chromium brave auto https://www.netflix.com/ netflix)" "brave-www.netflix.com__-fdwam-netflix"
  assert_equal "$(compute_wm_class chromium brave wayland https://netflix.com/browse netflix)" "brave-netflix.com__browse-fdwam-netflix"
  assert_equal "$(compute_wm_class chromium brave auto 'https://Netflix.com:8443/a/b?x=1#y' n2)" "brave-netflix.com__a_b-fdwam-n2"
  assert_equal "$(compute_wm_class chromium brave x11 https://www.netflix.com/ netflix)" "fdwam-netflix"
  assert_equal "$(compute_wm_class chromium msedge auto https://example.com/ e)" "msedge-example.com__-fdwam-e"
  assert_equal "$(compute_wm_class firefox firefox auto https://example.com/ e)" "fdwam-e"
  assert_equal "$(compute_wm_class epiphany epiphany auto https://example.com/ e)" "org.gnome.Epiphany.WebApp_e"
  assert_equal "$(compute_wm_class falkon falkon auto https://example.com/ e)" "fdwam-e"
}

@test "default ozone mode follows the session type" {
  source_fdwam
  assert_equal "$(ozone_default)" auto
  assert_equal "$(XDG_SESSION_TYPE=x11 ozone_default)" x11
  assert_equal "$(XDG_SESSION_TYPE=wayland ozone_default)" auto
  assert_equal "$(DISPLAY=:0 ozone_default)" x11
  assert_equal "$(DISPLAY=:0 WAYLAND_DISPLAY=wayland-0 ozone_default)" auto
  assert_equal "$(FDWAM_OZONE=x11 ozone_default)" x11
  write_config "ozone_mode=wayland"; config_load
  assert_equal "$(ozone_default)" wayland
  write_config "ozone_mode=bogus"; config_load
  assert_equal "$(ozone_default 2>/dev/null)" auto
}

@test "x11 session makes x11 the default mode for the chromium family" {
  XDG_SESSION_TYPE=x11 run "$FDWAM" create https://www.netflix.com/ brave --name Netflix --no-icon -y
  assert_success
  assert_equal "$(desktop_value "$APPS_DIR/fdwam-netflix.desktop" StartupWMClass)" fdwam-netflix
  grep -q -- '--ozone-platform=x11 --class=fdwam-netflix' "$APPS_DIR/fdwam-netflix.desktop"
}

@test "url_normalize adds https, lower-cases host, rejects other schemes" {
  source_fdwam
  assert_equal "$(url_normalize netflix.com)" "https://netflix.com/"
  assert_equal "$(url_normalize 'HTTP://Example.COM/Path?Q=1')" "http://example.com/Path?Q=1"
  assert_equal "$(url_normalize ' https://x.org ')" "https://x.org/"
  ! url_normalize 'ftp://x.org/'
  ! url_normalize 'file:///etc/passwd'
  ! url_normalize 'not a url'
  ! url_normalize ''
}

@test "url_resolve handles absolute, protocol-relative, root-relative and relative refs" {
  source_fdwam
  local base="https://example.com/dir/page.html"
  assert_equal "$(url_resolve "$base" https://cdn.example/i.png)" https://cdn.example/i.png
  assert_equal "$(url_resolve "$base" //cdn.example/i.png)" https://cdn.example/i.png
  assert_equal "$(url_resolve "$base" /i.png)" https://example.com/i.png
  assert_equal "$(url_resolve "$base" i.png)" https://example.com/dir/i.png
  assert_equal "$(url_resolve https://example.com i.png)" https://example.com/i.png
}

# --- independent Exec= verification ------------------------------------------

@test "gio launch runs the generated Exec= with the expected argv" {
  skip_without gio
  run "$FDWAM" create 'https://example.com/a%20b/c?x=1&y=2;z=3&q="quoted"' brave --name 'Ex & "Co"' --flags '--lang="en US" --password-store=basic' --no-icon -y
  assert_success
  rm -f "$FDWAM_TEST_LOG"
  run gio launch "$APPS_DIR/fdwam-example.desktop"
  assert_success
  local i=0
  while [[ ! -s "$FDWAM_TEST_LOG" && $i -lt 50 ]]; do sleep 0.1; i=$((i + 1)); done
  run browser_log_args
  assert_line --index 0 "--user-data-dir=$PROFILES_DIR/example"
  assert_line --index 1 "--profile-directory=fdwam-example"
  assert_line --index 2 "--no-first-run"
  assert_line --index 3 "--no-default-browser-check"
  assert_line --index 4 "--ozone-platform-hint=auto"
  assert_line --index 5 "--lang=en US"
  assert_line --index 6 "--password-store=basic"
  assert_line --index 7 '--app=https://example.com/a%20b/c?x=1&y=2;z=3&q="quoted"'
  assert_equal "$(browser_log_args | wc -l)" 8
  assert_equal "$(browser_log_argv0)" "$BIN/brave"
}

@test "fdwam launch passes the same argv as Exec= (fallback parser check)" {
  run "$FDWAM" create 'https://example.com/a%20b/?x=1&y="q"' firefox --name 'Ex' --flags "--kiosk 'two words'" --no-icon -y
  assert_success
  run "$FDWAM" launch example
  assert_success
  run browser_log_args
  assert_line --index 0 "--no-remote"
  assert_line --index 1 "--profile"
  assert_line --index 2 "$PROFILES_DIR/example"
  assert_line --index 3 "--name"
  assert_line --index 4 "fdwam-example"
  assert_line --index 5 "--class"
  assert_line --index 6 "fdwam-example"
  assert_line --index 7 "--kiosk"
  assert_line --index 8 "two words"
  assert_line --index 9 'https://example.com/a%20b/?x=1&y="q"'
  # unquote the Exec= line with a tiny independent parser and compare
  source_fdwam
  local exec_line
  exec_line="$(desktop_value "$APPS_DIR/fdwam-example.desktop" Exec)"
  run exec_unquote "$exec_line"
  assert_line --index 0 "$BIN/firefox"
  assert_line --index 10 'https://example.com/a%20b/?x=1&y="q"'
}

# Minimal reverse parser of an Exec= value (spec 1.5): used only as a fallback
# where gio is missing. Prints one argument per line.
exec_unquote() {
  local s="$1" i c cur="" inq=0 out=()
  # step 1: undo generic string escaping (\\ -> \)
  s="$(printf '%s' "$s" | sed 's/\\\\/\\/g')"
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    if (( inq )); then
      if [[ "$c" == '\' ]]; then i=$((i + 1)); cur+="${s:i:1}"
      elif [[ "$c" == '"' ]]; then inq=0
      else cur+="$c"; fi
    elif [[ "$c" == '"' ]]; then inq=1
    elif [[ "$c" == ' ' ]]; then out+=("$cur"); cur=""
    else cur+="$c"; fi
  done
  out+=("$cur")
  printf '%s\n' "${out[@]//%%/%}"
}

@test "control characters never reach Exec= (defence in depth)" {
  source_fdwam
  APP=([id]=example [name]=Example [url]=https://example.com/ [browser]=brave [browser_exec]=/usr/bin/brave
       [family]=chromium [profile_dir]=/p [ozone]=auto [category]=Network [wm_class]=w [icon]=/i.png [flags]="")
  CFG[flags.brave]=$'--x\nIcon=/tmp/evil --y\001z'
  build_argv
  desktop_content > "$T/out.desktop"
  assert_equal "$(grep -c '^Icon=' "$T/out.desktop")" 1
  assert_equal "$(grep -c '^Exec=' "$T/out.desktop")" 1
  run grep -c '[[:cntrl:]]' "$T/out.desktop"
  assert_output 0
  # the newline is a word separator for split_flags, \001 is stripped
  grep -q -- '^Exec=.* --x Icon=/tmp/evil --yz --app=https://example.com/$' "$T/out.desktop"
  ARGV=(/usr/bin/brave $'--a\nIcon=/tmp/evil')
  assert_equal "$(desktop_exec_line)" '/usr/bin/brave --aIcon=/tmp/evil'
}
