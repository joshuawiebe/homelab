#!/usr/bin/env bash
set -euo pipefail

# Source shared logging module
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$(dirname "$SCRIPT_DIR")/../.shared/log.sh" 2>/dev/null || {
  echo "[ERROR] Failed to load logging module"
  exit 1
}

ENV_FILE="$SCRIPT_DIR/.env"

section "HomeLab Auto Backup Removal"

# Check if configured
if [ ! -f "$ENV_FILE" ]; then
  error "No .env file found - auto backup not configured"
  echo "Nothing to remove."
  exit 1
fi

# Load config to get service name
source "$ENV_FILE"

subsection "Removing Auto Backup Service"

info "Service name: $SERVICE_NAME"
info "Configuration file: $ENV_FILE"
echo ""

# Confirm removal
if ! confirm "Are you sure you want to remove the backup automation"; then
  warn "Removal cancelled"
  exit 0
fi
echo ""

# Remove service files
info "Stopping and disabling timer..."
sudo systemctl disable --now "$SERVICE_NAME.timer" 2>/dev/null || warn "Timer was not active"
success "Timer disabled"

info "Removing systemd unit files..."
sudo rm -f "/etc/systemd/system/$SERVICE_NAME.service"
sudo rm -f "/etc/systemd/system/$SERVICE_NAME.timer"
success "Unit files removed"

info "Reloading systemd..."
sudo systemctl daemon-reload
success "Systemd reloaded"

echo ""
subsection "Cleanup Options"

# Ask about removing config
if confirm "Remove configuration file ($ENV_FILE)"; then
  rm -f "$ENV_FILE"
  success "Configuration file removed"
else
  info "Keeping configuration file for future reference"
fi

echo ""
separator_thick

info "Backup automation has been removed successfully"
info "Backup files are NOT automatically deleted"
info "To re-enable, run: $SCRIPT_DIR/backup_setup.sh"
echo ""

exit_success "Removal complete!"

