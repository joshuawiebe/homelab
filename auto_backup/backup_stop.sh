#!/bin/bash
# auto_backup/backup_stop.sh
set -e

cd "$(dirname "$0")"

echo "Stopping auto backup..."
sudo systemctl disable --now auto_backup.timer
sudo systemctl stop auto_backup.service || true

if [ "$1" == "--remove" ]; then
    echo "Removing systemd service and timer..."
    sudo rm -f /etc/systemd/system/auto_backup.service
    sudo rm -f /etc/systemd/system/auto_backup.timer
    sudo systemctl daemon-reload
    echo "✅ Service and timer removed."

    read -p "Do you also want to remove the .env file? (y/N): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        rm -f .env
        echo ".env file removed."
    fi
fi

echo "✅ Backup automation stopped."
