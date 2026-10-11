# Favicon pipeline and site name

## Download

`http_fetch <url> <out>` uses `curl -fsSL --max-time 15 -A <desktop UA> -w '%{url_effective}'`
and prints the effective URL after redirects; with `wget` as fallback the
original URL is printed. All relative references are resolved against the
effective URL (`url_resolve`: absolute, protocol-relative `//`, root-relative
`/`, relative).

## Candidates (`site_fetch_metadata <url>` → `META_CANDIDATES`, `META_NAME`)

The first 400 kB of the page are scanned for `<link>` and `<meta>` tags
(`grep -oiE`, attributes via `html_attr`, which accepts double, single or no
quotes). Each candidate is a line `prio|size|label|url`:

| prio | Source | Size |
|------|--------|------|
| 1 | Web App Manifest icons (`<link rel="manifest">`; `jq` or the grep/sed fallback parser in `manifest_collect`) | from `sizes` |
| 2 | `<link rel="apple-touch-icon">` | `sizes` or 180 |
| 3 | `<link rel="icon">` / `shortcut icon` | `sizes`; SVG counts as 1024 |
| 4 | `<origin>/favicon.ico` (always added) | 0 |

Sorted by prio, then size descending, deduplicated by URL. Third-party icon
services are deliberately not used.

Name: `--name` → `og:site_name` → `<meta name="application-name">` → manifest
`short_name`/`name` → `titleize(slug)`. Entities are decoded by
`html_unescape` (sed, because `&` is special in bash 5.2 pattern substitution).

## Normalisation (`icon_obtain <url|path>`)

1. download or copy to the temp dir,
2. `image_type` from magic bytes (`od`): png, jpeg, gif, ico, webp, bmp; SVG by
   `<svg` in the first 4 kB; `file --mime-type` as a last resort,
3. PNG and SVG are used as is; ICO/JPEG/GIF/WebP/BMP are converted by
   ImageMagick (`magick` or `convert`) with `-resize '256x256>'` (never
   upscaled); for ICO the largest layer is selected with `identify`,
4. without ImageMagick these types are skipped (a marker file
   `needs-converter` makes `create` suggest installing ImageMagick) and the
   next candidate is tried.

`icon_pick_best` walks the sorted candidates and returns the first usable one.
`icon_install` copies it to `icons/<id>.png|svg`. When every automatic
candidate fails the `.desktop` gets `Icon=applications-internet` and `create`
prints a warning but **never fails** because of the favicon (the same holds for
a page candidate picked in the wizard, `icon_is_page_candidate`).

An explicit `--icon` is different (`create` and `modify`): a missing local file
is a usage error (exit 2, checked while parsing by `icon_source_valid`), a URL
that cannot be downloaded or converted exits 1 (`die_icon_unusable`, with an
ImageMagick hint when a converter was missing). Both happen before anything is
written. `create_needs_metadata` downloads the page only when the name is
missing or the icon is automatic, so `--name` with `--no-icon` or any `--icon`
works without fetching the page.

Temp files live in `TMP_ROOT` (created by `ensure_tmp` in the main shell, never
inside `$(...)`, and removed by the EXIT trap).

## Tests

`test/icons.bats` runs a `python3 -m http.server` on `127.0.0.1:18791` with
fixtures in `test/fixtures/html`: manifest, apple-touch-icon with a
protocol-relative URL, relative links, SVG preference, ICO-only (converted in
the full image, generic icon in the minimal image), no icon, unreachable server,
`--icon URL`, `--refresh-icon`, magic byte detection, wget fallback. These
tests never compare golden `.desktop` files (the port would change the
`app_id`).
