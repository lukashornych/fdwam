# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Lukáš Hornych
#
# Bash completion for fdwam. Install to
# ${XDG_DATA_HOME:-~/.local/share}/bash-completion/completions/fdwam
# or source it from ~/.bashrc.

_fdwam_ids() {
  local dir="${XDG_DATA_HOME:-$HOME/.local/share}/fdwam/apps" f
  for f in "$dir"/*.conf; do
    [[ -f "$f" ]] || continue
    f="${f##*/}"
    printf '%s\n' "${f%.conf}"
  done
}

_fdwam() {
  local cur prev cmd
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  local commands="create list show modify delete launch regenerate browsers doctor help version"
  local browsers="brave chrome chromium firefox vivaldi edge librewolf floorp waterfox zen epiphany falkon"
  local categories="AudioVideo Development Education Game Graphics Network Office Science Settings System Utility"

  if (( COMP_CWORD == 1 )); then
    mapfile -t COMPREPLY < <(compgen -W "$commands --help --version --verbose" -- "$cur")
    return 0
  fi
  cmd="${COMP_WORDS[1]}"

  case "$prev" in
    --browser)  mapfile -t COMPREPLY < <(compgen -W "$browsers" -- "$cur"); return 0 ;;
    --category) mapfile -t COMPREPLY < <(compgen -W "$categories" -- "$cur"); return 0 ;;
    --icon)     mapfile -t COMPREPLY < <(compgen -f -- "$cur"); return 0 ;;
    --name|--id|--flags|--url) return 0 ;;
  esac

  case "$cmd" in
    create)
      if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--name --id --icon --no-icon --category --flags --x11 --wayland --interactive --yes --launch" -- "$cur")
      elif (( COMP_CWORD == 3 )); then
        mapfile -t COMPREPLY < <(compgen -W "$browsers" -- "$cur")
      fi
      ;;
    modify)
      if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--name --url --browser --icon --no-icon --refresh-icon --category --flags --x11 --wayland --keep-profile --interactive --yes" -- "$cur")
      else
        mapfile -t COMPREPLY < <(compgen -W "$(_fdwam_ids)" -- "$cur")
      fi
      ;;
    show)
      mapfile -t COMPREPLY < <(compgen -W "$(_fdwam_ids)" -- "$cur")
      ;;
    launch)
      if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--browser-mode" -- "$cur")
      else
        mapfile -t COMPREPLY < <(compgen -W "$(_fdwam_ids)" -- "$cur")
      fi
      ;;
    delete)
      if [[ "$cur" == -* ]]; then
        mapfile -t COMPREPLY < <(compgen -W "--keep-profile --yes" -- "$cur")
      else
        mapfile -t COMPREPLY < <(compgen -W "$(_fdwam_ids)" -- "$cur")
      fi
      ;;
    regenerate)
      mapfile -t COMPREPLY < <(compgen -W "--all $(_fdwam_ids)" -- "$cur")
      ;;
    list)
      mapfile -t COMPREPLY < <(compgen -W "--long" -- "$cur")
      ;;
    help)
      mapfile -t COMPREPLY < <(compgen -W "$commands" -- "$cur")
      ;;
  esac
  return 0
}

complete -F _fdwam fdwam
