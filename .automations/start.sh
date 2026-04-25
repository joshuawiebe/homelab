#!/usr/bin/env bash
set -euo pipefail

# Source shared logging module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/../.shared/log.sh" 2>/dev/null || {
  echo "[ERROR] Failed to load logging module"
  exit 1
}

# Default values
PROXY_SERVICE=""
SERVICES_STARTED=0
SERVICES_FAILED=0

section "HomeLab Services Startup"

# --- CLI args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --proxy)
            PROXY_SERVICE="$2"
            shift 2
            ;;
        *)
            error "Unknown option: $1"
            echo ""
            echo "Usage: $0 [--proxy traefik|zoraxy]"
            echo ""
            exit 1
            ;;
    esac
done

# --- Proxy detection ---
subsection "Detecting Proxy Service"

if [ -n "$PROXY_SERVICE" ]; then
    info "Using proxy from flag: $PROXY_SERVICE"
else
    if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
        PROXY_SERVICE="traefik"
        success "Auto-detected proxy: traefik"
    elif docker ps --format '{{.Names}}' | grep -q "^zoraxy$"; then
        PROXY_SERVICE="zoraxy"
        success "Auto-detected proxy: zoraxy"
    else
        error "No reverse proxy container detected (traefik or zoraxy)"
        exit 1
    fi
fi
echo ""

# --- Create network if missing ---
subsection "Preparing Docker Network"

if docker network inspect proxy >/dev/null 2>&1; then
    success "Docker network 'proxy' exists"
else
    info "Creating proxy network..."
    docker network create proxy
    success "Created Docker network 'proxy'"
fi
echo ""

# --- Start services in order ---
subsection "Starting Services"

services_order=(
    "$PROXY_SERVICE"
    "adguard_home"
    "gotify"
    "nextcloud"
    "uptime_kuma"
    "vaultwarden"
    "watchtower"
)

for service in "${services_order[@]}"; do
    service_path="$SCRIPT_DIR/../services/$service"
    if [ -d "$service_path" ]; then
        progress_item "$service" "starting"
        if docker compose -f "$service_path/docker-compose.yml" up -d 2>&1 | grep -q "done"; then
            progress_item "$service" "✓ started"
            ((SERVICES_STARTED++))
        else
            warn "$service failed to start (may still be starting)"
            ((SERVICES_FAILED++))
        fi
    else
        warn "$service folder not found, skipping"
    fi
done

echo ""
separator

# --- Summary ---
echo ""
success "Services startup initiated"
info "$SERVICES_STARTED service(s) started"
if [ $SERVICES_FAILED -gt 0 ]; then
    warn "$SERVICES_FAILED service(s) may need attention"
fi
echo ""
info "Check status with: docker ps"
info "View logs with: docker compose -f <path>/docker-compose.yml logs -f"
info "Stop services with: .automations/stop.sh"
echo ""
