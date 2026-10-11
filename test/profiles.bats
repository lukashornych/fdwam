#!/usr/bin/env bats
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
# Profile directories per family and installation kind.

load test_helper

@test "chromium native profile: directory with First Run sentinel" {
  create_offline https://example.com/ brave --name Example
  [[ -d "$PROFILES_DIR/example" ]]
  [[ -f "$PROFILES_DIR/example/First Run" ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" profile_dir)" "$PROFILES_DIR/example"
}

@test "chromium snap profile lives in ~/snap/<snap>/common" {
  remove_fake_browser chromium
  make_fake_snap chromium
  create_offline https://example.com/ chromium --name Example
  [[ -f "$HOME/snap/chromium/common/fdwam-profiles/example/First Run" ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" browser_kind)" snap
}

@test "chromium flatpak profile lives in ~/.var/app/<id>/data" {
  remove_fake_browser google-chrome-stable
  make_fake_flatpak user com.google.Chrome
  create_offline https://example.com/ chrome --name Example
  [[ -f "$HOME/.var/app/com.google.Chrome/data/fdwam-profiles/example/First Run" ]]
}

@test "firefox profile: user.js and chrome/userChrome.css" {
  create_offline https://example.com/ firefox --name Example
  grep -q 'toolkit.legacyUserProfileCustomizations.stylesheets", true' "$PROFILES_DIR/example/user.js"
  grep -q 'browser.aboutwelcome.enabled", false' "$PROFILES_DIR/example/user.js"
  grep -q 'browser.link.open_newwindow", 2' "$PROFILES_DIR/example/user.js"
  grep -q 'browser.shell.checkDefaultBrowser", false' "$PROFILES_DIR/example/user.js"
  grep -q '#navigator-toolbox' "$PROFILES_DIR/example/chrome/userChrome.css"
}

@test "firefox profile keeps the native title bar and reveals the toolbars on hover" {
  create_offline https://example.com/ firefox --name Example
  # Regression: the tab strip was hidden together with the title bar Firefox
  # draws into it, so the window had no move/minimize/close controls.
  grep -q 'browser.tabs.inTitlebar", 0' "$PROFILES_DIR/example/user.js"
  grep -q 'browser.tabs.drawInTitlebar", false' "$PROFILES_DIR/example/user.js"
  run cat "$PROFILES_DIR/example/chrome/userChrome.css"
  assert_output --partial '#navigator-toolbox:not(:hover):not(:focus-within),'
  # Regression: the toolbox squeezed to 4px showed shrunken toolbars, and the
  # address bar (own layer) stayed visible when only the toolbox was hidden.
  assert_output --partial 'position: fixed !important'
  assert_output --partial '#navigator-toolbox:not(:hover):not(:focus-within) #urlbar'
  # Regression: a faint address bar stayed visible (top-layer popover).
  assert_output --partial '#navigator-toolbox:not(:hover):not(:focus-within) [popover]'
  assert_output --partial 'clip-path: inset(50%) !important'
  # Regression: #urlbar-container stayed faintly visible despite opacity/clip-path.
  assert_output --partial '#navigator-toolbox:not(:hover):not(:focus-within):not(:has([open])) #urlbar-container {
  display: none !important;'
  refute_output --partial 'height: 4px !important;
  min-height'
  # Regression: hiding the toolbars with visibility closed an open menu as
  # soon as the mouse left the toolbar for the menu (invisible anchor).
  assert_output --partial 'opacity: 0 !important'
  assert_output --partial 'pointer-events: none !important'
  refute_output --regexp 'focus-within\)[^}]*visibility'
  refute_output --partial 'height: 0 !important'
}

@test "firefox derivatives use the same template" {
  create_offline https://example.com/ librewolf --name Example
  [[ -f "$PROFILES_DIR/example/chrome/userChrome.css" ]]
}

@test "firefox snap profile lives in ~/snap/firefox/common" {
  remove_fake_browser firefox
  make_fake_snap firefox
  create_offline https://example.com/ firefox --name Example
  [[ -f "$HOME/snap/firefox/common/fdwam-profiles/example/user.js" ]]
}

@test "epiphany profile: .app, app-icon.png and a copy of the .desktop file" {
  cp "$FIXTURES_DIR/icons/icon.png" "$T/icon.png"
  run "$FDWAM" create https://example.com/ epiphany --name Example --icon "$T/icon.png" -y
  assert_success
  local p="$PROFILES_DIR/org.gnome.Epiphany.WebApp_example"
  [[ -f "$p/.app" ]]
  [[ -f "$p/app-icon.png" ]]
  [[ -f "$p/fdwam-example.desktop" ]]
  cmp "$p/fdwam-example.desktop" "$APPS_DIR/fdwam-example.desktop"
}

@test "falkon profile: directory plus symlink in ~/.config/falkon/profiles" {
  create_offline https://example.com/ falkon --name Example
  [[ -d "$PROFILES_DIR/example" ]]
  [[ -L "$XDG_CONFIG_HOME/falkon/profiles/fdwam-example" ]]
  assert_equal "$(desktop_value "$REG_DIR/example.conf" profile_link)" "$XDG_CONFIG_HOME/falkon/profiles/fdwam-example"
  run "$FDWAM" delete example -y
  assert_success
  [[ ! -e "$PROFILES_DIR/example" ]]
  [[ ! -L "$XDG_CONFIG_HOME/falkon/profiles/fdwam-example" ]]
}

@test "delete removes the profile, --keep-profile keeps it" {
  create_offline https://example.com/ brave --name Example
  run "$FDWAM" delete example --keep-profile
  assert_success
  [[ -d "$PROFILES_DIR/example" ]]
  [[ ! -f "$REG_DIR/example.conf" ]]
  [[ ! -f "$APPS_DIR/fdwam-example.desktop" ]]
  create_offline https://example.com/ brave --name Example
  run "$FDWAM" delete example -y
  assert_success
  [[ ! -d "$PROFILES_DIR/example" ]]
}

@test "delete without -y on a non-terminal refuses and changes nothing" {
  create_offline https://example.com/ brave --name Example
  run "$FDWAM" delete example </dev/null
  assert_equal "$status" 2
  assert_output --partial "without confirmation"
  [[ -f "$REG_DIR/example.conf" ]]
  [[ -d "$PROFILES_DIR/example" ]]
}

@test "delete asks for confirmation on a terminal and honours the answer" {
  create_offline https://example.com/ brave --name Example
  FDWAM_FORCE_INTERACTIVE=1 run "$FDWAM" delete example <<< "n"
  assert_success
  assert_output --partial "not deleted"
  [[ -f "$REG_DIR/example.conf" ]]
  FDWAM_FORCE_INTERACTIVE=1 run "$FDWAM" delete example <<< "y"
  assert_success
  [[ ! -f "$REG_DIR/example.conf" ]]
  [[ ! -d "$PROFILES_DIR/example" ]]
}

@test "delete does not touch a foreign .desktop file with the same name" {
  create_offline https://example.com/ brave --name Example
  printf '[Desktop Entry]\nType=Application\nName=Foreign\nExec=true\n' > "$APPS_DIR/fdwam-example.desktop"
  run "$FDWAM" delete example -y
  assert_success
  assert_output --partial "not generated by fdwam"
  [[ -f "$APPS_DIR/fdwam-example.desktop" ]]
}

# Leaving Falkon while keeping the old profile: $1 = keep | refuse.
falkon_to_brave_keeping_profile() {
  local link="$XDG_CONFIG_HOME/falkon/profiles/fdwam-fk"
  create_offline https://site.example/ falkon --name F --id fk
  echo marker > "$PROFILES_DIR/fk/marker"
  [[ -L "$link" ]]
  if [[ "$1" == keep ]]; then
    run "$FDWAM" modify fk --browser brave --keep-profile
  else
    FDWAM_FORCE_INTERACTIVE=1 run "$FDWAM" modify fk --browser brave <<< "n"
  fi
  assert_success
  assert_output --partial "old profile kept at $PROFILES_DIR/fk.2026-10-11T100000Z"
  [[ -f "$PROFILES_DIR/fk.2026-10-11T100000Z/marker" ]]
  [[ -f "$PROFILES_DIR/fk/First Run" ]]
  [[ ! -e "$link" && ! -L "$link" ]]
  assert_equal "$(desktop_value "$REG_DIR/fk.conf" browser)" brave
  assert_equal "$(desktop_value "$REG_DIR/fk.conf" profile_dir)" "$PROFILES_DIR/fk"
  assert_equal "$(desktop_value "$REG_DIR/fk.conf" profile_link)" ""
  run "$FDWAM" delete fk -y
  assert_success
  assert_equal "$(ls -A "$XDG_CONFIG_HOME/falkon/profiles")" ""
  [[ ! -e "$PROFILES_DIR/fk" ]]
}

@test "Falkon -> Brave with --keep-profile removes the Falkon symlink" {
  falkon_to_brave_keeping_profile keep
}

@test "Falkon -> Brave with a refused confirmation behaves like --keep-profile" {
  falkon_to_brave_keeping_profile refuse
}

@test "Falkon -> Brave with -y deletes the old profile and its symlink" {
  create_offline https://site.example/ falkon --name F --id fk
  run "$FDWAM" modify fk --browser brave -y
  assert_success
  [[ ! -L "$XDG_CONFIG_HOME/falkon/profiles/fdwam-fk" ]]
  [[ -f "$PROFILES_DIR/fk/First Run" ]]
  run compgen -G "$PROFILES_DIR/fk.*"
  assert_failure
}
