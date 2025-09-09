#!/usr/bin/env bash
# Interactive HomeLab configuration script
set -euo pipefail

log() { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }

check_docker() {
  if ! docker info >/dev/null 2>&1; then
    log "Error: Docker not running or accessible"; exit 1
  fi
}

# Ensure that a service has a .env file (create from template if missing)
ensure_env_from_template() {
  local svc="$1" tpl="services/$svc/.env.template" envf="services/$svc/.env"
  if [ ! -f "$tpl" ]; then
    log "Error: missing template $tpl"; return 1
  fi
  if [ ! -f "$envf" ]; then
    mkdir -p "$(dirname "$envf")"
    cp "$tpl" "$envf"
    log "Created $envf from template"
  fi
  return 0
}

# Update or add a key=value pair in a .env file
set_env_value() {
  local file="$1" key="$2" val="$3"
  touch "$file"
  awk -v K="$key" -v V="$val" -F= '
    BEGIN { OFS=FS; seen=0 }
    $1==K { print K "=" V; seen=1; next }
    { print }
    END { if (!seen) print K "=" V }
  ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# Prompt user securely for a password (with confirmation)
prompt_password() {
  local prompt="$1" __outvar="$2"
  local p1 p2
  while true; do
    read -s -rp "$prompt: " p1; echo
    read -s -rp "Confirm $prompt: " p2; echo
    if [ -z "$p1" ]; then log "Empty password not allowed"; continue; fi
    if [ "$p1" != "$p2" ]; then log "Passwords do not match, try again"; continue; fi
    printf -v "$__outvar" '%s' "$p1"
    return 0
  done
}

# Trim whitespace from a string
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

log "Starting HomeLab configuration"
check_docker

# Ensure docker network "proxy" exists
if docker network inspect proxy >/dev/null 2>&1; then
  log "Docker network 'proxy' exists"
else
  docker network create proxy
  log "Created Docker network 'proxy'"
fi

# Ask user if one general password should be reused
read -rp "Use one general password for all services? [y/N]: " USE_GENERAL
USE_GENERAL=${USE_GENERAL:-N}
if [[ "$USE_GENERAL" =~ ^[Yy]$ ]]; then
  prompt_password "General password for all services (will be used where needed)" GENERAL_PASS
  log "General password captured"
fi

# List of services that require configuration
SERVICES=(nextcloud vaultwarden)

for svc in "${SERVICES[@]}"; do
  if ! ensure_env_from_template "$svc"; then 
    log "Skipping $svc due to missing template"
    continue
  fi
  ENVF="services/$svc/.env"

  if [[ "$USE_GENERAL" =~ ^[Yy]$ ]]; then
    case "$svc" in
      nextcloud)
        set_env_value "$ENVF" "MYSQL_ROOT_PASSWORD" "$GENERAL_PASS"
        set_env_value "$ENVF" "MYSQL_PASSWORD" "$GENERAL_PASS"
        log "Nextcloud DB passwords written to $ENVF"
        ;;
      vaultwarden)
        echo
        log "Vaultwarden admin token must be generated interactively."
        echo
        echo "Run this in another terminal and type the SAME general password when prompted:"
        echo "  docker run --rm -it vaultwarden/server /vaultwarden hash"
        echo
        read -rp "Paste the full \$argon2id... hash here: " VW_HASH_RAW
        VW_HASH="$(trim "$VW_HASH_RAW")"
        if [[ "$VW_HASH" == \"*\" && "$VW_HASH" == *\" ]]; then
          VW_HASH="${VW_HASH:1:-1}"
        elif [[ "$VW_HASH" == \'*\' && "$VW_HASH" == *\' ]]; then
          VW_HASH="${VW_HASH:1:-1}"
        fi
        if [[ "$VW_HASH" != \$argon2id* ]]; then
          log "Error: Hash must start with '\$argon2id'. Aborting."
          exit 1
        fi
        VW_HASH_QUOTED="'$VW_HASH'"
        set_env_value "$ENVF" "ADMIN_TOKEN" "$VW_HASH_QUOTED"
        read -rp "Vaultwarden domain for .env (e.g. vault.example.com) [leave empty to skip]: " VW_DOMAIN
        VW_DOMAIN="$(trim "$VW_DOMAIN")"
        if [ -n "$VW_DOMAIN" ]; then
          set_env_value "$ENVF" "DOMAIN" "$VW_DOMAIN"
          log "Vaultwarden DOMAIN set to $VW_DOMAIN"
        fi
        log "Vaultwarden ADMIN_TOKEN saved to $ENVF (wrapped in single quotes)"
        ;;
    esac
  else
    case "$svc" in
      nextcloud)
        prompt_password "Nextcloud MYSQL_ROOT_PASSWORD (will be stored in $ENVF)" NC_ROOT
        prompt_password "Nextcloud MYSQL_PASSWORD (will be stored in $ENVF)" NC_USER
        set_env_value "$ENVF" "MYSQL_ROOT_PASSWORD" "$NC_ROOT"
        set_env_value "$ENVF" "MYSQL_PASSWORD" "$NC_USER"
        log "Nextcloud DB passwords written to $ENVF"
        ;;
      vaultwarden)
        echo
        echo "To generate the Argon2id hash, open another terminal and run:"
        echo "  docker run --rm -it vaultwarden/server /vaultwarden hash"
        echo "Type the Vaultwarden admin password there, confirm it, then copy the \$argon2id... output."
        echo
        read -rp "Paste the full \$argon2id... hash here: " VW_HASH_RAW
        VW_HASH="$(trim "$VW_HASH_RAW")"
        if [[ "$VW_HASH" == \"*\" && "$VW_HASH" == *\" ]]; then
          VW_HASH="${VW_HASH:1:-1}"
        elif [[ "$VW_HASH" == \'*\' && "$VW_HASH" == *\' ]]; then
          VW_HASH="${VW_HASH:1:-1}"
        fi
        if [[ "$VW_HASH" != \$argon2id* ]]; then
          log "Error: Hash must start with '\$argon2id'. Aborting."
          exit 1
        fi
        VW_HASH_QUOTED="'$VW_HASH'"
        set_env_value "$ENVF" "ADMIN_TOKEN" "$VW_HASH_QUOTED"
        read -rp "Vaultwarden domain for .env (e.g. vault.example.com) [leave empty to skip]: " VW_DOMAIN
        VW_DOMAIN="$(trim "$VW_DOMAIN")"
        if [ -n "$VW_DOMAIN" ]; then
          set_env_value "$ENVF" "DOMAIN" "$VW_DOMAIN"
          log "Vaultwarden DOMAIN set to $VW_DOMAIN"
        fi
        log "Vaultwarden ADMIN_TOKEN saved to $ENVF (wrapped in single quotes)"
        ;;
    esac
  fi
done

# Optionally start all services after configuration
read -rp "Start services now using ./.automations/start.sh? [y/N]: " START_NOW
START_NOW=${START_NOW:-N}
if [[ "$START_NOW" =~ ^[Yy]$ ]]; then
  if [ -f ./.automations/start.sh ]; then
    log "Starting services..."
    bash ./.automations/start.sh
  else
    log "start.sh not found in ./.automations"
  fi
fi

log "Configuration finished."