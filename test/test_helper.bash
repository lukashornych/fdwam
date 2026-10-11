# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
#
# Hermetic test environment for fdwam. Loaded by every .bats file via
# `load test_helper`. Each test gets its own HOME, XDG dirs, fake browsers,
# fake snap/flatpak roots and stubbed menu tools in $BATS_TEST_TMPDIR.

bats_require_minimum_version 1.5.0

load 'bats-support/load'
load 'bats-assert/load'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FDWAM="$REPO_ROOT/bin/fdwam"
STUBS_DIR="$REPO_ROOT/test/stubs"
FIXTURES_DIR="$REPO_ROOT/test/fixtures"

# Browser names that get a fake binary in $BIN for every test.
FAKE_NATIVE_BROWSERS=(brave google-chrome-stable chromium firefox vivaldi-stable microsoft-edge-stable librewolf floorp waterfox zen-browser epiphany falkon)

# Builds the hermetic environment. Called from setup().
fdwam_setup() {
  # Nothing from the developer's environment may leak in (the golden-update
  # switch is the only FDWAM_* variable that survives).
  local update_golden="${FDWAM_UPDATE_GOLDEN:-0}"
  unset "${!FDWAM_@}"
  export FDWAM_UPDATE_GOLDEN="$update_golden"
  unset XDG_SESSION_TYPE WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS
  export LC_ALL=C.UTF-8 TZ=UTC NO_COLOR=1

  T="$BATS_TEST_TMPDIR"
  # The developer's real HOME, needed to filter PATH below.
  ORIG_HOME="$HOME"
  export HOME="$T/home"
  export XDG_DATA_HOME="$T/data"
  export XDG_CONFIG_HOME="$T/config"
  export XDG_CACHE_HOME="$T/cache"
  export XDG_STATE_HOME="$T/state"
  export XDG_RUNTIME_DIR="$T/runtime"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
  mkdir -p "$XDG_RUNTIME_DIR" && chmod 0700 "$XDG_RUNTIME_DIR"

  # Fake browsers and stubs come first in PATH; the system tools stay available.
  BIN="$T/bin"
  mkdir -p "$BIN"
  local name
  for name in "${FAKE_NATIVE_BROWSERS[@]}"; do
    ln -s "$STUBS_DIR/fake-browser" "$BIN/$name"
  done
  SYSTEM_PATH="$(system_path_without_browsers)"
  export PATH="$STUBS_DIR:$BIN:$SYSTEM_PATH"

  # Fake sandbox roots (empty by default; tests populate them).
  SNAP_ROOT="$T/snap"
  FLATPAK_ROOT="$T/flatpak"
  mkdir -p "$SNAP_ROOT/bin" "$FLATPAK_ROOT/system" "$FLATPAK_ROOT/user"
  export FDWAM_SNAP_BIN_DIR="$SNAP_ROOT/bin"
  export FDWAM_SNAP_PREFIX="$SNAP_ROOT/"
  export FDWAM_FLATPAK_SYSTEM_DIR="$FLATPAK_ROOT/system"
  export FDWAM_FLATPAK_USER_DIR="$FLATPAK_ROOT/user"

  export FDWAM_NOW="2026-10-11T10:00:00Z"
  export FDWAM_TEST_LOG="$T/browser.log"
  export FDWAM_TEST_CALLS="$T/calls.log"

  # Paths used by the test files.
  # shellcheck disable=SC2034
  {
    APPS_DIR="$XDG_DATA_HOME/applications"
    DATA_DIR="$XDG_DATA_HOME/fdwam"
    REG_DIR="$DATA_DIR/apps"
    ICON_DIR="$DATA_DIR/icons"
    PROFILES_DIR="$DATA_DIR/profiles"
  }
}

# Returns PATH without directories that may contain real browsers (anything
# under the developer's real HOME, ~/.local/bin, snap, flatpak, /opt), so
# detection only sees the fakes.
system_path_without_browsers() {
  local out="" d
  local IFS=:
  for d in $PATH; do
    case "$d" in
      "$ORIG_HOME"/*|*/.local/bin|/snap/bin|*/flatpak/exports/bin|/opt/*) continue ;;
    esac
    out+="${out:+:}$d"
  done
  printf '%s' "$out"
}

setup() {
  fdwam_setup
}

# Removes a fake browser so that detection falls through to the next candidate.
remove_fake_browser() { rm -f "$BIN/$1"; }
remove_all_fake_browsers() {
  local name
  for name in "${FAKE_NATIVE_BROWSERS[@]}"; do rm -f "$BIN/$name"; done
}

# Creates a fake snap: $SNAP_ROOT/<snap>/current/<cmd> (real file) and the
# /snap/bin style symlink $SNAP_ROOT/bin/<snap> pointing to it.
make_fake_snap() {
  local snap="$1"
  mkdir -p "$SNAP_ROOT/$snap/current"
  cp "$STUBS_DIR/fake-browser" "$SNAP_ROOT/$snap/current/$snap"
  ln -s "$SNAP_ROOT/$snap/current/$snap" "$SNAP_ROOT/bin/$snap"
}

# Creates a fake flatpak export wrapper in the system or user root.
make_fake_flatpak() {
  local scope="$1" id="$2"
  cp "$STUBS_DIR/fake-browser" "$FLATPAK_ROOT/$scope/$id"
}

# Writes a config file.
write_config() {
  mkdir -p "$XDG_CONFIG_HOME/fdwam"
  printf '%s\n' "$@" > "$XDG_CONFIG_HOME/fdwam/config"
}

# Sources the script so that functions can be unit tested.
source_fdwam() {
  # shellcheck disable=SC1090
  source "$FDWAM"
  config_load
}

# Replaces temp paths with placeholders (longest first) and compares with a
# golden file. FDWAM_UPDATE_GOLDEN=1 rewrites the golden file instead.
# Usage: assert_golden <actual-file> <golden-relative-path>
assert_golden() {
  local actual="$1" golden="$FIXTURES_DIR/$2" normalized="$BATS_TEST_TMPDIR/normalized"
  normalize_paths < "$actual" > "$normalized"
  if [[ "${FDWAM_UPDATE_GOLDEN:-0}" == 1 ]]; then
    mkdir -p "$(dirname "$golden")"
    cp "$normalized" "$golden"
  fi
  [[ -f "$golden" ]] || { echo "missing golden file $golden (run with FDWAM_UPDATE_GOLDEN=1)"; return 1; }
  if ! diff -u "$golden" "$normalized"; then
    echo "golden mismatch: $2"
    return 1
  fi
}

normalize_paths() {
  sed -e "s#$XDG_DATA_HOME/flatpak/exports/bin#@FLATPAK_USER@#g" \
      -e "s#$FLATPAK_ROOT/system#@FLATPAK_SYSTEM@#g" \
      -e "s#$FLATPAK_ROOT/user#@FLATPAK_USER@#g" \
      -e "s#$SNAP_ROOT/bin#@SNAP_BIN@#g" \
      -e "s#$SNAP_ROOT#@SNAP@#g" \
      -e "s#$XDG_CONFIG_HOME#@CONFIG@#g" \
      -e "s#$XDG_DATA_HOME#@DATA@#g" \
      -e "s#$BIN#@BIN@#g" \
      -e "s#$HOME#@HOME@#g"
}

# Reads the browser log written by fake-browser: line 1 = $0, rest = args.
browser_log_argv0() { head -n1 "$FDWAM_TEST_LOG"; }
browser_log_args() { tail -n +2 "$FDWAM_TEST_LOG"; }

# Extracts a key from a .desktop or registry file.
desktop_value() { sed -n "s/^$2=//p" "$1" | head -n1; }

# Creates an app offline (fixed name, no icon) with the given extra arguments.
create_offline() {
  run "$FDWAM" create "$@" --no-icon -y
  assert_success
}

skip_without() {
  command -v "$1" >/dev/null 2>&1 || skip "$1 not installed"
}
