# fdwam – freedesktop web app manager

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)
[![CI](https://github.com/lukashornych/fdwam/actions/workflows/ci.yml/badge.svg)](https://github.com/lukashornych/fdwam/actions/workflows/ci.yml)

**fdwam** = **f**ree**d**esktop **w**eb **a**pp **m**anager.

It turns a web site into a desktop application: a `.desktop` launcher in your
application menu, an isolated browser profile (own cookies and logins) and the
site's favicon as the icon. It is a single Bash script without a GUI.

> Note: in the current state, this project is an **experimental** POC of the idea. 

The name refers to the two [freedesktop.org](https://www.freedesktop.org/)
standards it is built on: the *Desktop Entry Specification* (the `.desktop`
files) and the *XDG Base Directory Specification* (where data lives). Because
only those standards are used, the result works in every desktop environment
that follows them: KDE Plasma, GNOME, Xfce, Cinnamon, …

> fdwam is **not** an official freedesktop.org project and is not affiliated
> with freedesktop.org in any way.

fdwam is a plain command-line tool without a GUI. It works on native Wayland
(correct taskbar icon and window grouping on Plasma 6), handles snap and
flatpak browsers, escapes `Exec=` correctly and keeps a registry so that launchers can be regenerated at any time.

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/lukashornych/fdwam/main/install.sh | bash
fdwam create netflix.com        # interactive wizard, Enter accepts every default
fdwam list
fdwam delete netflix
```

## Requirements

Mandatory:

| Tool | Why |
|------|-----|
| bash ≥ 4.4 | the program itself |
| coreutils, grep, sed, awk (mawk is fine) | text processing |
| curl (or wget) | downloading the page and the favicon |

Optional (fdwam degrades gracefully without them):

| Tool | Without it |
|------|-----------|
| ImageMagick (`magick` or `convert`) | ICO, WebP, JPEG and GIF favicons are skipped; PNG and SVG still work. Sites that only offer `/favicon.ico` get the generic icon. |
| `jq` | the Web App Manifest is parsed with a simpler grep/sed parser |
| `file` | image types are detected from magic bytes only |
| `desktop-file-validate` (desktop-file-utils) | generated launchers are not validated |
| `update-desktop-database`, `kbuildsycoca6` | the menu may update only after re-login |

## Commands

```
fdwam create [<url>] [<browser>] [options]
fdwam list [--long]
fdwam show <id>
fdwam modify <id> [options]
fdwam delete <id> [--keep-profile] [-y]
fdwam launch <id>
fdwam regenerate <id> | --all
fdwam browsers
fdwam doctor
fdwam help [command]
fdwam version
```

Exit codes: `0` success, `1` error, `2` wrong usage, `3` unknown id,
`4` browser not found. Errors go to stderr; `-v` adds debug output;
`NO_COLOR` is honoured.

### create

```
fdwam create [<url>] [<browser>] [--name NAME] [--id ID] [--icon PATH|URL] [--no-icon]
             [--category CAT] [--flags "EXTRA ARGS"] [--x11|--wayland]
             [-i|--interactive] [-y|--yes] [--launch]
```

Browsers: `brave chrome chromium firefox vivaldi edge librewolf floorp waterfox zen epiphany falkon`.

Without `<url>` on a terminal the **interactive wizard** starts. It asks for
the URL, browser, name, id, category, icon, window mode and extra flags. Every
question shows the possible values and a default in brackets; Enter accepts the
default. Arguments and options skip the corresponding questions; `-i` runs the
wizard pre-filled with them; `-y` uses defaults for everything and never asks.

```
$ fdwam create
URL: netflix.com
  Fetching site metadata… done
Browser:
  1) brave      (native)
  2) chrome     (native)
  3) firefox    (snap)
Choose [1]:
Name [Netflix]:
ID [netflix]:
Category (AudioVideo, Development, Education, Game, Graphics, Network, Office, Science, Settings, System, Utility) [Network]: audiovideo
Icon:
  1) apple-touch-icon 180x180 (https://assets.nflxext.com/…/icon.png)
  2) favicon.ico (https://www.netflix.com/favicon.ico)
  3) custom path or URL
  4) generic icon
Choose [1]:
Window mode (auto, wayland, x11) [auto]:
Extra browser flags []:

  Name      Netflix
  ID        netflix
  URL       https://netflix.com/
  Browser   brave (/snap/bin/brave, snap)
  Category  AudioVideo
  Icon      https://assets.nflxext.com/…/icon.png
  Window    auto
  Exec      /snap/bin/brave --user-data-dir=… --profile-directory=fdwam-netflix … --app=https://netflix.com/
Create? [Y/n/e]:
Created 'netflix' -> ~/.local/share/applications/fdwam-netflix.desktop
Launch now? [y/N]:
```

In the summary `e` lets you go back to one step. Ctrl+C or Ctrl+D aborts
without writing anything.

Non-interactive equivalents:

```bash
fdwam create netflix.com brave --category AudioVideo -y
fdwam create https://mail.google.com/ firefox --name "Gmail" --id gmail --icon ~/gmail.png -y
fdwam create example.com --name Example --no-icon -y     # offline: touches no network
```

Options: `--name` application name (default: from the site, else from the
host), `--id` launcher id (default: slug of the host, `netflix`,
`mail-google`; collisions get `-2`, `-3`, …), `--icon` file or URL instead of
the favicon, `--no-icon` generic theme icon, `--category` menu category
(default `Network`), `--flags` extra browser arguments for this app,
`--x11`/`--wayland` window backend for the chromium family, `--launch` start
the app right away.

URLs without a scheme get `https://`; only `http` and `https` are accepted,
and URLs or `--flags` containing control characters (newline, tab, …) are
rejected with exit code `2`. An `--id` whose registry entry or
`fdwam-<id>.desktop` file already exists is rejected with exit code `2`; a
foreign `.desktop` file is never overwritten.

A favicon that cannot be found never makes `create` fail: a warning is printed
and the generic `applications-internet` icon is used. An explicit `--icon`,
however, must work: a missing file exits with `2`, a URL that cannot be
downloaded or converted exits with `1`, and nothing is created in either case.
With `--name` and an `--icon` (file or URL) the page itself is not downloaded.

### list, show

`fdwam list` prints `ID NAME BROWSER URL`; `--long` adds the installation
kind, the window class and the profile directory. `fdwam show <id>` prints the
whole registry entry plus the `.desktop` path and the exact command line.

### modify

```
fdwam modify <id> [--name NAME] [--url URL] [--browser BROWSER] [--keep-profile]
                  [--icon PATH|URL] [--no-icon] [--refresh-icon]
                  [--category CAT] [--flags "ARGS"] [--x11|--wayland] [-i] [-y]
```

Without options on a terminal the wizard runs with the current values as
defaults (on a terminal the current value is pre-filled; Ctrl+U clears it).
`--url` recomputes the window class (on Wayland it depends on the exact URL).
`--browser` creates a **new profile**, because profiles are not portable
between browsers; the old one is deleted after confirmation (`-y`) or kept with
`--keep-profile`. A kept profile is a backup only: when switching away from
Falkon its symlink in `~/.config/falkon/profiles` is removed. `--icon` is
checked before anything changes; an unusable icon (exit `2` for a missing
file, `1` for a failed download) leaves the app untouched.

### delete

`fdwam delete <id>` removes the launcher, the icon, the registry entry and the
browser profile. The profile holds logins and cookies, so it asks for
confirmation; on a non-terminal `-y` is required. `--keep-profile` leaves the
profile directory in place.

### launch, regenerate, browsers, doctor

- `fdwam launch <id>` starts the app in the foreground with the browser's
  stderr visible (useful for debugging). `--browser-mode` (`-b`) opens the
  app URL in a normal browser window on the app's profile, see
  [Extensions and settings](#extensions-and-settings).
- `fdwam regenerate <id>|--all` re-detects the browser binary, recomputes the
  window class and rewrites the launcher(s). Run it after editing the config
  file, reinstalling a browser or upgrading fdwam.
- `fdwam browsers` shows how each supported browser was detected (native,
  snap, flatpak) and whether its window-matching rule is verified.
- `fdwam doctor` checks the session, optional tools, browsers and every
  registered app (missing binaries, missing or orphaned launchers). On KDE it
  explains how to compare the real window `app_id` with the stored one.

## Configuration

`${XDG_CONFIG_HOME:-~/.config}/fdwam/config`, `key=value` lines:

| Key | Meaning | Default |
|-----|---------|---------|
| `default_browser` | browser used by `create` when none is given | first installed primary browser (brave, chrome, chromium, firefox) |
| `browser.<enum>` | path to the binary, overrides detection (e.g. `browser.brave=/opt/brave.com/brave/brave`) | – |
| `flags.<enum>` | extra arguments for every app of that browser (e.g. `flags.brave=--password-store=basic`) | empty |
| `ozone_mode` | `auto`, `wayland` or `x11` (chromium family) | `auto` on Wayland, `x11` on X11 sessions |
| `default_category` | default menu category | `Network` |

Environment variables: `FDWAM_BROWSER_<ENUM>` (e.g. `FDWAM_BROWSER_BRAVE=/path`)
overrides the binary, `FDWAM_OZONE` the window mode, `NO_COLOR` disables
colours, and the `XDG_*` variables move the directories below.

After changing the config run `fdwam regenerate --all`; launchers contain the
final command line and are not re-read from the config at start.

## Where the data is

| What | Path |
|------|------|
| registry (one `key=value` file per app) | `~/.local/share/fdwam/apps/<id>.conf` |
| icons | `~/.local/share/fdwam/icons/<id>.png` or `.svg` |
| profiles (native browsers) | `~/.local/share/fdwam/profiles/<id>/` |
| profiles (snap browsers) | `~/snap/<snap>/common/fdwam-profiles/<id>/` |
| profiles (flatpak browsers) | `~/.var/app/<flatpak-id>/data/fdwam-profiles/<id>/` |
| Epiphany profile | `~/.local/share/fdwam/profiles/org.gnome.Epiphany.WebApp_<id>/` |
| Falkon profile | `~/.local/share/fdwam/profiles/<id>/` + symlink `~/.config/falkon/profiles/fdwam-<id>` |
| launchers | `~/.local/share/applications/fdwam-<id>.desktop` |
| program (installer) | `~/.local/share/fdwam/bin/fdwam`, symlink `~/.local/bin/fdwam` |

`~/.local/share` follows `$XDG_DATA_HOME`, `~/.config` follows
`$XDG_CONFIG_HOME`. The registry is the single source of truth; launchers are
generated artefacts tagged with `X-Fdwam-Id=<id>` and fdwam only ever deletes
launchers carrying that tag.

## Supported systems

| System | Desktop / session | Status |
|--------|-------------------|--------|
| KDE Neon (Ubuntu 24.04), Plasma 6 | Wayland | ✅ tested (Brave) |
| KDE Neon / Kubuntu | X11 | ❔ untested |
| Ubuntu 24.04 GNOME | Wayland | ❔ untested |
| Fedora, Arch, Debian | any | ❔ untested (CI only: shellcheck + bats) |

## Supported browsers

| Browser | Family | Support | Installations | Tested | Known limitations |
|---------|--------|---------|---------------|--------|-------------------|
| `brave` | chromium | primary | native, snap, flatpak | ✅ yes – KDE Neon, Plasma 6.6.6, Wayland, Brave 155 snap, 2026-10-11 | – |
| `chrome` | chromium | primary | native, flatpak | ❔ no – estimated | app_id prefix `chrome` is an estimate |
| `chromium` | chromium | primary | native, snap, flatpak | ❔ no – estimated | app_id prefix `chromium` is an estimate |
| `firefox` | firefox | primary | native, snap, flatpak | ✅ yes – KDE Neon, Plasma 6.6.6, Wayland, Firefox 154.0 snap, 2026-10-11 | no native app mode; toolbars hidden by `userChrome.css`, shown on hover of the top edge |
| `vivaldi` | chromium | best effort | native, snap, flatpak | ❔ no – estimated | app_id prefix `vivaldi` is an estimate |
| `edge` | chromium | best effort | native, flatpak | ❔ no – estimated | app_id prefix `msedge` is an estimate |
| `librewolf` | firefox | best effort | native, flatpak | ❔ no – estimated | as Firefox |
| `floorp` | firefox | best effort | native, flatpak | ❔ no – estimated | as Firefox |
| `waterfox` | firefox | best effort | native, flatpak | ❔ no – estimated | as Firefox |
| `zen` | firefox | best effort | native, flatpak | ❔ no – estimated | different UI; `userChrome.css` may not hide the toolbars |
| `epiphany` | epiphany | best effort | native only | ❔ no – estimated | flatpak Epiphany is refused (it creates web apps through the portal); profile format changed between versions |
| `falkon` | falkon | best effort | native, flatpak | ❔ no – estimated | no app mode (toolbar stays); on Wayland the window groups with Falkon (`--wmclass` is X11 only) |

The source of truth for the *Tested* column is the `BROWSER_VERIFIED` table in
`bin/fdwam`; `fdwam browsers` prints it and a CI test checks that this table
and the script agree.

## Extensions and settings

Each app has its own browser profile, so extensions, site permissions
(notifications, camera, ...) and browser settings are per app.

- **Chromium family** (Brave, Chrome, Chromium, Edge, Vivaldi, Opera). The app
  window has no toolbar. Run `fdwam launch <id> --browser-mode` to open the app
  URL in a normal browser window on the same profile; it works while the app
  is running. Extensions installed there run in the app window too (without
  their toolbar icons). Site permissions are behind the icon left of the
  address. In Brave, DRM for streaming sites (Netflix) is the Widevine switch
  in `brave://settings/extensions`.
- **Firefox family.** The toolbars are hidden. Hover the top edge of the app
  window (or press Ctrl+L or Alt) to show tabs, address bar, extensions and
  the application menu over the page; *Settings* and *Add-ons* are in the
  menu. Profiles created by older fdwam versions keep the old template, which
  hides the toolbars and the window title bar: recreate the app (`fdwam delete
  <id>` and `fdwam create ...`) to get the new one.

## Wayland and taskbar icons

On Wayland a window has no icon of its own: Plasma takes it from the
`.desktop` file whose name or `StartupWMClass` equals the window's `app_id`.
Chromium-based browsers ignore `--class` on Wayland and derive the `app_id`
from the `--app` URL and the profile directory:

```
<browser>-<host>_<path with / replaced by _>-<profile-directory>
https://www.netflix.com/  +  --profile-directory=fdwam-netflix
  -> brave-www.netflix.com__-fdwam-netflix
```

fdwam always passes `--profile-directory=fdwam-<id>` and writes exactly this
value into `StartupWMClass`, so every app has a unique `app_id` even when two
apps share a URL. This was measured on KDE Neon with Brave 155 (see
`docs/research-wayland.md`); for other browsers only the prefix is estimated.

Use `--x11` (or `ozone_mode=x11`) to run the browser through XWayland with
`--class=fdwam-<id>` instead. That is the fallback when the Wayland rule does
not match, at the cost of blurry windows under fractional scaling.

## Troubleshooting

- **Wrong icon or the window groups with the browser in the panel.** Run
  `fdwam doctor`; on KDE compare the window's `resourceClass` (via
  `qdbus6 org.kde.KWin /KWin org.kde.KWin.queryWindowInfo`) with the stored
  `wm_class`. If they differ the browser changed its rule: use `--x11` or
  report the value.
- **KWallet prompt on first start (Chrome/Brave).** Add
  `--flags "--password-store=basic"` to the app or `flags.brave=--password-store=basic`
  to the config (less secure: passwords are stored unencrypted).
- **Input methods (IME) do not work.** Add `--enable-wayland-ime` via `--flags`.
- **The app does not start (snap browser).** The profile must live inside the
  snap's home (`~/snap/<snap>/common`), which fdwam does automatically. If the
  browser was switched between snap and deb afterwards, run
  `fdwam modify <id> --browser <browser>` to create a fresh profile.
- **Generic icon although the site has one.** Install ImageMagick (for ICO
  favicons) or pass `--icon PATH|URL`.
- **Ubuntu `/usr/bin/firefox` or `chromium-browser` is a snap shim.** fdwam
  detects that and treats the browser as a snap; `fdwam browsers` shows the
  result.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/lukashornych/fdwam/main/install.sh | bash -s -- --uninstall
```

This removes the program, the symlink and the bash completion. Your data stays:
run `fdwam delete <id>` for every app *before* uninstalling, or delete
`~/.local/share/fdwam/`, `~/.local/share/applications/fdwam-*.desktop` and the
snap/flatpak profile directories listed above by hand.

Developers can also use `make install PREFIX=~/.local` / `make uninstall`.

## License and acknowledgements

Apache License 2.0, see [LICENSE](LICENSE) and [NOTICE](NOTICE).

Developer documentation lives in [docs/dev/](docs/dev/). Development happens
on the `dev` branch; merges into `main` are released automatically with a
version derived from the commit messages (see [docs/dev/release.md](docs/dev/release.md)).
