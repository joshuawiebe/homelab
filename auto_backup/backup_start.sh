#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Load config
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    echo "[ERROR] Missing .env file in $SCRIPT_DIR"
    exit 1
fi

# Use log file
exec >> "$LOG_FILE" 2>&1

echo "===== Backup started at $(date) ====="

# --- 0. Stop HomeLab Docker services ---
echo "[INFO] Stopping HomeLab services..."
SERVICES=("uptime_kuma" "gotify" "adguard_home" "vaultwarden" "nextcloud" "$PROXY_SERVICE")

for svc in "${SERVICES[@]}"; do
    SERVICE_FILE="../services/$svc/docker-compose.yml"
    if [ -f "$SERVICE_FILE" ]; then
        echo "[INFO] Stopping $svc..."
        docker compose -f "$SERVICE_FILE" down || echo "[WARN] Failed to stop $svc"
    else
        echo "[INFO] Skipping $svc: docker-compose.yml not found"
    fi
done

# --- 1. Mount USB ---
echo "[INFO] Mounting USB drive..."
sudo mount "$USB_DEVICE" "$BACKUP_MOUNT"

# --- 2. Prune old backups (pre) ---
echo "[INFO] Pruning old backups (pre)..."
borg prune -v --list "$BORG_REPO" --keep-last 3 || true

# --- 3. Create backup ---
echo "[INFO] Creating new backup..."
borg create \
    --stats \
    --compression zstd,3 \
    "$BORG_REPO::backup-$(date +%F-%H%M%S)" \
    "$BACKUP_SRC"

# --- 4. Prune old backups (post) ---
echo "[INFO] Pruning old backups (post)..."
borg prune -v --list "$BORG_REPO" --keep-last 3 || true

# --- 5. Unmount USB ---
echo "[INFO] Unmounting USB drive..."
sudo umount "$BACKUP_MOUNT"

# --- 6. Restart HomeLab Docker services ---
echo "[INFO] Starting HomeLab services..."
"$SCRIPT_DIR/../.automations/start.sh"

echo "===== Backup finished at $(date) ====="
