# Release

Releases are automatic and follow the same model as
[lukashornych/hole](https://github.com/lukashornych/hole): the version is
resolved from the commit messages, nobody edits a version number by hand.

## Branches

- `dev` is the integration branch: CI (`.github/workflows/ci.yml`) runs on
  every push to `dev` and on pull requests to `dev` and `main`.
- `main` is the release branch: every push (a merge from `dev`) runs
  `.github/workflows/release.yml`, which publishes a release.

## Version resolution

`codacy/git-version` looks at the commits since the last tag on `main` and
applies [Conventional Commits](https://www.conventionalcommits.org/):

| Commit message | Bump |
|----------------|------|
| `feat!: …`, `fix(scope)!: …`, or a `BREAKING CHANGE:` footer | major |
| `feat: …`, `feat(scope): …` | minor |
| anything else (`fix:`, `docs:`, `chore:`, …) | patch |

The resolved version is tagged (`vX.Y.Z`, annotated), release-drafter publishes
the release notes from the merged pull requests (`.github/release-drafter.yml`),
and the workflow uploads the assets.

## Assets

`make dist VERSION=vX.Y.Z` (the same target the workflow runs) produces
`dist/fdwam` with the version stamped in place of `development`, `dist/fdwam.bash`
(bash completion) and `dist/SHA256SUMS`. `install.sh` downloads exactly these
three names from `releases/latest/download/` (or `releases/download/<tag>/`)
and verifies the checksums. The `release-config` CI job builds the assets on
every change so that a broken `make dist` is caught before a push to `main`.

In the repository `fdwam version` prints `fdwam development, Apache-2.0`; only
the released copy carries a number (`test/readme.bats` checks both).

## Checklist before merging `dev` into `main`

1. CI green on `dev` (`make lint test test-minimal` locally does the same).
2. Commit messages on the merged work follow Conventional Commits, otherwise
   the bump is a patch.
3. README tables (supported browsers / systems) and `BROWSER_VERIFIED` are
   current; the README test keeps them consistent with the script.
4. After the release: `curl -fsSL https://raw.githubusercontent.com/lukashornych/fdwam/main/install.sh | bash`
   must print `checksum OK` and the new version. When browser-related code
   changed, run a manual check on KDE Neon with Brave: create an app, launch
   it from the menu and verify the taskbar icon, that the window does not group
   with a regular Brave window, and that pinning to the task manager works.
