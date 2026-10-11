#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Installer tests: a fake GitHub release served from a local HTTP server.

load test_helper

PORT=18792
BASE="http://127.0.0.1:$PORT"
INSTALL="$REPO_ROOT/install.sh"

setup_file() {
  SRV="$BATS_FILE_TMPDIR/srv"
  mkdir -p "$SRV/releases/latest/download" "$SRV/releases/download/v9.9.9" "$SRV/raw/main/bin" "$SRV/raw/main/completions" "$SRV/bad/releases/latest/download"
  # latest = the real script, v9.9.9 = a marker script (used for "update")
  cp "$REPO_ROOT/bin/fdwam" "$SRV/releases/latest/download/fdwam"
  cp "$REPO_ROOT/completions/fdwam.bash" "$SRV/releases/latest/download/fdwam.bash"
  (cd "$SRV/releases/latest/download" && sha256sum fdwam fdwam.bash > SHA256SUMS)
  printf '#!/usr/bin/env bash\necho "fdwam 9.9.9, Apache-2.0"\n' > "$SRV/releases/download/v9.9.9/fdwam"
  cp "$REPO_ROOT/completions/fdwam.bash" "$SRV/releases/download/v9.9.9/fdwam.bash"
  (cd "$SRV/releases/download/v9.9.9" && sha256sum fdwam fdwam.bash > SHA256SUMS)
  cp "$REPO_ROOT/bin/fdwam" "$SRV/raw/main/bin/fdwam"
  cp "$REPO_ROOT/completions/fdwam.bash" "$SRV/raw/main/completions/fdwam.bash"
  # a release with a wrong checksum
  cp "$REPO_ROOT/bin/fdwam" "$SRV/bad/releases/latest/download/fdwam"
  cp "$REPO_ROOT/completions/fdwam.bash" "$SRV/bad/releases/latest/download/fdwam.bash"
  (cd "$SRV/bad/releases/latest/download" && sha256sum fdwam fdwam.bash | sed 's/^0/x/; s/^[1-9a-f]/0/' > SHA256SUMS)
  cd "$SRV"
  python3 -m http.server --bind 127.0.0.1 "$PORT" >/dev/null 2>&1 &
  echo $! > "$BATS_FILE_TMPDIR/server.pid"
  local i=0
  until curl -fs "$BASE/releases/latest/download/SHA256SUMS" >/dev/null 2>&1; do
    sleep 0.1; i=$((i + 1)); (( i < 100 )) || { echo "server did not start"; return 1; }
  done
}

teardown_file() {
  kill "$(cat "$BATS_FILE_TMPDIR/server.pid")" 2>/dev/null || true
}

setup() {
  fdwam_setup
  export FDWAM_RELEASE_BASE_URL="$BASE"
  export PATH="$HOME/.local/bin:$PATH"
  TARGET="$XDG_DATA_HOME/fdwam/bin/fdwam"
  LINK="$HOME/.local/bin/fdwam"
  COMPLETION="$XDG_DATA_HOME/bash-completion/completions/fdwam"
}

assert_installed_latest() {
  [[ -x "$TARGET" ]]
  cmp -s "$TARGET" "$REPO_ROOT/bin/fdwam"
  [[ -L "$LINK" ]]
  assert_equal "$(readlink "$LINK")" "$TARGET"
  [[ -f "$COMPLETION" ]]
}

@test "clean install with curl" {
  FDWAM_DOWNLOADER=curl run bash "$INSTALL"
  assert_success
  assert_output --partial "checksum OK"
  assert_output --partial "fdwam development, Apache-2.0"
  assert_output --partial "fdwam doctor"
  refute_output --partial "not in your PATH"
  assert_installed_latest
  run fdwam version
  assert_success
}

@test "clean install with wget" {
  skip_without wget
  FDWAM_DOWNLOADER=wget run bash "$INSTALL"
  assert_success
  assert_output --partial "with wget"
  assert_installed_latest
}

@test "piped through bash like the README one-liner" {
  run bash -c "cat '$INSTALL' | bash"
  assert_success
  assert_installed_latest
}

@test "update replaces the script atomically and keeps data" {
  FDWAM_VERSION=v9.9.9 run bash "$INSTALL"
  assert_success
  assert_equal "$(fdwam version)" "fdwam 9.9.9, Apache-2.0"
  mkdir -p "$XDG_DATA_HOME/fdwam/apps"
  echo "id=keep" > "$XDG_DATA_HOME/fdwam/apps/keep.conf"
  run bash "$INSTALL"
  assert_success
  assert_installed_latest
  [[ -f "$XDG_DATA_HOME/fdwam/apps/keep.conf" ]]
  [[ ! -e "$XDG_DATA_HOME/fdwam/bin/.fdwam.new" ]]
}

@test "wrong checksum: nothing is installed or changed" {
  FDWAM_RELEASE_BASE_URL="$BASE/bad" run bash "$INSTALL"
  assert_failure
  assert_output --partial "checksum verification of fdwam FAILED"
  [[ ! -e "$TARGET" ]]
  [[ ! -e "$LINK" ]]
  [[ ! -e "$COMPLETION" ]]
  # an existing installation stays untouched
  run bash "$INSTALL"
  assert_success
  FDWAM_RELEASE_BASE_URL="$BASE/bad" run bash "$INSTALL"
  assert_failure
  assert_installed_latest
}

@test "unreachable release: fails without changes" {
  FDWAM_RELEASE_BASE_URL="http://127.0.0.1:1" run bash "$INSTALL"
  assert_failure
  assert_output --partial "download failed"
  [[ ! -e "$TARGET" ]]
}

@test "development version from main skips the checksum with a warning" {
  FDWAM_VERSION=main run bash "$INSTALL"
  assert_success
  assert_output --partial "no checksum verification"
  refute_output --partial "checksum OK"
  assert_installed_latest
}

@test "~/.local/bin outside PATH prints the hint" {
  PATH="$STUBS_DIR:$BIN:$SYSTEM_PATH" run bash "$INSTALL"
  assert_success
  assert_output --partial "not in your PATH"
  assert_output --partial 'export PATH="'"$HOME"'/.local/bin:$PATH"'
}

@test "existing foreign ~/.local/bin/fdwam is never overwritten" {
  mkdir -p "$HOME/.local/bin"
  echo "mine" > "$LINK"
  run bash "$INSTALL"
  assert_failure
  assert_output --partial "already exists and is not a fdwam symlink"
  assert_equal "$(cat "$LINK")" mine
  [[ ! -e "$TARGET" ]]
  [[ ! -e "$COMPLETION" ]]
}

@test "--prefix and --no-completion" {
  run bash "$INSTALL" --prefix "$T/mybin" --no-completion
  assert_success
  [[ -L "$T/mybin/fdwam" ]]
  [[ ! -e "$LINK" ]]
  [[ ! -e "$COMPLETION" ]]
}

@test "--uninstall removes program, symlink and completion but keeps data" {
  run bash "$INSTALL"
  assert_success
  mkdir -p "$XDG_DATA_HOME/fdwam/apps" "$XDG_DATA_HOME/fdwam/profiles/x"
  echo "id=x" > "$XDG_DATA_HOME/fdwam/apps/x.conf"
  run bash "$INSTALL" --uninstall
  assert_success
  assert_output --partial "removed $LINK"
  assert_output --partial "Kept (your data)"
  [[ ! -e "$LINK" ]]
  [[ ! -e "$XDG_DATA_HOME/fdwam/bin" ]]
  [[ ! -e "$COMPLETION" ]]
  [[ -f "$XDG_DATA_HOME/fdwam/apps/x.conf" ]]
  [[ -d "$XDG_DATA_HOME/fdwam/profiles/x" ]]
  run bash "$INSTALL" --uninstall
  assert_success
  assert_output --partial "nothing to remove"
}

@test "--uninstall leaves a foreign ~/.local/bin/fdwam alone" {
  mkdir -p "$HOME/.local/bin"
  echo "mine" > "$LINK"
  run bash "$INSTALL" --uninstall
  assert_success
  assert_output --partial "not the fdwam symlink"
  assert_equal "$(cat "$LINK")" mine
}

@test "--help and unknown option" {
  run bash "$INSTALL" --help
  assert_success
  assert_output --partial "--uninstall"
  run bash "$INSTALL" --bogus
  assert_failure
}
