#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Detect running reverse proxy automatically
if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
    PROXY_SERVICE="traefik"
elif docker ps --format '{{.Names}}' | grep -q "^zoraxy$"; then
    PROXY_SERVICE="zoraxy"
else
    log "No reverse proxy container detected (traefik or zoraxy). Exiting."
    exit 1
fi

log "Stopping HomeLab services with proxy: $PROXY_SERVICE"

SERVICES=(
    "adguard_home"
    "gotify"
    "nextcloud"
    "uptime_kuma"
    "vaultwarden"
    "watchtower"
    "$PROXY_SERVICE"
)

for svc in "${SERVICES[@]}"; do
    SERVICE_FILE="./services/$svc/docker-compose.yml"
    if [ -f "$SERVICE_FILE" ]; then
        log "Stopping $svc..."
        docker compose -f "$SERVICE_FILE" down || log "Warning: failed to stop $svc"
    else
        log "Skipping $svc: docker-compose.yml not found"
    fi
done

log "HomeLab services stopped."
log "You can start them again with .automations/start.sh"
log "==============================="
