#!/usr/bin/env bash
set -euo pipefail

log() { printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }

log "Stopping HomeLab services..."

# Ask which reverse proxy to stop
echo "Choose reverse proxy to stop:"
echo "1) Traefik"
echo "2) Zoraxy"
read -rp "Enter choice [1-2]: " choice

case "$choice" in
  1) PROXY_SERVICE="traefik" ;;
  2) PROXY_SERVICE="zoraxy" ;;
  *) log "Invalid choice"; exit 1 ;;
esac

# Reverse order: monitoring first, proxy last
SERVICES=(
  "uptime_kuma"
  "gotify"
  "adguard_home"
  "vaultwarden"
  "nextcloud"
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

# Optionally remind about the proxy network
if docker network inspect proxy >/dev/null 2>&1; then
  log "Docker network 'proxy' still exists. You can remove it manually if desired:"
  echo "  docker network rm proxy"
fi

log "All selected services stopped."
log "You can start them again with .automations/start.sh"