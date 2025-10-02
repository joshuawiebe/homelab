#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# --- Script directory ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect running reverse proxy automatically
PROXY_SERVICE=""
if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
    PROXY_SERVICE="traefik"
elif docker ps --format '{{.Names}}' | grep -q "^zoraxy$"; then
    PROXY_SERVICE="zoraxy"
else
    log "No reverse proxy container detected (traefik or zoraxy). Continuing without proxy."
fi

log "Stopping HomeLab services..."

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
fi

for svc in "${SERVICES[@]}"; do
    service_path="$SCRIPT_DIR/../services/$svc"
    if [ -f "$service_path/docker-compose.yml" ]; then
        log "Stopping $svc..."
        docker compose -f "$service_path/docker-compose.yml" down || log "Warning: failed to stop $svc"
    else
        log "Skipping $svc: docker-compose.yml not found"
    fi
done

log "HomeLab services stopped."
log "You can start them again with .automations/start.sh"
log "==============================="
