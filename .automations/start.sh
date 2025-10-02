#!/bin/bash
set -e

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

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

log "Starting HomeLab services..."

# Ensure proxy network exists
if ! docker network inspect proxy >/dev/null 2>&1; then
    docker network create proxy
    log "Created proxy network"
fi

# Ask which reverse proxy to use
echo "Choose reverse proxy:"
echo "1) Traefik"
echo "2) Zoraxy"
read -rp "Enter choice [1-2]: " choice

case "$choice" in
  1) PROXY_SERVICE="traefik" ;;
  2) PROXY_SERVICE="zoraxy" ;;
  *) log "Invalid choice"; exit 1 ;;
esac

# Define services in order
services_order=(
    "$PROXY_SERVICE"
    "vaultwarden"
    "nextcloud"
    "adguard_home"
    "gotify"
    "uptime_kuma"
    "watchtower"
)

# Start services
for service in "${services_order[@]}"; do
    service_path="./services/$service"
    if [ -d "$service_path" ]; then
        log "Starting $service..."
        docker compose -f "$service_path/docker-compose.yml" up -d
        wait_for_service "$service" || log "Warning: $service might not be fully ready"
    else
        log "Warning: Service directory $service_path not found"
    fi
done

log "All services started with $PROXY_SERVICE as reverse proxy."
log "You can stop them with '.automations/stop.sh'."
