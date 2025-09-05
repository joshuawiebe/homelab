#!/bin/bash

set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

log "Stopping all services..."

# Stop services in reverse order (apps first, then databases)
services_order=(
    "watchtower"
    "uptime_kuma"
    "gotify"
    "adguard_home"
    "nextcloud"
    "vaultwarden"
    "mongodb"
    "zoraxy"  # Stop reverse proxy last
)

for service in "${services_order[@]}"; do
    if [ -d "./services/$service" ]; then
        log "Stopping $service..."
        (cd "./services/$service" && docker compose down)
    fi
done

read -p "Do you want to remove the proxy network? [y/N]: " remove_network
if [[ "$remove_network" =~ ^[Yy]$ ]]; then
    if docker network rm proxy; then
        log "Removed proxy network"
    else
        log "Warning: Could not remove proxy network. It might still be in use."
    fi
fi

log "All services stopped."
log "You can start the services again by running './start.sh'."