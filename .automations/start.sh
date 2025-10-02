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

log "Detected reverse proxy: $PROXY_SERVICE"

# Ensure proxy network exists
if ! docker network inspect proxy >/dev/null 2>&1; then
    docker network create proxy
    log "Created proxy network"
fi

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
    service_path="./services/$service"
    if [ -d "$service_path" ]; then
        log "Starting $service..."
        docker compose -f "$service_path/docker-compose.yml" up -d
    else
        log "Warning: $service folder not found, skipping"
    fi
done

log "All services started."
log "You can stop them again with .automations/stop.sh"
log "==============================="
