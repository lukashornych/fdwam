#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Registry read/write, safe parser, IDs and collisions.

load test_helper

@test "round-trip of values with special characters" {
  source_fdwam
  APP=()
  APP[id]=rt
  APP[name]='Název = "quoted" & 100% $HOME `x` ; done'
  APP[url]='https://example.com/a?b=c&d=e%20f;g'
  APP[flags]="--a='1 2' --b"
  APP[browser]=brave
  registry_write
  APP=()
  registry_read rt
  assert_equal "${APP[name]}" 'Název = "quoted" & 100% $HOME `x` ; done'
  assert_equal "${APP[url]}" 'https://example.com/a?b=c&d=e%20f;g'
  assert_equal "${APP[flags]}" "--a='1 2' --b"
  assert_equal "${APP[version]}" 1
}

@test "registry values are never evaluated (no code injection)" {
  source_fdwam
  APP=()
  APP[id]=inj
  APP[name]='$(touch '"$T"'/pwned) `touch '"$T"'/pwned2`'
  registry_write
  APP=()
  registry_read inj
  assert_equal "${APP[name]}" '$(touch '"$T"'/pwned) `touch '"$T"'/pwned2`'
  [[ ! -e "$T/pwned" && ! -e "$T/pwned2" ]]
  # even a hand-crafted file with shell syntax is only data
  printf 'id=inj\nname=x; touch %s/pwned3\nurl=$(touch %s/pwned4)\n' "$T" "$T" > "$REG_DIR/inj.conf"
  registry_read inj
  assert_equal "${APP[name]}" "x; touch $T/pwned3"
  [[ ! -e "$T/pwned3" && ! -e "$T/pwned4" ]]
  run "$FDWAM" show inj
  assert_success
  [[ ! -e "$T/pwned3" && ! -e "$T/pwned4" ]]
}

@test "parser ignores malformed lines and keeps field order on write" {
  source_fdwam
  mkdir -p "$REG_DIR"
  printf '# comment\nid=ord\nname=Ord\nURL=upper\n junk\nurl=https://o.example/\n' > "$REG_DIR/ord.conf"
  registry_read ord
  assert_equal "${APP[url]}" "https://o.example/"
  registry_write
  run cat "$REG_DIR/ord.conf"
  assert_line --index 0 "id=ord"
  assert_line --index 1 "name=Ord"
  assert_line --index 2 "url=https://o.example/"
  refute_output --partial "URL=upper"
}

@test "newlines in values are stripped on write" {
  source_fdwam
  APP=([id]=nl [name]=$'multi\nline\rname')
  registry_write
  assert_equal "$(grep -c '' "$REG_DIR/nl.conf")" "${#REG_FIELDS[@]}"
  registry_read nl
  assert_equal "${APP[name]}" "multilinename"
}

@test "created/modified use FDWAM_NOW" {
  create_offline https://example.com/ brave --name Example
  assert_equal "$(desktop_value "$REG_DIR/example.conf" created)" "2026-10-11T10:00:00Z"
  assert_equal "$(desktop_value "$REG_DIR/example.conf" modified)" "2026-10-11T10:00:00Z"
}

@test "slug from hostname" {
  source_fdwam
  assert_equal "$(slug_from_url https://netflix.com/)" netflix
  assert_equal "$(slug_from_url https://www.netflix.com/browse)" netflix
  assert_equal "$(slug_from_url https://app.slack.com/)" slack
  assert_equal "$(slug_from_url https://mail.google.com/mail/)" mail-google
  assert_equal "$(slug_from_url https://www.bbc.co.uk/)" bbc
  assert_equal "$(slug_from_url https://news.bbc.co.uk/)" news-bbc
  assert_equal "$(slug_from_url http://localhost:8080/)" localhost
  assert_equal "$(slug_from_url https://192.168.1.1/)" 192-168-1
  assert_equal "$(slug_from_url https://Some_Host.Example.ORG/)" some-host-example
}

@test "id validation" {
  source_fdwam
  id_valid netflix
  id_valid a
  id_valid mail-google-2
  ! id_valid Netflix
  ! id_valid -x
  ! id_valid "a b"
  ! id_valid "$(printf 'a%.0s' {1..41})"
  id_valid "$(printf 'a%.0s' {1..40})"
}

@test "id collision appends -2, -3" {
  create_offline https://example.com/ brave --name One
  create_offline https://www.example.com/x brave --name Two
  create_offline https://example.com/y brave --name Three
  run "$FDWAM" list
  assert_line --partial "example "
  assert_line --partial "example-2 "
  assert_line --partial "example-3 "
  [[ -f "$APPS_DIR/fdwam-example-3.desktop" ]]
}

@test "ids are case-sensitive and --id is validated" {
  run "$FDWAM" create https://example.com/ brave --name X --no-icon -y --id Netflix
  assert_equal "$status" 2
  create_offline https://example.com/ brave --name X --id netflix
  run "$FDWAM" create https://example.com/ brave --name X --no-icon -y --id netflix
  assert_equal "$status" 2
  assert_output --partial "already exists"
}

@test "registry_list is sorted" {
  create_offline https://b.example/ brave --name B
  create_offline https://a.example/ brave --name A
  create_offline https://c.example/ brave --name C
  source_fdwam
  assert_equal "$(registry_list | tr '\n' ' ')" "a b c "
}
