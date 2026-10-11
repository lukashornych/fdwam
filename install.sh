#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
#
# Installer / updater / uninstaller for fdwam (no sudo, everything in $HOME).
#
#   curl -fsSL https://raw.githubusercontent.com/lukashornych/fdwam/main/install.sh | bash
#   curl -fsSL .../install.sh | bash -s -- --uninstall
#
# Options:
#   --uninstall       remove the program, the symlink and the completion (data stays)
#   --prefix DIR      directory for the `fdwam` symlink (default ~/.local/bin)
#   --no-completion   skip the bash completion
#   -h, --help
#
# Environment:
#   FDWAM_VERSION           latest (default) | vX.Y.Z | main (development, unchecked)
#   FDWAM_RELEASE_BASE_URL  base URL of the repository (test hook)
#   FDWAM_DOWNLOADER        curl | wget (test hook, default: curl, fallback wget)

set -Eeuo pipefail

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4) )); then
  printf 'install.sh: bash >= 4.4 is required (found %s)\n' "$BASH_VERSION" >&2
  exit 1
fi

TOOL="fdwam"
REPO="lukashornych/fdwam"
BASE_URL="${FDWAM_RELEASE_BASE_URL:-https://github.com/$REPO}"
VERSION="${FDWAM_VERSION:-latest}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DATA_DIR="$XDG_DATA_HOME/$TOOL"
INSTALL_DIR="$DATA_DIR/bin"
TARGET="$INSTALL_DIR/$TOOL"
PREFIX="$HOME/.local/bin"
COMPLETION_DIR="$XDG_DATA_HOME/bash-completion/completions"
WITH_COMPLETION=1
UNINSTALL=0
TMP=""

info() { printf '%s\n' "$*"; }
warn() { printf 'install.sh: warning: %s\n' "$*" >&2; }
die() { printf 'install.sh: error: %s\n' "$*" >&2; exit 1; }

cleanup() { [[ -n "$TMP" && -d "$TMP" ]] && rm -rf -- "${TMP:?}"; return 0; }
trap cleanup EXIT

usage() {
  sed -n '5,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

while (( $# )); do
  case "$1" in
    --uninstall) UNINSTALL=1; shift ;;
    --prefix) [[ $# -ge 2 ]] || die "--prefix requires a directory"; PREFIX="$2"; shift 2 ;;
    --prefix=*) PREFIX="${1#*=}"; shift ;;
    --no-completion) WITH_COMPLETION=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done
LINK="$PREFIX/$TOOL"

# Picks curl or wget (FDWAM_DOWNLOADER forces one).
downloader() {
  case "${FDWAM_DOWNLOADER:-}" in
    curl|wget)
      command -v "$FDWAM_DOWNLOADER" >/dev/null 2>&1 || die "FDWAM_DOWNLOADER=$FDWAM_DOWNLOADER is not installed"
      printf '%s' "$FDWAM_DOWNLOADER"; return ;;
  esac
  if command -v curl >/dev/null 2>&1; then printf 'curl'
  elif command -v wget >/dev/null 2>&1; then printf 'wget'
  else die "neither curl nor wget is available"; fi
}

# download <url> <outfile>; returns 1 on failure.
download() {
  case "$(downloader)" in
    curl) curl -fsSL --retry 2 -o "$2" -- "$1" ;;
    wget) wget -q -O "$2" -- "$1" ;;
  esac
}

do_uninstall() {
  local removed=0
  if [[ -L "$LINK" && "$(readlink -- "$LINK")" == "$TARGET" ]]; then
    rm -f -- "${LINK:?}"; info "removed $LINK"; removed=1
  elif [[ -e "$LINK" ]]; then
    warn "$LINK is not the $TOOL symlink, leaving it alone"
  fi
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf -- "${INSTALL_DIR:?}"; info "removed $INSTALL_DIR"; removed=1
  fi
  if [[ -f "$COMPLETION_DIR/$TOOL" ]]; then
    rm -f -- "${COMPLETION_DIR:?}/${TOOL:?}"; info "removed $COMPLETION_DIR/$TOOL"; removed=1
  fi
  (( removed )) || info "nothing to remove"
  cat <<MSG

Kept (your data):
  registry, icons, profiles:  $DATA_DIR/{apps,icons,profiles}
  launchers:                  $XDG_DATA_HOME/applications/$TOOL-*.desktop
  snap/flatpak profiles:      ~/snap/<snap>/common/$TOOL-profiles, ~/.var/app/<id>/data/$TOOL-profiles
To remove an app including its profile run '$TOOL delete <id>' BEFORE uninstalling,
or delete the directories above by hand.
MSG
}

do_install() {
  local url_bin url_sums url_comp expected
  TMP="$(mktemp -d "${TMPDIR:-/tmp}/$TOOL-install.XXXXXX")"
  case "$VERSION" in
    main)
      warn "installing the development version from branch main (no checksum verification)"
      url_bin="$BASE_URL/raw/main/bin/$TOOL"
      url_comp="$BASE_URL/raw/main/completions/$TOOL.bash"
      url_sums=""
      ;;
    latest)
      url_bin="$BASE_URL/releases/latest/download/$TOOL"
      url_sums="$BASE_URL/releases/latest/download/SHA256SUMS"
      url_comp="$BASE_URL/releases/latest/download/$TOOL.bash"
      ;;
    *)
      url_bin="$BASE_URL/releases/download/$VERSION/$TOOL"
      url_sums="$BASE_URL/releases/download/$VERSION/SHA256SUMS"
      url_comp="$BASE_URL/releases/download/$VERSION/$TOOL.bash"
      ;;
  esac

  info "downloading $TOOL ($VERSION) with $(downloader)…"
  download "$url_bin" "$TMP/$TOOL" || die "download failed: $url_bin"
  if (( WITH_COMPLETION )); then
    download "$url_comp" "$TMP/$TOOL.bash" || { warn "completion not available at $url_comp"; WITH_COMPLETION=0; }
  fi
  if [[ -n "$url_sums" ]]; then
    download "$url_sums" "$TMP/SHA256SUMS" || die "download failed: $url_sums"
    expected="$(grep -E "[[:space:]]\*?$TOOL\$" "$TMP/SHA256SUMS" || true)"
    [[ -n "$expected" ]] || die "SHA256SUMS does not list $TOOL"
    if ! (cd "$TMP" && printf '%s\n' "$expected" | sha256sum -c --quiet - >/dev/null 2>&1); then
      die "checksum verification of $TOOL FAILED, nothing was installed"
    fi
    if (( WITH_COMPLETION )); then
      expected="$(grep -E "[[:space:]]\*?$TOOL\.bash\$" "$TMP/SHA256SUMS" || true)"
      if [[ -n "$expected" ]] && ! (cd "$TMP" && printf '%s\n' "$expected" | sha256sum -c --quiet - >/dev/null 2>&1); then
        die "checksum verification of $TOOL.bash FAILED, nothing was installed"
      fi
    fi
    info "checksum OK"
  fi
  head -c 2 "$TMP/$TOOL" | grep -q '#!' || die "downloaded file does not look like a script, nothing was installed"

  # Refuse to clobber a foreign file at the symlink location before touching anything.
  if [[ -e "$LINK" || -L "$LINK" ]]; then
    if [[ ! -L "$LINK" || "$(readlink -- "$LINK")" != "$TARGET" ]]; then
      die "$LINK already exists and is not a $TOOL symlink; remove it or use --prefix DIR"
    fi
  fi

  mkdir -p -- "$INSTALL_DIR" "$PREFIX"
  chmod 0755 "$TMP/$TOOL"
  mv -f -- "$TMP/$TOOL" "$INSTALL_DIR/.$TOOL.new"
  mv -f -- "$INSTALL_DIR/.$TOOL.new" "$TARGET"
  ln -sfn -- "$TARGET" "$LINK"
  info "installed $TARGET"
  info "symlink   $LINK"

  if (( WITH_COMPLETION )); then
    mkdir -p -- "$COMPLETION_DIR"
    mv -f -- "$TMP/$TOOL.bash" "$COMPLETION_DIR/$TOOL"
    chmod 0644 "$COMPLETION_DIR/$TOOL"
    info "completion $COMPLETION_DIR/$TOOL"
  fi

  case ":$PATH:" in
    *":$PREFIX:"*) ;;
    *)
      cat <<MSG

NOTE: $PREFIX is not in your PATH.
  On Ubuntu/KDE Neon ~/.profile adds ~/.local/bin automatically after you log in again.
  Otherwise add this line to ~/.bashrc:
    export PATH="$PREFIX:\$PATH"
MSG
      ;;
  esac

  info ""
  info "$("$TARGET" version)"
  info "Run '$TOOL doctor' to check your setup, then '$TOOL create <url>'."
}

if (( UNINSTALL )); then do_uninstall; else do_install; fi
