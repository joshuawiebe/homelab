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

# Logging
exec >> "$LOG_FILE" 2>&1
echo "===== Backup started at $(date) ====="

# --- Stop HomeLab services ---
echo "[INFO] Stopping HomeLab services..."
"$SCRIPT_DIR/../.automations/stop.sh"

# --- Mount USB ---
if ! mountpoint -q "$BACKUP_MOUNT"; then
    echo "[INFO] Mounting USB drive..."
    sudo mount "$USB_DEVICE" "$BACKUP_MOUNT"
else
    echo "[INFO] USB drive already mounted"
fi

# --- Prune old backups (pre) ---
echo "[INFO] Pruning old backups (pre)..."
borg prune -v --list "$BORG_REPO" --keep-last 3 || true

# --- Create backup ---
echo "[INFO] Creating new backup..."
borg create \
    --stats \
    --compression zstd,3 \
    "$BORG_REPO::backup-$(date +%F-%H%M%S)" \
    "$BACKUP_SRC"

# --- Prune old backups (post) ---
echo "[INFO] Pruning old backups (post)..."
borg prune -v --list "$BORG_REPO" --keep-last 3 || true

# --- Unmount USB ---
echo "[INFO] Unmounting USB drive..."
sudo umount "$BACKUP_MOUNT" || echo "[WARN] Failed to unmount USB"

# --- Restart HomeLab services ---
echo "[INFO] Starting HomeLab services..."
"$SCRIPT_DIR/../.automations/start.sh"

echo "===== Backup finished at $(date) ====="
