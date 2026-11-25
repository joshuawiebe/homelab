# bash completion for the homelab CLI
_homelab_root() {
  if [ -n "${HOMELAB_ROOT:-}" ]; then
    echo "$HOMELAB_ROOT"
  else
    git rev-parse --show-toplevel 2>/dev/null || echo .
  fi
}

_homelab_services() {
  local root
  root=$(_homelab_root)
  ls -1 "$root/services" 2>/dev/null
  ls -1 "$root/hosts/pi/services" 2>/dev/null
}

_homelab_values() {
  local file="${HOMELAB_CONF:-}"
  if [ -z "$file" ]; then
    file="$(_homelab_root)/homelab.toml"
  fi
  sed -n "$1" "$file" 2>/dev/null
}

_homelab() {
  local cur prev
  cur=${COMP_WORDS[COMP_CWORD]}
  prev=${COMP_WORDS[COMP_CWORD-1]}
  local commands="up down restart status urls logs config doctor snapshot migrate provision install uninstall"

  case "$prev" in
    homelab) COMPREPLY=($(compgen -W "$commands --root --host --conf --verbose" -- "$cur")); return 0 ;;
    logs) COMPREPLY=($(compgen -W "$(_homelab_services)" -- "$cur")); return 0 ;;
    snapshot) COMPREPLY=($(compgen -W "run list verify extract stats copy install uninstall" -- "$cur")); return 0 ;;
    provision) COMPREPLY=($(compgen -W "pi" -- "$cur")); return 0 ;;
    migrate) COMPREPLY=($(compgen -W "data" -- "$cur")); return 0 ;;
    --host) COMPREPLY=($(compgen -W "$(_homelab_values 's/^\[hosts\.\([A-Za-z0-9_-]*\)\]$/\1/p')" -- "$cur")); return 0 ;;
    --only) COMPREPLY=($(compgen -W "$(_homelab_values 's/^name *= *"\([^"]*\)"$/\1/p')" -- "$cur")); return 0 ;;
    --proxy) COMPREPLY=($(compgen -W "$(_homelab_services)" -- "$cur")); return 0 ;;
    --conf) COMPREPLY=($(compgen -f -- "$cur")); return 0 ;;
  esac

  case "${COMP_WORDS[1]}" in
    up) COMPREPLY=($(compgen -W "$(_homelab_services) --proxy --profile --wait --no-wait --dry-run" -- "$cur")) ;;
    down|restart) COMPREPLY=($(compgen -W "$(_homelab_services) --dry-run" -- "$cur")) ;;
    snapshot) COMPREPLY=($(compgen -W "run list verify extract stats copy install uninstall --only --remote --dry-run --full --no-check" -- "$cur")) ;;
    provision) COMPREPLY=($(compgen -W "pi --apply --yes --dry-run" -- "$cur")) ;;
    migrate) COMPREPLY=($(compgen -W "data --to --apply --dry-run" -- "$cur")) ;;
    *) COMPREPLY=($(compgen -W "$commands" -- "$cur")) ;;
  esac
  return 0
}

complete -F _homelab homelab
