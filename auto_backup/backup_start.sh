#!/bin/bash
# auto_backup/backup_start.sh
# Runs the backup using .env config

set -e
cd "$(dirname "$0")"
source .env

echo "Backup started at $(date)" >> $LOG_FILE

# Mount USB if not mounted
if ! mountpoint -q "$BACKUP_MOUNT"; then
    sudo mount -L $BACKUP_USB_LABEL "$BACKUP_MOUNT"
fi

# Run Borg backup
borg create --verbose --stats --progress \
    $BORG_REPO::'{hostname}-{now:%Y-%m-%d}' \
    $BACKUP_SRC >> $LOG_FILE 2>&1

# Prune old backups (keep last 7 daily)
borg prune -v --keep-daily=7 $BORG_REPO >> $LOG_FILE 2>&1

# Unmount USB
sudo umount "$BACKUP_MOUNT"

echo "Backup finished at $(date)" >> $LOG_FILE
echo "----------------------------------------" >> $LOG_FILE