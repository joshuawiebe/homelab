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
