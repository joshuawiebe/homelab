#!/usr/bin/env bash
set -euo pipefail

log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"; }

# Default values
PROXY_SERVICE=""

# --- CLI args ---
while [[ $# -gt 0 ]]; do
    case "$1" in
        --proxy)
            PROXY_SERVICE="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--proxy traefik|zoraxy]"
            exit 1
            ;;
    esac
done

# --- Proxy detection ---
if [ -n "$PROXY_SERVICE" ]; then
    log "Using proxy from flag: $PROXY_SERVICE"
else
    if docker ps --format '{{.Names}}' | grep -q "^traefik$"; then
        PROXY_SERVICE="traefik"
    elif docker ps --format '{{.Names}}' | grep -q "^zoraxy$"; then
        PROXY_SERVICE="zoraxy"
    else
        log "No reverse proxy container detected (traefik or zoraxy). Exiting."
        exit 1
    fi
    log "Auto-detected proxy: $PROXY_SERVICE"
fi

# --- Create network if missing ---
if ! docker network inspect proxy >/dev/null 2>&1; then
    docker network create proxy
    log "Created proxy network"
fi

# --- Start services in order ---
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
