#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Skeleton, CLI parsing, help, version, exit codes.

load test_helper

@test "help prints usage and exits 0" {
  run "$FDWAM" help
  assert_success
  assert_output --partial "Usage: fdwam <command>"
  assert_output --partial "create [<url>] [<browser>]"
}

@test "--help and -h print usage" {
  run "$FDWAM" --help
  assert_success
  assert_output --partial "Usage: fdwam"
  run "$FDWAM" -h
  assert_success
}

@test "help <command> prints command help" {
  run "$FDWAM" help create
  assert_success
  assert_output --partial "Usage: fdwam create"
  assert_output --partial "--no-icon"
  run "$FDWAM" help delete
  assert_output --partial "--keep-profile"
}

@test "no arguments prints usage to stderr and exits 2" {
  run --separate-stderr "$FDWAM"
  assert_equal "$status" 2
  [[ "$stderr" == *"Usage: fdwam"* ]]
  [[ -z "$output" ]]
}

@test "unknown command exits 2 with message on stderr" {
  run --separate-stderr "$FDWAM" frobnicate
  assert_equal "$status" 2
  [[ "$stderr" == *"unknown command 'frobnicate'"* ]]
}

@test "unknown option exits 2" {
  run "$FDWAM" --bogus
  assert_equal "$status" 2
  run "$FDWAM" list --bogus
  assert_equal "$status" 2
}

@test "version prints version and license" {
  run "$FDWAM" version
  assert_success
  assert_output --regexp '^fdwam (development|[0-9]+\.[0-9]+\.[0-9]+), Apache-2\.0$'
  run "$FDWAM" --version
  assert_success
}

@test "script has strict mode, bash version check and license header" {
  grep -q 'set -Eeuo pipefail' "$FDWAM"
  grep -q 'BASH_VERSINFO' "$FDWAM"
  grep -q '^# SPDX-License-Identifier: Apache-2.0' "$FDWAM"
}

@test "the script can be sourced without side effects" {
  source_fdwam
  [[ "$(type -t main)" == function ]]
  [[ ! -e "$DATA_DIR" ]]
}

@test "unknown id exits 3" {
  run "$FDWAM" show nope
  assert_equal "$status" 3
  run "$FDWAM" delete nope -y
  assert_equal "$status" 3
}

@test "control characters in the URL are rejected with exit 2" {
  run "$FDWAM" create $'https://example.com/a\nIcon=/tmp/evil' brave --name X --no-icon -y
  assert_equal "$status" 2
  assert_output --partial "invalid URL"
  run "$FDWAM" create $'https://example.com/a\tb' brave --name X --no-icon -y
  assert_equal "$status" 2
  [[ ! -e "$APPS_DIR/fdwam-example.desktop" ]]
  [[ ! -e "$REG_DIR/example.conf" ]]
  create_offline https://example.com/ brave --name X
  run "$FDWAM" modify example --url $'https://example.com/a\nIcon=/tmp/evil'
  assert_equal "$status" 2
  assert_equal "$(desktop_value "$REG_DIR/example.conf" url)" "https://example.com/"
}

@test "control characters in --flags are rejected with exit 2" {
  run "$FDWAM" create https://example.com/ brave --name X --no-icon -y --flags $'--x\nIcon=/tmp/evil'
  assert_equal "$status" 2
  assert_output --partial "control characters"
  [[ ! -e "$APPS_DIR/fdwam-example.desktop" ]]
  [[ ! -e "$REG_DIR/example.conf" ]]
  create_offline https://example.com/ brave --name X
  run "$FDWAM" modify example --flags $'--x\rIcon=/tmp/evil'
  assert_equal "$status" 2
  assert_equal "$(desktop_value "$REG_DIR/example.conf" flags)" ""
}

@test "the PATH filter drops directories under the developer's real HOME" {
  [[ -n "$ORIG_HOME" && "$ORIG_HOME" != "$HOME" ]]
  # (test/stubs may live under the real HOME; only the system part is filtered)
  [[ ":$SYSTEM_PATH:" != *":$ORIG_HOME/"* ]]
  local out
  out="$(ORIG_HOME=/home/dev; PATH="/home/dev/.cargo/bin:/usr/bin:/home/dev/bin:/opt/foo/bin:/snap/bin"; system_path_without_browsers)"
  assert_equal "$out" "/usr/bin"
}
