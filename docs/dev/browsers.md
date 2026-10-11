# Browser detection

Source: section *Browser detection* in `bin/fdwam`.

## Tables

| Array | Content |
|-------|---------|
| `BROWSER_ENUM` | the 12 enum values; order = default-browser preference (primary first) |
| `BROWSER_FAMILY` | `chromium`, `firefox`, `epiphany`, `falkon`; selects `build_argv_<family>`, profile layout and `compute_wm_class` rule |
| `BROWSER_SUPPORT` | `primary` (tested on KDE Neon) or `secondary` (best effort) |
| `BROWSER_NATIVE` | binary names tried with `type -P` in order |
| `BROWSER_SNAP` | snap name (`/snap/bin/<name>`) |
| `BROWSER_FLATPAK` | flatpak app ids (export wrappers `<root>/exports/bin/<id>`) |
| `BROWSER_PREFIX` | Wayland `app_id` prefix of the chromium family (`brave` verified, others ESTIMATED) |
| `BROWSER_VERIFIED` | environment in which the window matching was verified by hand; empty = unverified. Shown by `fdwam browsers`, mirrored in the README (checked by `test/readme.bats`) |

## `browser_resolve <enum>`

Sets `BR_ENUM BR_FAMILY BR_SUPPORT BR_KIND BR_EXEC BR_SNAP_NAME BR_FLATPAK_ID BR_PREFIX`.
Order:

1. override: `FDWAM_BROWSER_<ENUM>` env, then config `browser.<enum>` (must be executable, else exit 4),
2. native names in `PATH` (`type -P`), each classified by `browser_classify_exec`,
3. `$FDWAM_SNAP_BIN_DIR/<snap>` (default `/snap/bin`),
4. flatpak export wrappers, system root before user root.

Returns 4 with a message listing what was searched when nothing is found.
Flatpak Epiphany is refused (it creates web apps through the portal).

## Shim detection (`browser_classify_exec`)

A native hit is reclassified as **snap** when

- the path lies in `FDWAM_SNAP_BIN_DIR`, or
- `readlink -f` resolves under `FDWAM_SNAP_PREFIX` (default `/snap/`), or
- `readlink -f` ends in a file named `snap` (the launcher `/usr/bin/snap`), or
- it is a shell script containing `<snap-bin-dir>/` (Ubuntu's transitional
  `/usr/bin/chromium-browser`, `/usr/bin/firefox`).

The snap name comes from `/snap/bin/<snap>[.<app>]`, from the script's
`/snap/bin/<name>` reference, or from the `BROWSER_SNAP` table as a last
resort. `snap_name_from_bin` follows the symlink chain one hop at a time (max
16, relative targets resolved against the link's directory) and takes the last
link inside `FDWAM_SNAP_BIN_DIR`, so both
`/usr/bin/brave-browser → /etc/alternatives/brave-browser → /snap/bin/brave → /usr/bin/snap`
and aliases (`/snap/bin/<alias> → <snap>.<app>`) give the right name. It
decides the profile location
(`~/snap/<snap>/common/fdwam-profiles/<id>`).

**`BR_EXEC` always keeps the unresolved path** returned by `type -P`.
`/snap/bin/chromium` is a symlink to `/usr/bin/snap`, which dispatches on
`argv[0]`; the resolved path would start a bare `snap`. Tests assert that the
fake browser is started as `$BIN/brave`, not as `fake-browser`.

## Tests

`test/browsers.bats`: priority order, snap shims (three variants), snap name
derivation, env and config override, missing browser (exit 4), flatpak
Epiphany refusal, default browser order.

## Adding a browser

1. Add the enum value to `BROWSER_ENUM` and a row to each table (family,
   support, natives, snap, flatpak, prefix for chromium family).
2. A new family additionally needs `build_argv_<family>`, a case in
   `compute_wm_class`, `profile_locate`/`profile_create` handling and a case in
   `cmd_show`'s family list.
3. Add a golden test in `test/desktop.bats` and a fake binary name to
   `FAKE_NATIVE_BROWSERS` in `test/test_helper.bash`.
4. Add the row to the README table (`test/readme.bats` enforces it) and to
   `completions/fdwam.bash`.
