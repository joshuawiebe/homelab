#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/.env"

echo "[INFO] Starting backup job..."

# 1. Mount USB
echo "[INFO] Mounting USB drive..."
sudo mount "$USB_DEVICE" "$USB_MOUNTPOINT"

# 2. Prune before backup
echo "[INFO] Pruning old backups (pre)..."
sudo borg prune -v --list "$USB_MOUNTPOINT" --keep-last 3

# 3. Create backup
echo "[INFO] Creating new backup..."
sudo borg create \
    "$USB_MOUNTPOINT::ssd-$(date +%F-%H%M%S)" \
    "$SOURCE_PATH"

# 4. Prune after backup
echo "[INFO] Pruning old backups (post)..."
sudo borg prune -v --list "$USB_MOUNTPOINT" --keep-last 3

# 5. Unmount
echo "[INFO] Unmounting USB drive..."
sudo umount "$USB_MOUNTPOINT"

echo "[INFO] Backup finished successfully!"




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

# 1. Mount USB
echo "[INFO] Mounting USB drive..."
sudo mount "$USB_DEVICE" "$BACKUP_MOUNT"

# 2. Prune old backups (pre)
echo "[INFO] Pruning old backups (pre)..."
borg prune -v --list "$BORG_REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6 || true

# 3. Create backup
echo "[INFO] Creating new backup..."
borg create \
    --stats \
    --compression lz4 \
    "$BORG_REPO::${BACKUP_NAME}-$(date +%F-%H%M%S)" \
    "$BACKUP_SRC"

# 4. Prune old backups (post)
echo "[INFO] Pruning old backups (post)..."
borg prune -v --list "$BORG_REPO" --keep-daily=7 --keep-weekly=4 --keep-monthly=6 || true

# 5. Unmount USB
echo "[INFO] Unmounting USB drive..."
sudo umount "$BACKUP_MOUNT"

echo "===== Backup finished at $(date) ====="
