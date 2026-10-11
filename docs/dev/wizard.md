# Interactive wizard

Entered by `fdwam create` without `<url>` on a terminal, by `-i`, or by
`fdwam modify <id>` without change options on a terminal. A terminal means
`[[ -t 0 && -t 1 ]]`; `FDWAM_FORCE_INTERACTIVE=1` forces it for tests.

## Primitives

- `wizard_read <prompt> <prefill>`: on a tty `read -r -e [-i prefill] -p`;
  otherwise the prompt is printed to stderr and a plain `read -r` is used.
  Returns 1 on EOF.
- `prompt_text <label> <default> <validator> [prefill]`: shows `label [default]: `,
  empty answer = default, validator prints the canonical value (or a reason to
  stderr and returns 1 → the question repeats).
- `prompt_choice <label> <default> <options...>`: numbered list; accepts the
  number, the full option text or its first word (case-insensitive).

**Rule: an empty answer always means the default**, regardless of prefill.
Without a tty readline and `-i` are unavailable, so behaviour must not depend
on the prefill. Prompts go to stderr, so stdout stays usable for results.

## Steps (`run_step <n> [force]`)

| # | Step | Default | Validator |
|---|------|---------|-----------|
| 1 | URL (then metadata fetch) | current (modify) | `validate_url` |
| 2 | Browser (installed ones only, best-effort marked) | current / `default_browser` / first installed | number or name |
| 3 | Name | site name / titleized slug | `validate_name` |
| 4 | ID (create only) | `id_unique(slug)` | `validate_new_id` |
| 5 | Category | config `default_category` / Network | main category, number or case-insensitive name |
| 6 | Icon | best candidate; modify: keep current / generic | candidates, custom path or URL, generic |
| 7 | Window mode (chromium family only) | `ozone_default` | `auto wayland x11` |
| 8 | Extra flags (`-` clears in modify) | empty / current | – |
| 9 | Summary with `Exec=` preview, `Y/n/e` (`e` → step number) | Y | – |
| 10 | Launch now? (create only) | N | – |

Steps whose value came from arguments (`W_SET[key]`) are skipped on the first
pass; `e` forces them. Values live in the associative array `W`; `wizard_fill_app`
turns `W` + `BR_*` into `APP` for the preview and for `create_commit`.

Nothing is written before step 9 is confirmed. Ctrl+C triggers the INT trap
(exit 130, temp dir removed); EOF makes the current prompt return 1 and
`wizard_abort` exits 1 with "aborted, nothing was written". `n` in the summary
exits 0 without writing.

`wizard_modify` works the same with the current values as defaults, skips the
ID step, prefills with `read -e -i` on a tty (Ctrl+U clears), and ends by
diffing `W` against `APP` and calling `modify_apply` with only the changes.

## Tests

`test/wizard.bats`: answers through stdin (defaults, numeric and named browser
choice, invalid URL/category repeat, ID collision, `n`, EOF, `e`, summary
content, launch, argument skipping with `-i`, `-y`, icon custom path, modify
wizard) and a PTY smoke test with `script -qec` that sends keys with small
delays to exercise readline and Ctrl+U.
