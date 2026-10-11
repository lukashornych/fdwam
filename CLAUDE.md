# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

fdwam (freedesktop web app manager) turns a web site into a desktop app: a generated `.desktop` launcher, an isolated browser profile and the site's favicon as icon. The whole tool is a single Bash script, `bin/fdwam` (~2400 lines); `install.sh` is the curl-pipe installer and `completions/fdwam.bash` the bash completion. Developer docs live in `docs/dev/` (one file per script section) and are the reference for details; every public function in the script has a header comment that the docs point to instead of repeating.

## Commands

Tests use bats from git submodules (`test/bats`, `test/bats-support`, `test/bats-assert`); run `git submodule update --init` if they are empty. bats is not installed system-wide.

| Command | Purpose |
|---------|---------|
| `make test` | full suite in Docker (Ubuntu 24.04, all optional tools, `--network none`) |
| `make test-minimal` | same in the minimal image (bash, coreutils, curl, python3); tool-dependent tests `skip` |
| `make test-local` | bats directly on the host (Linux only) |
| `TESTS=test/wizard.bats make test-local` | one test file |
| `./test/bats/bin/bats test/cli.bats -f '<regex>'` | single test by name |
| `make lint` / `make lint-local` | `shellcheck -S warning` on all shell files (+ `bash -n`) |
| `make golden` | rewrite golden files in `test/fixtures/*-golden/` (`FDWAM_UPDATE_GOLDEN=1`); review the diff |
| `make dist VERSION=vX.Y.Z` | release assets in `dist/` (version stamped over `FDWAM_VERSION="development"`, SHA256SUMS) |

The Docker images use `mawk`, not `gawk` — awk code must stay POSIX/mawk-compatible.

## Architecture

`bin/fdwam` is organized in fixed sections, in order: constants → logging → util → config → browser detection → registry → desktop entry → profiles → icons → commands (`cmd_*`) → wizard (`step_*`, `wizard_*`) → main. See `docs/dev/architecture.md` for the section table and the create/modify/delete/regenerate data flow.

Key invariants (break these and tests or safety guarantees fail):

- **Sourceable script.** Strict mode and traps are installed only when executed (`[[ "${BASH_SOURCE[0]}" == "$0" ]]`); tests `source` the script to call functions directly.
- **No `eval`, no `source` of data.** Registry (`$XDG_DATA_HOME/fdwam/apps/<id>.conf`) and config (`~/.config/fdwam/config`) are parsed by regex; the browser is started via an argv array, never `sh -c`.
- **Registry is the single source of truth.** `.desktop` files (`fdwam-<id>.desktop`) are generated from it and tagged `X-Fdwam-Id=<id>`; only tagged files are ever deleted.
- **Atomic writes + rollback.** `atomic_write` writes temp-then-`mv`. `create_commit` lists in `ROLLBACK_PATHS` only paths it is about to create; the EXIT trap removes them on failure. Command substitutions that write files need `|| exit "$?"` (`inherit_errexit` doesn't propagate `die` out of `$(...)`).
- **Validate, then mutate.** Arguments, icon source and browser are resolved before anything is written; the wizard writes nothing before the summary is confirmed.
- **Output channels.** Results on stdout (`say`), progress/prompts/warnings on stderr.
- **Everything derives from `TOOL="fdwam"`** (data dir, `X-Fdwam-*` keys, `FDWAM_*` env vars, `fdwam-<id>` profile dirs and window classes).
- **Exit codes:** 0 ok, 1 general error, 2 usage, 3 unknown app id, 4 browser not found/unsupported.

Browsers are table-driven (`BROWSER_ENUM`, `BROWSER_FAMILY`, `BROWSER_NATIVE`, `BROWSER_SNAP`, `BROWSER_FLATPAK`, `BROWSER_PREFIX`, `BROWSER_VERIFIED`). The family (`chromium`, `firefox`, `epiphany`, `falkon`) selects `build_argv_<family>`, the profile layout and the `compute_wm_class` rule. Detection order: env/config override → native in PATH → snap → flatpak (`docs/dev/browsers.md`). Snap browsers keep profiles inside the snap home.

Wayland window matching: Chromium-family browsers derive `app_id` as `<prefix>-<host>_<path>-<profile-directory>`; fdwam always passes `--profile-directory=fdwam-<id>` and writes that value into `StartupWMClass`. `--x11` falls back to XWayland with `--class=fdwam-<id>`. Background measurements are in `docs/research-wayland.md`.

## Tests

`test/test_helper.bash` (`fdwam_setup`) builds a hermetic environment per test: own `HOME`/XDG dirs, all `FDWAM_*` vars unset, PATH stripped of real browsers, fake browsers (`test/stubs/fake-browser` logs argv to `$FDWAM_TEST_LOG`), stubbed `kbuildsycoca*`/`update-desktop-database` (log to `$FDWAM_TEST_CALLS`), and fake snap/flatpak roots. Test-only hooks in the script: `FDWAM_FORCE_INTERACTIVE=1` (wizard reads answers from stdin), `FDWAM_NOW`, `FDWAM_SNAP_*`, `FDWAM_FLATPAK_*`, `FDWAM_RELEASE_BASE_URL`/`FDWAM_DOWNLOADER` (installer). `icons.bats` and `install.bats` start local HTTP servers on ports 18791/18792. See `docs/dev/testing.md` for the helper list.

`test/readme.bats` enforces README ↔ script consistency: the README browser table must match `fdwam browsers --porcelain` (incl. `BROWSER_VERIFIED`), and every command and config key must be documented. Update `README.md` whenever browsers, commands or config keys change.

## Release & branches

Development happens on `dev`; merges into `main` release automatically (`.github/workflows/release.yml`). The version comes from Conventional Commit messages (`feat:` → minor, `!`/`BREAKING CHANGE:` → major, anything else → patch), so commit messages must follow that format. Nobody edits version numbers by hand; the repo copy always reports `development`.

## Licensing constraint

Apache-2.0. Linux Mint's webapp-manager (GPL-3.0) may be used only for facts (binary names, flatpak ids, flags) — never copy its code. The Firefox `userChrome.css` is written from scratch; do not embed MPL-licensed CSS.
