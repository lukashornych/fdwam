#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Keeps README.md in sync with the browser table in bin/fdwam.

load test_helper

README="$REPO_ROOT/README.md"

@test "README browser table lists every enum value with family, support and tested status" {
  run "$FDWAM" browsers --porcelain
  assert_success
  local line enum family support verified row rows=0
  for line in "${lines[@]}"; do
    IFS='|' read -r enum family support _ _ verified <<< "$line"
    row="$(grep -E "^\| \`$enum\` \|" "$README" || true)"
    [[ -n "$row" ]] || { echo "README has no row for $enum"; return 1; }
    rows=$((rows + 1))
    [[ "$row" == "| \`$enum\` | $family | "* ]] || { echo "family mismatch for $enum: $row"; return 1; }
    if [[ "$support" == primary ]]; then
      [[ "$row" == *"| primary |"* ]] || { echo "support mismatch for $enum"; return 1; }
    else
      [[ "$row" == *"| best effort |"* ]] || { echo "support mismatch for $enum"; return 1; }
    fi
    if [[ -n "$verified" ]]; then
      [[ "$row" == *"| ✅ yes – $verified |"* ]] || { echo "tested column mismatch for $enum (expected '✅ yes – $verified'): $row"; return 1; }
    else
      [[ "$row" == *"| ❔ no – estimated |"* ]] || { echo "tested column mismatch for $enum (expected '❔ no – estimated'): $row"; return 1; }
    fi
  done
  assert_equal "$rows" 12
  assert_equal "$(grep -cE '^\| `[a-z]+` \| (chromium|firefox|epiphany|falkon) \|' "$README")" 12
}

@test "README documents every command and the config keys" {
  for cmd in create list show modify delete launch regenerate browsers doctor help version; do
    grep -q "fdwam $cmd" "$README" || { echo "README does not mention 'fdwam $cmd'"; return 1; }
  done
  for key in default_browser 'browser.<enum>' 'flags.<enum>' ozone_mode default_category; do
    grep -qF "\`$key\`" "$README" || { echo "README does not document config key $key"; return 1; }
  done
  # test hooks must not be advertised in the README
  ! grep -q FDWAM_FORCE_INTERACTIVE "$README"
  ! grep -q FDWAM_UPDATE_GOLDEN "$README"
}

@test "version is 'development' in the repository and stamped by make dist" {
  run "$FDWAM" version
  assert_output "fdwam development, Apache-2.0"
  run make -s -C "$REPO_ROOT" dist VERSION=v1.2.3 DIST="$T/dist"
  assert_success
  run "$T/dist/fdwam" version
  assert_output "fdwam 1.2.3, Apache-2.0"
  [[ -f "$T/dist/fdwam.bash" ]]
  (cd "$T/dist" && sha256sum -c --quiet SHA256SUMS)
  grep -q ' fdwam$' "$T/dist/SHA256SUMS"
  grep -q ' fdwam.bash$' "$T/dist/SHA256SUMS"
}
