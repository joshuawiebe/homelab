#!/bin/bash
# auto_backup/backup_stop.sh
set -e

echo "Stopping auto backup..."
sudo systemctl disable --now auto_backup.timer
sudo systemctl stop auto_backup.service || true
echo "✅ Backup automation stopped."
echo "You can start it again with: sudo systemctl enable --now auto_backup.timer"