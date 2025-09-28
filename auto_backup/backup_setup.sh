#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

echo "=== Auto Backup Setup ==="

# Ask for config
read -rp "Enter USB device path (e.g., /dev/sda1): " USB_DEVICE
read -rp "Enter USB mount point (e.g., /mnt/backup_usb): " USB_MOUNTPOINT
read -rp "Enter source path to back up (e.g., /mnt/ssd/): " SOURCE_PATH
read -rp "Enter systemd service name (default: auto-backup): " SERVICE_NAME
SERVICE_NAME=${SERVICE_NAME:-auto-backup}

# Save to .env
cat > "$ENV_FILE" <<EOF
USB_DEVICE=$USB_DEVICE
USB_MOUNTPOINT=$USB_MOUNTPOINT
SOURCE_PATH=$SOURCE_PATH
SERVICE_NAME=$SERVICE_NAME
EOF

echo "[INFO] Configuration saved to $ENV_FILE"

# Create systemd service file
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
TIMER_FILE="/etc/systemd/system/$SERVICE_NAME.timer"

sudo tee "$SERVICE_FILE" > /dev/null <<EOF
[Unit]
Description=Automatic Borg Backup

[Service]
Type=oneshot
EnvironmentFile=$ENV_FILE
ExecStart=$SCRIPT_DIR/backup_start.sh
EOF

# Create systemd timer file (daily at 02:00)
sudo tee "$TIMER_FILE" > /dev/null <<EOF
[Unit]
Description=Run automatic backup daily at 02:00

[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable timer
sudo systemctl daemon-reload
sudo systemctl enable --now "$SERVICE_NAME.timer"

echo "[INFO] Systemd service and timer installed and started."
