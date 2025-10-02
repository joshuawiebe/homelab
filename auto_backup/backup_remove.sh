#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "[ERROR] No .env file found in $SCRIPT_DIR"
  exit 1
fi

# Load config
source "$ENV_FILE"

SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
TIMER_FILE="/etc/systemd/system/$SERVICE_NAME.timer"

echo "[INFO] Stopping and disabling $SERVICE_NAME.timer..."
sudo systemctl disable --now "$SERVICE_NAME.timer" || true

echo "[INFO] Removing systemd unit files..."
sudo rm -f "$SERVICE_FILE" "$TIMER_FILE"

echo "[INFO] Reloading systemd..."
sudo systemctl daemon-reload

read -rp "Do you also want to remove $ENV_FILE? [y/N]: " REMOVE_ENV
if [[ "$REMOVE_ENV" =~ ^[Yy]$ ]]; then
  rm -f "$ENV_FILE"
  echo "[INFO] Removed $ENV_FILE"
fi

echo "[INFO] Auto backup automation removed successfully."
echo "[INFO] Please remember to manually delete any backup files if needed."
echo "[INFO] To re-enable the service, run the setup script again."
echo "========================================="
