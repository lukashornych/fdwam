# Architecture

`bin/fdwam` is one Bash script (~2300 lines) split into sections in this order:

| Section | Content |
|---------|---------|
| constants | `TOOL`, version, exit codes, XDG paths, sandbox roots (`FDWAM_SNAP_*`, `FDWAM_FLATPAK_*`), categories, ozone modes |
| logging | `say` (stdout, results), `log_info` (stderr, progress), `log_warn`, `log_error`, `log_debug` (`-v`), `die` |
| util | temp dir (`ensure_tmp`), rollback, `atomic_write`, string helpers, URL helpers (`url_normalize`, `url_host`, `url_path`, `url_resolve`), `html_unescape` |
| config | `config_load` / `config_get` (`~/.config/fdwam/config`) |
| browser detection | candidate tables, `browser_resolve`, `browser_classify_exec`, `browser_default`, `browsers_installed` ([browsers.md](browsers.md)) |
| registry | `registry_read/write/list/delete`, `slug_from_url`, `id_valid`, `id_unique` ([registry.md](registry.md)) |
| desktop entry | `compute_wm_class`, `build_argv_<family>`, `desktop_exec_quote`, `desktop_content`, `desktop_write`, `desktop_refresh` ([desktop-entry.md](desktop-entry.md)) |
| profiles | `profile_locate`, `profile_create`, `profile_delete`, Firefox template ([profiles.md](profiles.md)) |
| icons | `http_fetch`, `site_fetch_metadata`, `manifest_collect`, `image_type`, `image_to_png`, `icon_obtain`, `icon_pick_best`, `icon_install` ([icons.md](icons.md)) |
| commands | `cmd_create`, `cmd_list`, `cmd_show`, `cmd_modify` (+ `modify_apply`), `cmd_delete`, `cmd_launch`, `cmd_regenerate`, `cmd_browsers`, `cmd_doctor` |
| wizard | `prompt_text`, `prompt_choice`, `step_*`, `wizard_create`, `wizard_modify` ([wizard.md](wizard.md)) |
| main | `cmd_help`, `cmd_version`, `main`, guarded entry point |

Every public function has a header comment (purpose, arguments, output, return
code). This documentation refers to those comments instead of repeating them.

## Principles

- **Strict mode** (`set -Eeuo pipefail`, `shopt -s extglob nullglob inherit_errexit`)
  and the traps are installed only when the script is executed, not when it is
  sourced by tests (`[[ "${BASH_SOURCE[0]}" == "$0" ]]`).
- **No `eval`, no `source` of data.** The registry and the config are parsed by a
  regex (`^[a-z_]+=`) and values are used literally. The browser is started via
  an argv array (`exec "${ARGV[@]}"`), never through `sh -c`.
- **Atomic writes.** `atomic_write` writes to a `mktemp` file in the target
  directory and `mv`s it. A failure anywhere exits non-zero (`die`); command
  substitutions that write files are followed by `|| exit "$?"` because
  `inherit_errexit` alone does not propagate `die` out of `$(...)`.
- **Rollback.** `create_commit` sets `CREATE_IN_PROGRESS=1` and lists in
  `ROLLBACK_PATHS` only the paths it is about to create (a pre-existing profile
  directory, `.desktop` file, icon or registry file is never listed). The EXIT
  trap removes them when the exit status is non-zero. Nothing is written in the
  wizard before the summary is confirmed.
- **Validate, then mutate.** `create` checks `--id` (`id_available`), `--icon`
  (`icon_source_valid`), the URL and `--flags` while parsing; `modify_apply`
  obtains a new icon and resolves a new browser before it touches the profile.
- **Temp dir.** `TMP_ROOT` is removed by the EXIT trap and by `cmd_launch`
  right before `exec` (which never returns to the trap).
- **Registry is the single source of truth**; `.desktop` files are generated
  and carry `X-Fdwam-Id=<id>`. Only files with that tag are ever deleted.
- **Everything is derived from `TOOL="fdwam"`:** command name, data directory,
  `X-Fdwam-*` keys (`X_KEY_PREFIX`), `FDWAM_*` variables (`tool_env`),
  `fdwam-<id>` profile directory names and window classes.
- **Logging never includes profile content or cookies**, only ids, URLs and paths.
- **Output channels:** results on stdout (`say`), prompts and progress on
  stderr. `fdwam create ... | something` therefore only sees `Created '<id>' -> <path>`.

## Data flow

```
create ─┬─ parse args ──► W (wanted values) ─┬─ non-interactive: create_defaults
        │                                    └─ wizard: step_1..8 ──► step_summary
        │
        └─► create_commit:
              wizard_fill_app     W + BR_* ──► APP (profile_dir, wm_class, ...)
              resolve_icon_into_app          candidates / --icon / generic
              profile_create                 family specific
              registry_write                 apps/<id>.conf   (atomic)
              desktop_write                  applications/fdwam-<id>.desktop (atomic, validated)
              profile_post_desktop           Epiphany copies the .desktop into the profile
              desktop_refresh                update-desktop-database, kbuildsycoca6 (best effort)

modify ──► registry_read ──► modify_apply (M, new browser, new icon) ──► registry_write ──► desktop_write
delete ──► registry_read ──► confirm ──► desktop_remove, icon_remove, profile_delete, registry_delete
regenerate ──► registry_read ──► browser_resolve ──► compute_wm_class ──► registry_write ──► desktop_write
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | success |
| 1 | general error (download, write, validation inside the wizard aborted, explicit `--icon` URL that cannot be downloaded or converted) |
| 2 | wrong usage / arguments (incl. `--icon` file not found, `--id` already taken, control characters in the URL or `--flags`) |
| 3 | unknown app id |
| 4 | browser not found / not executable / unsupported (flatpak Epiphany) |

## License boundaries

The project is Apache-2.0: **no code may be copied from GPL-licensed
projects**, only facts (binary names, flatpak ids, browser flags). The Firefox `userChrome.css` is written from scratch (MrOtherGuy's MPL-2.0 CSS
is not used, because embedding it in the script would make the whole script a
"Modification" under the MPL).
