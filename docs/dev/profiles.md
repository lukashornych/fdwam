# Profiles

## Location (`profile_locate <id>` → `PROFILE_PATH`, `PROFILE_LINK`)

| Browser / kind | Directory |
|----------------|-----------|
| native (chromium, firefox families) | `${XDG_DATA_HOME}/fdwam/profiles/<id>` |
| snap | `$HOME/snap/<snap-name>/common/fdwam-profiles/<id>` (verified for Brave: snap confinement forbids hidden dirs in `$HOME` and has a private `/tmp`) |
| flatpak | `$HOME/.var/app/<flatpak-id>/data/fdwam-profiles/<id>` |
| epiphany | `${XDG_DATA_HOME}/fdwam/profiles/org.gnome.Epiphany.WebApp_<id>` (the name is required by Epiphany) |
| falkon | `${XDG_DATA_HOME}/fdwam/profiles/<id>` + symlink `${XDG_CONFIG_HOME}/falkon/profiles/fdwam-<id>` (Falkon only accepts profile names, `--profile=fdwam-<id>`) |

Both paths are stored in the registry (`profile_dir`, `profile_link`), so
`delete` never guesses.

## Content (`profile_create`)

| Family | Files |
|--------|-------|
| chromium | empty `First Run` sentinel (suppresses the first-run UI). The profile inside `--user-data-dir` is named `fdwam-<id>` via `--profile-directory`, because that name is part of the Wayland `app_id`. The browser initialises the rest on first start. |
| firefox | `user.js` (userChrome enabled, welcome/first-run pages off, no default-browser check, `browser.link.open_newwindow=2`, no close warning, native window title bar via `browser.tabs.inTitlebar=0` / `browser.tabs.drawInTitlebar=false`) and `chrome/userChrome.css`: `#navigator-toolbox` is `position: fixed` over the page in its natural height and hidden until its 4px `::before` strip at the top edge is hovered (or focus is inside it, or a menu/panel is open); DOM fullscreen hides it. The hidden toolbox uses `opacity: 0` + `pointer-events: none`, never `visibility: hidden`: Firefox closes a menu whose anchor button becomes invisible, so the menu would vanish when the mouse moves into it. `#urlbar` and `[popover]` elements are listed explicitly (and additionally hidden by `clip-path: inset(50%)`, which keeps them laid out and visible as anchors) because the top layer ignores the toolbox opacity. `#urlbar-container` stayed faintly visible anyway (Firefox on KDE), so it gets `display: none` while hidden, except when a menu/panel is open (`:not(:has([open]))`, so the address bar panels do not close). Without the title bar prefs Firefox draws its own title bar into the hidden tab strip and the window has no move/minimize/close controls. Own minimal CSS under Apache-2.0. Same template for LibreWolf, Floorp, Waterfox, Zen. The files are written only by `profile_create`; existing profiles keep the old template. |
| epiphany | empty `.app`, `app-icon.png` (copy of a PNG icon), and after `desktop_write` a copy of the `.desktop` file (`profile_post_desktop`). |
| falkon | directory + symlink. |

## Deletion and browser change

`profile_delete` removes the symlink and the directory. `delete --keep-profile`
skips it. `modify --browser` with a different browser or installation kind
always creates a fresh profile: the old one is deleted after confirmation
(`-y`), otherwise kept (`--keep-profile` and a refused confirmation behave the
same, `profile_move_aside`); when the new path equals the old one the old
directory is moved aside to `<dir>.<timestamp>` first. A kept profile is a
backup, not an active profile: the Falkon symlink of the old profile is
removed (not redirected), so Falkon does not offer it and `delete` cannot
leave a dangling link behind. Both branches run before `APP[profile_link]` is
overwritten with the new value.

## Tests

`test/profiles.bats` (files per family, snap and flatpak paths, Falkon symlink
removal, `--keep-profile`, confirmation handling, foreign `.desktop` files) and
`test/commands.bats` (browser change scenarios, rollback keeps pre-existing
profile directories).
