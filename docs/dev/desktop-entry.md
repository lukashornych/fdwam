# Desktop entry generation

## Content

```ini
[Desktop Entry]
Type=Application
Version=1.5
Name=<name>
Comment=Web app: <url>
Exec=<quoted argv>
Icon=<absolute path | applications-internet>
Terminal=false
StartupNotify=true
StartupWMClass=<wm_class>
Categories=<category>;
X-Fdwam-Id=<id>
X-Fdwam-Browser=<enum>
```

`desktop_write` builds `ARGV` (`build_argv` → `build_argv_<family>`), writes
the file atomically to `${XDG_DATA_HOME}/applications/fdwam-<id>.desktop`,
runs `desktop-file-validate` when available (warning only) and returns the
path. `desktop_refresh` calls `update-desktop-database` and `kbuildsycoca6`
(or `5`), best effort.

## Command lines

| Family | argv |
|--------|------|
| chromium | `<exec> --user-data-dir=<profile> --profile-directory=fdwam-<id> --no-first-run --no-default-browser-check <ozone> <config flags.<enum>> <app flags> --app=<url>` (`launch --browser-mode`: plain `<url>` instead of `--app=<url>`) |
| firefox | `<exec> --no-remote --profile <profile> --name fdwam-<id> --class fdwam-<id> <flags> <url>` |
| epiphany | `<exec> --application-mode --profile=<profile> <flags> <url>` |
| falkon | `<exec> --no-remote --profile=fdwam-<id> --wmclass=fdwam-<id> <flags> <url>` |

`<ozone>`: `auto` → `--ozone-platform-hint=auto`; `wayland` →
`--ozone-platform=wayland`; `x11` → `--ozone-platform=x11 --class=fdwam-<id>`.

Flags strings are split by `split_flags` (whitespace, single and double quotes
group words; quotes are removed), so `--lang="en US"` becomes one argument.

## `Exec=` quoting (`desktop_exec_quote`)

Per argument, in this order:

1. `%` → `%%` (field codes).
2. If the argument is empty or contains a reserved character (whitespace,
   `" ' \ > < ~ | & ; $ * ? # ( )` or a backtick) it is wrapped in double quotes
   and `"`, backtick, `$` and `\` inside are escaped with a backslash.
3. The generic string escaping is applied on top: every `\` → `\\`.

Examples: `100%` → `100%%`; `a b` → `"a b"`; `$HOME` → `"\\$HOME"`;
`https://e.com/?a=b` → `"https://e.com/?a=b"`.

Verification: `gio launch` runs the generated file
and the fake browser records argv (full image), `desktop-file-validate`
validates every golden file, and `test/desktop.bats` contains an independent
reverse parser for the minimal image.

## `compute_wm_class <family> <prefix> <ozone> <url> <id>`

| Family / mode | Value | Status |
|---------------|-------|--------|
| chromium, `auto`/`wayland` | `<prefix>-<host>_<path with '/'→'_'>-fdwam-<id>`, host lower-case, port/query/fragment dropped | **verified for Brave 155** (`docs/research-wayland.md`); prefix for chrome/chromium/vivaldi/edge and the port rule are ESTIMATED |
| chromium, `x11` | `fdwam-<id>` (= `--class`) | ESTIMATED (the XWayland measurement showed `WM_CLASS` class = `--class`) |
| firefox family | `fdwam-<id>` (= `--name`) | ESTIMATED |
| epiphany | `org.gnome.Epiphany.WebApp_<id>` | ESTIMATED |
| falkon | `fdwam-<id>` (= `--wmclass`, X11 only) | documented limitation on Wayland |

Measurement: `https://www.netflix.com/` → `brave-www.netflix.com__-Default`,
`https://netflix.com/browse` → `brave-netflix.com__browse-Default`, and
`--profile-directory=fdwam-netflix` replaces `Default`. Because the host and
path are taken literally from `--app`, `modify --url` recomputes the value.

If a rule turns out to be wrong, fix it here and run `fdwam regenerate --all`.

## Default ozone mode (`ozone_default`)

`FDWAM_OZONE` → config `ozone_mode` → `x11` when `XDG_SESSION_TYPE=x11` (or
`DISPLAY` without `WAYLAND_DISPLAY`) → otherwise `auto`. Tests clear all
session variables so the default is `auto`.

## Tests

`test/desktop.bats`: golden files for every family × kind × ozone combination
and every secondary browser (`test/fixtures/desktop-golden`,
`registry-golden`; placeholders `@BIN@ @DATA@ @CONFIG@ @HOME@ @SNAP@
@SNAP_BIN@ @FLATPAK_SYSTEM@ @FLATPAK_USER@`), quoting unit tests, wm_class
unit tests, `gio launch` verification, fallback parser.
