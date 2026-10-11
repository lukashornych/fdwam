# Registry

One file per app: `${XDG_DATA_HOME:-~/.local/share}/fdwam/apps/<id>.conf`.

## Format

`key=value`, one per line, fixed order (`REG_FIELDS`):

| Field | Meaning |
|-------|---------|
| `id` | launcher id, `^[a-z0-9][a-z0-9-]{0,39}$` |
| `name` | display name (`Name=`) |
| `url` | normalised URL (scheme and host lower-case, path at least `/`) |
| `browser` | enum value |
| `browser_kind` | `native`, `snap`, `flatpak` |
| `browser_exec` | unresolved executable path used in `Exec=` |
| `family` | `chromium`, `firefox`, `epiphany`, `falkon` |
| `profile_dir` | absolute profile directory |
| `profile_link` | Falkon only: symlink in `~/.config/falkon/profiles` |
| `icon` | absolute icon path or empty (generic icon) |
| `wm_class` | computed `StartupWMClass` |
| `ozone` | `auto`, `wayland`, `x11` |
| `category` | `Categories=` without the trailing `;` |
| `flags` | per-app extra flags (string, split with quote support at build time) |
| `created`, `modified` | ISO 8601 UTC; `FDWAM_NOW` overrides the clock in tests |
| `version` | registry format version (`REGISTRY_FORMAT_VERSION`, currently `1`) |

Values are written through `sanitize_line` (control characters and newlines
removed), so a value is always one line. The writer is atomic.

## Parser

`registry_read` reads lines matching `^([a-z_]+)=(.*)$` and stores the value
literally in the associative array `APP`. Unknown keys are kept, malformed
lines ignored, the file is **never** `source`d. `test/registry.bats` checks
that `$(...)` and backticks in values are not executed, including a
hand-crafted file.

## Format changes

Bump `REGISTRY_FORMAT_VERSION` when a field changes meaning. `registry_read`
initialises every known field to `""` first, so new fields are backwards
compatible; a migration can branch on `APP[version]` inside `registry_read`.

## IDs

`slug_from_url`: host → drop a generic `www.`/`app.` first label (when more
than two labels remain) → drop the public suffix (`com`, or `co.uk`-style
two-level suffixes with a 2-letter country code) → join labels with `-` →
restrict to `[a-z0-9-]`, max 40 chars. `netflix.com` → `netflix`,
`mail.google.com` → `mail-google`, `news.bbc.co.uk` → `news-bbc`.

`id_unique` appends `-2`, `-3`, … while the registry entry **or** the
`.desktop` file exists. Both checks live in the silent predicate
`id_available` (reason in `ID_TAKEN_REASON`), which `create --id` (exit 2) and
the wizard's `validate_new_id` use as well. IDs are case-sensitive (tests run
in `/tmp`, not on a
case-insensitive bind mount).
