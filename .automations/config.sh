#!/usr/bin/env bash
# Interactive HomeLab configuration script with Traefik
set -euo pipefail

log() { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }

check_docker() {
  if ! docker info >/dev/null 2>&1; then
    log "Error: Docker not running or accessible"
    exit 1
  fi
}

ensure_env_from_template() {
  local svc="${1:-}"
  local tpl="services/$svc/.env.template"
  local envf="services/$svc/.env"
  if [ ! -f "$tpl" ]; then
    log "Error: missing template $tpl"
    return 1
  fi
  if [ ! -f "$envf" ]; then
    mkdir -p "$(dirname "$envf")"
    cp "$tpl" "$envf"
    log "Created $envf from template"
  fi
}

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

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

log "Starting HomeLab configuration"
check_docker

# Ensure proxy network exists
if docker network inspect proxy >/dev/null 2>&1; then
  log "Docker network 'proxy' exists"
else
  docker network create proxy
  log "Created Docker network 'proxy'"
fi

# General password option
USE_GENERAL=""
read -rp "Use one general password for all services? [y/N]: " USE_GENERAL_INPUT
USE_GENERAL=${USE_GENERAL_INPUT:-N}
if [[ "$USE_GENERAL" =~ ^[Yy]$ ]]; then
  prompt_password "General password for all services (used where needed)" GENERAL_PASS
  log "General password captured"
fi

# Traefik setup
TRA_ENV="services/traefik/.env"
ensure_env_from_template "traefik"

read -rp "Enter ACME email (for SSL certificates): " ACME_EMAIL
read -rp "Enter ipv64.net API token: " IPV64_TOKEN
read -rp "Traefik dashboard username: " DASH_USER
prompt_password "Traefik dashboard password" DASH_PASS
read -rp "Enter base domain (e.g., joshua.home64.de): " BASE_DOMAIN
read -rp "Enter subdomain for Traefik dashboard (e.g., 'traefik'): " TRAEFIK_SUBDOMAIN

set_env_value "$TRA_ENV" "EMAIL" "$ACME_EMAIL"
set_env_value "$TRA_ENV" "IPV64_TOKEN" "$IPV64_TOKEN"
set_env_value "$TRA_ENV" "DASHBOARD_USER" "$DASH_USER"
set_env_value "$TRA_ENV" "DASHBOARD_PASSWORD" "$DASH_PASS"
set_env_value "$TRA_ENV" "BASE_DOMAIN" "$BASE_DOMAIN"
set_env_value "$TRA_ENV" "TRAEFIK_SUBDOMAIN" "$TRAEFIK_SUBDOMAIN"

log "Traefik environment configured"

# Services
SERVICES=(nextcloud vaultwarden gotify uptime_kuma adguard_home)

for svc in "${SERVICES[@]}"; do
  SERVICE_ENV="services/$svc/.env"
  ensure_env_from_template "$svc"

  read -rp "Enter subdomain for $svc (e.g., 'vault' for vault.${BASE_DOMAIN}): " SUBDOMAIN
  FULL_DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"
  set_env_value "$SERVICE_ENV" "DOMAIN" "$FULL_DOMAIN"
  log "$svc DOMAIN set to $FULL_DOMAIN"

  if [[ "$USE_GENERAL" =~ ^[Yy]$ ]]; then
    case "$svc" in
      nextcloud)
        set_env_value "$SERVICE_ENV" "MYSQL_ROOT_PASSWORD" "$GENERAL_PASS"
        set_env_value "$SERVICE_ENV" "MYSQL_PASSWORD" "$GENERAL_PASS"
        set_env_value "$SERVICE_ENV" "HSTS_ENABLED" "true"
        ;;
      vaultwarden)
        echo "Generate Vaultwarden Argon2id hash with:"
        echo "  docker run --rm -it vaultwarden/server /vaultwarden hash"
        read -rp "Paste the full \$argon2id hash: " VW_HASH_RAW
        VW_HASH="$(trim "$VW_HASH_RAW")"
        set_env_value "$SERVICE_ENV" "ADMIN_TOKEN" "$VW_HASH"
        ;;
    esac
  else
    case "$svc" in
      nextcloud)
        prompt_password "Nextcloud MYSQL_ROOT_PASSWORD" NC_ROOT
        prompt_password "Nextcloud MYSQL_PASSWORD" NC_USER
        set_env_value "$SERVICE_ENV" "MYSQL_ROOT_PASSWORD" "$NC_ROOT"
        set_env_value "$SERVICE_ENV" "MYSQL_PASSWORD" "$NC_USER"
        set_env_value "$SERVICE_ENV" "HSTS_ENABLED" "true"
        ;;
      vaultwarden)
        echo "Generate Vaultwarden Argon2id hash with:"
        echo "  docker run --rm -it vaultwarden/server /vaultwarden hash"
        read -rp "Paste the full \$argon2id hash: " VW_HASH_RAW
        VW_HASH="$(trim "$VW_HASH_RAW")"
        set_env_value "$SERVICE_ENV" "ADMIN_TOKEN" "$VW_HASH"
        ;;
    esac
  fi
done

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
