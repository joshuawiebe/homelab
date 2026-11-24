# bash completion for the homelab CLI
_homelab_services() {
  local root="${HOMELAB_ROOT:-}"
  if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
  fi
  ls -1 "$root/services" 2>/dev/null
}

_homelab() {
  local cur prev words cword
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"
  local commands="up down restart status urls logs config doctor snapshot install uninstall"

  case "$prev" in
    homelab)
      COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
      return 0
      ;;
    logs)
      COMPREPLY=( $(compgen -W "$(_homelab_services)" -- "$cur") )
      return 0
      ;;
    snapshot)
      COMPREPLY=( $(compgen -W "run list verify extract stats install uninstall" -- "$cur") )
      return 0
      ;;
    --proxy)
      COMPREPLY=( $(compgen -W "$(_homelab_services)" -- "$cur") )
      return 0
      ;;
  esac

  case "${COMP_WORDS[1]}" in
    up|down|restart)
      COMPREPLY=( $(compgen -W "$(_homelab_services) --proxy --wait --no-wait --dry-run" -- "$cur") )
      ;;
    *)
      COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
      ;;
  esac
  return 0
}

complete -F _homelab homelab
