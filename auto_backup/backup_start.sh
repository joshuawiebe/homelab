#!/usr/bin/env bash
set -euo pipefail

# Source shared logging module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/../.shared/log.sh" 2>/dev/null || {
  echo "[ERROR] Failed to load logging module"
  exit 1
}

ENV_FILE="$SCRIPT_DIR/.env"

# Load config
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
else
    error "Missing .env file in $SCRIPT_DIR"
    echo "Run $SCRIPT_DIR/backup_setup.sh to configure"
    exit 1
fi

# Log output to file
exec >> "$LOG_FILE" 2>&1

section "HomeLab Auto Backup"
info "Started at $(date)"
echo ""

# --- Phase 1: Stop services ---
subsection "Phase 1: Stopping Services"
info "Stopping HomeLab services..."
"$SCRIPT_DIR/../.automations/stop.sh" >/dev/null 2>&1 || warn "Failed to stop some services"
success "Services stopped"
echo ""

# --- Phase 2: Mount USB ---
subsection "Phase 2: Mounting USB Drive"

if mountpoint -q "$BACKUP_MOUNT"; then
    success "USB drive already mounted at $BACKUP_MOUNT"
else
    info "Mounting USB drive: $USB_DEVICE → $BACKUP_MOUNT"
    if sudo mount "$USB_DEVICE" "$BACKUP_MOUNT"; then
        success "USB drive mounted"
    else
        error "Failed to mount USB drive"
        exit 1
    fi
fi
echo ""

# --- Phase 3: Pre-backup prune ---
subsection "Phase 3: Pruning Old Backups (Pre)"
info "Keeping last 3 backups..."
borg prune -v --list "$BORG_REPO" --keep-last 3 2>&1 || warn "Prune had issues"
success "Prune completed"
echo ""

# --- Phase 4: Create backup ---
subsection "Phase 4: Creating Backup"
info "Source: $BACKUP_SRC"
info "Destination: $BORG_REPO"
info "Compression: zstd,3"
echo ""

BACKUP_NAME="backup-$(date +%F-%H%M%S)"
info "Backup name: $BACKUP_NAME"

if borg create \
    --stats \
    --compression zstd,3 \
    "$BORG_REPO::$BACKUP_NAME" \
    "$BACKUP_SRC"; then
    success "Backup created successfully"
else
    error "Backup creation failed"
    exit 1
fi
echo ""

# --- Phase 5: Post-backup prune ---
subsection "Phase 5: Pruning Old Backups (Post)"
info "Removing old backups..."
borg prune -v --list "$BORG_REPO" --keep-last 3 2>&1 || warn "Prune had issues"
success "Cleanup completed"
echo ""

# --- Phase 6: Unmount USB ---
subsection "Phase 6: Unmounting USB Drive"

if mountpoint -q "$BACKUP_MOUNT"; then
    info "Unmounting $BACKUP_MOUNT..."
    if sudo umount "$BACKUP_MOUNT"; then
        success "USB drive unmounted safely"
    else
        warn "Failed to unmount USB - may still be in use"
    fi
else
    info "USB drive was not mounted"
fi
echo ""

# --- Phase 7: Restart services ---
subsection "Phase 7: Restarting Services"
info "Starting HomeLab services..."
"$SCRIPT_DIR/../.automations/start.sh" --proxy "$DEFAULT_PROXY" >/dev/null 2>&1 || warn "Failed to start some services"
success "Services restarted"
echo ""

separator
info "Finished at $(date)"
success "Auto backup completed successfully!"
echo ""

