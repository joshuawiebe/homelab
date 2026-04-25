#!/usr/bin/env bash
set -euo pipefail

# Source shared logging module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/../.shared/log.sh" 2>/dev/null || {
  echo "[ERROR] Failed to load logging module"
  exit 1
}

# Statistics
SERVICES_STOPPED=0
SERVICES_FAILED=0

section "HomeLab Services Shutdown"

# --- Detect running reverse proxy automatically ---
subsection "Detecting Proxy Service"

PROXY_SERVICE=""
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^traefik$"; then
    PROXY_SERVICE="traefik"
    success "Detected: traefik"
elif docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^zoraxy$"; then
    PROXY_SERVICE="zoraxy"
    success "Detected: zoraxy"
else
    warn "No reverse proxy container detected (traefik or zoraxy)"
fi
echo ""

# --- Build service list ---
subsection "Preparing Service List"

SERVICES=(
    "adguard_home"
    "gotify"
    "nextcloud"
    "uptime_kuma"
    "vaultwarden"
    "watchtower"
)

# Add proxy if detected
if [ -n "$PROXY_SERVICE" ]; then
    SERVICES+=("$PROXY_SERVICE")
    info "Will stop $PROXY_SERVICE proxy"
fi

info "Total services to stop: ${#SERVICES[@]}"
echo ""

# --- Stop services ---
subsection "Stopping Services"

for svc in "${SERVICES[@]}"; do
    service_path="$SCRIPT_DIR/../services/$svc"
    if [ -f "$service_path/docker-compose.yml" ]; then
        progress_item "$svc" "stopping"
        if docker compose -f "$service_path/docker-compose.yml" down 2>&1; then
            progress_item "$svc" "✓ stopped"
            ((SERVICES_STOPPED++))
        else
            warn "$svc failed to stop"
            ((SERVICES_FAILED++))
        fi
    else
        warn "$svc: docker-compose.yml not found, skipping"
    fi
done

echo ""
separator

# --- Summary ---
echo ""
success "Services shutdown complete"
info "$SERVICES_STOPPED service(s) stopped"
if [ $SERVICES_FAILED -gt 0 ]; then
    warn "$SERVICES_FAILED service(s) had issues"
fi
echo ""
info "Start services again with: .automations/start.sh"
echo ""
