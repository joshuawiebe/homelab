#!/bin/bash
# auto_backup/backup_setup.sh
# Interactive setup for Borg backup automation

set -e
cd "$(dirname "$0")"

echo "=== Borg Auto Backup Setup ==="

# Ask user for config
read -p "USB drive label [BACKUP_USB]: " usb_label
read -p "Mount path [/mnt/backup_usb]: " mount_path
read -p "Source path to backup [/]: " src
read -p "Repo path [/mnt/backup_usb/borgrepo]: " repo
read -p "Borg passphrase (no echo): " -s passphrase
echo
read -p "Daily backup time [02:00:00]: " backup_time

# Apply defaults if empty
usb_label=${usb_label:-BACKUP_USB}
mount_path=${mount_path:-/mnt/backup_usb}
src=${src:-/}
repo=${repo:-$mount_path/borgrepo}
passphrase=${passphrase:-changeme}
backup_time=${backup_time:-02:00:00}

# Write .env file
cat > .env <<EOF
BACKUP_USB_LABEL=$usb_label
BACKUP_MOUNT=$mount_path
BACKUP_SRC=$src
BORG_REPO=$repo
BORG_PASSPHRASE=$passphrase
LOG_FILE=$mount_path/backup.log
BACKUP_TIME=$backup_time
EOF

echo ".env created!"

# Ensure mount point exists
sudo mkdir -p "$mount_path"

# Install Borg if missing
if ! command -v borg &> /dev/null; then
    echo "Installing borg..."
    sudo apt update && sudo apt install -y borgbackup
fi

# Initialize repo if not exists
if [ ! -d "$repo" ]; then
    echo "Initializing Borg repo..."
    BORG_PASSPHRASE=$passphrase borg init --encryption=repokey-blake2 "$repo"
fi

# Create systemd service
SERVICE_FILE="/etc/systemd/system/auto_backup.service"
sudo tee $SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=Daily Borg Backup (from homelab/auto_backup)

[Service]
Type=oneshot
User=$(whoami)
EnvironmentFile=$PWD/.env
ExecStart=$PWD/backup_start.sh
EOF

# Create systemd timer
TIMER_FILE="/etc/systemd/system/auto_backup.timer"
sudo tee $TIMER_FILE > /dev/null <<EOF
[Unit]
Description=Run Borg backup daily

[Timer]
OnCalendar=*-*-* $backup_time
Persistent=true

[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now auto_backup.timer

echo "✅ Setup complete! Backup runs daily at $backup_time"
echo "Check status with: sudo systemctl status auto_backup.timer"
echo "View logs with: journalctl -u auto_backup.service"