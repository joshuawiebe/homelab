#!/bin/bash

set -e

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to wait for service startup
wait_for_service() {
    local service=$1
    local max_attempts=30
    local attempt=1

    while [ $attempt -le $max_attempts ]; do
        if docker ps --filter "name=$service" --format "{{.Status}}" | grep -q "Up"; then
            log "$service is running"
            return 0
        fi
        log "Waiting for $service to start (attempt $attempt/$max_attempts)..."
        sleep 2
        ((attempt++))
    done
    
    log "Timed out waiting for $service to start"
    return 1
}

log "Starting all services..."

# Create proxy network if it doesn't exist
if ! docker network inspect proxy >/dev/null 2>&1; then
    docker network create proxy
    log "Created proxy network"
fi

# Define service order (MongoDB removed)
services_order=(
    "zoraxy"       # Start reverse proxy first
    "vaultwarden"
    "nextcloud"
    "adguard_home"
    "gotify"
    "uptime_kuma"
    "watchtower"   # Start watchtower last
)

# Start services in order
for service in "${services_order[@]}"; do
    service_path="./services/$service"
    if [ -d "$service_path" ]; then
        log "Starting $service..."
        docker compose -f "$service_path/docker-compose.yml" up -d
        
        # Special handling for Zoraxy as it's our gateway
        if [ "$service" = "zoraxy" ]; then
            wait_for_service zoraxy || { log "Failed to start Zoraxy"; exit 1; }
        else
            wait_for_service "$service" || log "Warning: $service might not be fully ready"
        fi
    else
        log "Warning: Service directory $service_path not found"
    fi
done

log "All services started. Please check individual service logs for any issues."
log "You can stop the services by running './stop.sh'."