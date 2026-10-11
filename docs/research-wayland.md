# Wayland window matching (measurements)

How a Chromium-family browser names an `--app` window on Wayland, and how a
`.desktop` file is paired with it. The results drive `compute_wm_class` in
`bin/fdwam` and are summarised in `docs/dev/desktop-entry.md`.

## Environment

- Brave 155.1.97.56 (snap, started as `brave`)
- KDE Plasma 6.6.6, Wayland session, fractional scaling (e.g. 150 %)
- No `~/.config/brave-flags.conf`

Window properties were read with KWin's `queryWindowInfo`. The backend is
determined by `clientMachine`: empty = native Wayland, `localhost` = X11/XWayland.

## Variants

All variants opened `https://www.netflix.com/` with `--app` unless noted.

| Variant | Backend | resourceClass / app_id | resourceName | Note |
|---------|---------|------------------------|--------------|------|
| A default flags | Wayland | `brave-www.netflix.com__-Default` | `brave` | Brave runs natively on Wayland without flags. |
| B `--ozone-platform=wayland` | Wayland | `brave-www.netflix.com__-Default` | `brave` | Same as A. |
| C wayland + `--class` | Wayland | `brave-www.netflix.com__-Default` | `brave` | `--class` is ignored on Wayland. |
| D wayland + `--profile-directory` | Wayland | `brave-www.netflix.com__-fdwam-netflix` | `brave` | Last segment = `--profile-directory`. |
| E wayland, `https://netflix.com/browse` | Wayland | `brave-netflix.com__browse-Default` | `brave` | Taken from the `--app` URL; redirects have no effect. |
| F `--ozone-platform-hint=auto` | Wayland | `brave-www.netflix.com__-Default` | `brave` | Same as A. |
| G `--ozone-platform=x11 --class` | X11 (XWayland) | `fdwam-test` | `www.netflix.com` | `WM_CLASS` class = `--class`, instance = host. |

For A–F a `.desktop` file with `StartupWMClass=<app_id>` was launched from the
menu with a regular Brave window open. In every case the taskbar showed the
right icon, the window did not group with regular Brave, and pinning to the
task manager and launching from the pinned icon worked. G was not checked.

## Findings

- **app_id shape:** `<prefix>-<host>_<path with '/' → '_'>-<profile-directory>`.
  - `https://www.netflix.com/` → `brave-www.netflix.com__-Default`
  - `https://netflix.com/browse` → `brave-netflix.com__browse-Default`
  - Host and path are taken literally from the `--app` URL (no `www`
    normalisation), so changing the URL in `modify` must recompute
    `StartupWMClass`.
  - The prefix is `brave` for the snap as well.
- **`--class`** is ignored on Wayland.
- **`--profile-directory`** replaces the last segment, so
  `--profile-directory=fdwam-<id>` makes the app_id unique even for two apps
  with the same URL.
- **Pairing** only needs `StartupWMClass`; the `.desktop` file name does not
  have to match the app_id.
- **Ozone flags** are not needed for Brave 155. `--ozone-platform-hint=auto` is
  harmless and kept for older versions; `--ozone-platform=wayland` is not forced.
- **Snap profiles** live under `~/snap/brave/common/`.
- **X11 mode** (`--ozone-platform=x11 --class=fdwam-<id>`,
  `StartupWMClass=fdwam-<id>`) remains an unverified fallback; blurriness under
  fractional scaling was not tested.

## Implications

- `compute_wm_class` for the chromium family on Wayland follows the shape above.
  Only the `brave` prefix is verified; chrome, chromium, vivaldi and edge are
  ESTIMATED.
- fdwam always passes `--profile-directory=fdwam-<id>`, e.g.
  `brave-www.netflix.com__-fdwam-netflix`.
- For a snap install the main binary is `brave` (`/snap/bin/brave`).
