# Testing

## Running

| Command | What |
|---------|------|
| `make test` | builds `test/docker/Dockerfile` (Ubuntu 24.04 + all optional tools) and runs all bats files with `--network none` as the calling uid |
| `make test-minimal` | same with `Dockerfile.minimal` (bash, coreutils, curl, python3 only): degradation paths run, tool-dependent tests `skip` |
| `make test-local` | bats directly on the host (Linux only; macOS lacks bash 4+, GNU tools, `desktop-file-validate`, `gio`) |
| `make lint` / `make lint-local` | shellcheck (`-S warning`) on every shell file |
| `make golden` | rewrites the golden files (`FDWAM_UPDATE_GOLDEN=1`); review the diff |
| `TESTS=test/wizard.bats make test` | a single file |

bats is **not** installed in the images; the pinned submodule `test/bats`
(v1.14.0) plus `test/bats-support` and `test/bats-assert` are used everywhere.
Clone with `git clone --recurse-submodules` or run `git submodule update --init`.

The images refuse `gawk` (`awk` must be `mawk`, as on KDE Neon). Containers run
as the host uid with `HOME=/tmp/home`; the repository is bind-mounted at
`/src`, but all test `HOME`s and temp files are in the container's `/tmp`
(case-sensitive, fast).

## Hermetic helper (`test/test_helper.bash`)

`fdwam_setup` (called from `setup`):

- `unset "${!FDWAM_@}"` (only `FDWAM_UPDATE_GOLDEN` survives), clears
  `XDG_SESSION_TYPE WAYLAND_DISPLAY DISPLAY XDG_CURRENT_DESKTOP DBUS_SESSION_BUS_ADDRESS`,
  sets `LC_ALL=C.UTF-8 TZ=UTC NO_COLOR=1`,
- own `HOME`, `XDG_DATA_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`,
  `XDG_STATE_HOME`, `XDG_RUNTIME_DIR` (0700) under `$BATS_TEST_TMPDIR`,
- `PATH` = `test/stubs` : `$BIN` (fake browsers) : system PATH without
  anything under the developer's real home (`ORIG_HOME`, saved before `HOME`
  is replaced), `~/.local/bin`, `/snap/bin`, flatpak exports and `/opt`,
- fake snap root (`FDWAM_SNAP_BIN_DIR`, `FDWAM_SNAP_PREFIX`) and flatpak roots
  (`FDWAM_FLATPAK_SYSTEM_DIR`, `FDWAM_FLATPAK_USER_DIR`),
- `FDWAM_NOW=2026-10-11T10:00:00Z`, `FDWAM_TEST_LOG`, `FDWAM_TEST_CALLS`.

Helpers: `make_fake_snap`, `make_fake_flatpak`, `remove_fake_browser`,
`write_config`, `source_fdwam`, `create_offline`, `assert_golden`,
`browser_log_argv0/args`, `desktop_value`, `skip_without`.

## Stubs (`test/stubs`)

- `fake-browser`: symlinked under real browser names; writes `$0` and one
  argument per line to `$FDWAM_TEST_LOG`.
- `kbuildsycoca6`, `kbuildsycoca5`, `update-desktop-database`: append their
  name and arguments to `$FDWAM_TEST_CALLS`. Tests never touch a real Plasma
  session.

## Golden files

`test/fixtures/desktop-golden/*.desktop` and `registry-golden/*.conf`.
`assert_golden` replaces temp paths with placeholders from the longest path to
the shortest (`@FLATPAK_SYSTEM@`, `@FLATPAK_USER@`, `@SNAP_BIN@`, `@SNAP@`,
`@CONFIG@`, `@DATA@`, `@BIN@`, `@HOME@`). Golden tests run offline (fixed
`https://` URL, `--name`, `--no-icon`).

## Test hooks in the script

| Variable | Effect |
|----------|--------|
| `FDWAM_FORCE_INTERACTIVE=1` | wizard without a tty (answers via stdin) |
| `FDWAM_NOW` | fixed timestamp |
| `FDWAM_SNAP_BIN_DIR`, `FDWAM_SNAP_PREFIX`, `FDWAM_FLATPAK_SYSTEM_DIR`, `FDWAM_FLATPAK_USER_DIR` | fake sandbox roots |
| `FDWAM_RELEASE_BASE_URL`, `FDWAM_DOWNLOADER` | installer: fake release server, force curl/wget |
| `FDWAM_UPDATE_GOLDEN=1` | rewrite golden files |
| `fdwam browsers --porcelain` | machine-readable detection output (README test) |

## Files

| File | Phase / content |
|------|-----------------|
| `cli.bats` | help, version, exit codes, sourcing |
| `browsers.bats` | detection, shims, overrides |
| `registry.bats` | parser safety, round trips, ids |
| `desktop.bats` | golden files, quoting, wm_class, `gio launch`, fallback parser |
| `profiles.bats` | profile layout, delete |
| `icons.bats` | favicon pipeline against a local HTTP server (port 18791) |
| `commands.bats` | end-to-end lifecycle, rollback, menu refresh, regenerate, modify, doctor |
| `wizard.bats` | stdin-driven wizard, PTY smoke test |
| `install.bats` | installer against a fake release server (port 18792) |
| `readme.bats` | README ↔ script consistency |

## CI

`.github/workflows/ci.yml` runs on pushes to `dev` and on pull requests to
`dev`/`main`: `lint`, `test` and `test-minimal` build the same Dockerfiles as
`make` (cached with the GitHub Actions cache, `NO_BUILD=1` because the action
already built the image), `release-config` checks `make dist` and the installer
syntax, and an optional Fedora/Arch matrix covers detection and `.desktop`
validation. Releases are produced by `.github/workflows/release.yml` on pushes
to `main`, see [release.md](release.md).
