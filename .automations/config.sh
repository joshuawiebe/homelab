#!/usr/bin/env bash
# Interactive HomeLab configuration script with Traefik
set -euo pipefail

# Source shared logging module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/../.shared/log.sh" 2>/dev/null || {
  echo "[ERROR] Failed to load logging module"
  exit 1
}

# Helper functions
check_docker() {
  if ! docker info >/dev/null 2>&1; then
    error "Docker not running or not accessible"
    exit 1
  fi
}

ensure_env_from_template() {
  local svc="${1:-}"
  local tpl="services/$svc/.env.template"
  local envf="services/$svc/.env"
  if [ ! -f "$tpl" ]; then
    error "Missing template: $tpl"
    return 1
  fi
  if [ ! -f "$envf" ]; then
    mkdir -p "$(dirname "$envf")"
    cp "$tpl" "$envf"
    success "Created: $envf (from template)"
  else
    info "Using existing: $envf"
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
    read -s -rp "  $prompt: " p1; echo
    read -s -rp "  Confirm: " p2; echo
    if [ -z "$p1" ]; then
      warn "Empty password not allowed"
      continue
    fi
    if [ "$p1" != "$p2" ]; then
      warn "Passwords do not match, try again"
      continue
    fi
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

# Main setup
section "HomeLab Configuration"

# --- Docker check ---
subsection "Prerequisites"
info "Checking Docker installation..."
check_docker
success "Docker is running and accessible"
echo ""

# --- Network setup ---
subsection "Docker Network"
if docker network inspect proxy >/dev/null 2>&1; then
  success "Docker network 'proxy' exists"
else
  info "Creating proxy network..."
  docker network create proxy
  success "Created Docker network 'proxy'"
fi
echo ""

# --- General password option ---
subsection "Password Strategy"
info "Would you like to use one password for all services?"
echo ""
USE_GENERAL=""
if confirm "Use single password for all services"; then
  USE_GENERAL="Y"
  echo ""
  info "Please enter the general password"
  prompt_password "General password" GENERAL_PASS
  success "General password set"
else
  USE_GENERAL="N"
fi
echo ""

# --- Traefik setup ---
subsection "Traefik Configuration"
TRA_ENV="services/traefik/.env"
ensure_env_from_template "traefik"
echo ""

info "Enter Traefik configuration details:"
read -rp "  ACME email (for SSL): " ACME_EMAIL
read -rp "  IPv64.net API token: " IPV64_TOKEN
read -rp "  Dashboard username: " DASH_USER
prompt_password "Dashboard password" DASH_PASS
read -rp "  Base domain (e.g., joshua.home64.de): " BASE_DOMAIN
read -rp "  Traefik subdomain (e.g., 'traefik'): " TRAEFIK_SUBDOMAIN

set_env_value "$TRA_ENV" "EMAIL" "$ACME_EMAIL"
set_env_value "$TRA_ENV" "IPV64_TOKEN" "$IPV64_TOKEN"
set_env_value "$TRA_ENV" "DASHBOARD_USER" "$DASH_USER"
set_env_value "$TRA_ENV" "DASHBOARD_PASSWORD" "$DASH_PASS"
set_env_value "$TRA_ENV" "BASE_DOMAIN" "$BASE_DOMAIN"
set_env_value "$TRA_ENV" "TRAEFIK_SUBDOMAIN" "$TRAEFIK_SUBDOMAIN"

success "Traefik configuration complete"
echo ""

# --- Services configuration ---
subsection "Service Configuration"

SERVICES=(nextcloud vaultwarden gotify uptime_kuma adguard_home)
CONFIGURED=0

for svc in "${SERVICES[@]}"; do
  echo ""
  info "Configuring: $svc"
  separator
  
  SERVICE_ENV="services/$svc/.env"
  ensure_env_from_template "$svc"
  
  read -rp "  Subdomain for $svc (e.g., 'vault'): " SUBDOMAIN
  FULL_DOMAIN="${SUBDOMAIN}.${BASE_DOMAIN}"
  set_env_value "$SERVICE_ENV" "DOMAIN" "$FULL_DOMAIN"
  success "Domain: $FULL_DOMAIN"
  
  if [[ "$USE_GENERAL" =~ ^[Yy]$ ]]; then
    case "$svc" in
      nextcloud)
        set_env_value "$SERVICE_ENV" "MYSQL_ROOT_PASSWORD" "$GENERAL_PASS"
        set_env_value "$SERVICE_ENV" "MYSQL_PASSWORD" "$GENERAL_PASS"
        set_env_value "$SERVICE_ENV" "HSTS_ENABLED" "true"
        success "MySQL passwords configured"
        ;;
      vaultwarden)
        info "Generate Vaultwarden admin token:"
        info "  docker run --rm -it vaultwarden/server /vaultwarden hash"
        read -rp "  Paste Argon2id hash: " VW_HASH_RAW
        VW_HASH="$(trim "$VW_HASH_RAW")"
        set_env_value "$SERVICE_ENV" "ADMIN_TOKEN" "$VW_HASH"
        success "Admin token configured"
        ;;
    esac
  else
    case "$svc" in
      nextcloud)
        info "Enter Nextcloud database passwords:"
        prompt_password "MYSQL_ROOT_PASSWORD" NC_ROOT
        prompt_password "MYSQL_PASSWORD (app user)" NC_USER
        set_env_value "$SERVICE_ENV" "MYSQL_ROOT_PASSWORD" "$NC_ROOT"
        set_env_value "$SERVICE_ENV" "MYSQL_PASSWORD" "$NC_USER"
        set_env_value "$SERVICE_ENV" "HSTS_ENABLED" "true"
        success "Nextcloud passwords configured"
        ;;
      vaultwarden)
        info "Generate Vaultwarden admin token:"
        info "  docker run --rm -it vaultwarden/server /vaultwarden hash"
        read -rp "  Paste Argon2id hash: " VW_HASH_RAW
        VW_HASH="$(trim "$VW_HASH_RAW")"
        set_env_value "$SERVICE_ENV" "ADMIN_TOKEN" "$VW_HASH"
        success "Admin token configured"
        ;;
    esac
  fi
  
  ((CONFIGURED++))
done

echo ""
separator
success "Configured $CONFIGURED/${#SERVICES[@]} services"
echo ""

# --- Summary and next steps ---
subsection "Configuration Summary"

info "Configuration files created:"
info "  Traefik: services/traefik/.env"
for svc in "${SERVICES[@]}"; do
  info "  $svc: services/$svc/.env"
done
echo ""

info "Base domain: $BASE_DOMAIN"
info "Dashboard: https://${TRAEFIK_SUBDOMAIN}.${BASE_DOMAIN}"
echo ""

# --- Optional: Start services ---
echo ""
subsection "Next Steps"

if confirm "Start services now"; then
  if [ -f "$SCRIPT_DIR/start.sh" ]; then
    success "Starting services..."
    bash "$SCRIPT_DIR/start.sh"
  else
    error "start.sh not found in $SCRIPT_DIR"
  fi
else
  info "Run this command later to start services:"
  info "  bash $SCRIPT_DIR/start.sh"
fi

echo ""
exit_success "Configuration complete! Your HomeLab is ready."
