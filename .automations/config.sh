#!/bin/bash
set -e

SERVICES=("adguard_home" "gotify" "mongodb" "nextcloud" "uptime_kuma" "vaultwarden" "watchtower" "zoraxy")

echo "Setup homelab..."
read -p "Generate one master password automatically? (y/n): " AUTO_PASS

MASTER_PASS=""

if [ "$AUTO_PASS" = "y" ]; then
  MASTER_PASS=$(openssl rand -base64 24)
  echo "Generated Master Password: $MASTER_PASS"
else
  read -sp "Enter master password: " MASTER_PASS
  echo
fi

for SERVICE in "${SERVICES[@]}"; do
  cd services/$SERVICE

  if [ ! -f .env ]; then
    cp .env.template .env
  fi

  case $SERVICE in
    vaultwarden)
      HASH=$(docker run --rm vaultwarden/server /vaultwarden hash "$MASTER_PASS" | tail -n 1)
      sed -i "s|ADMIN_TOKEN=.*|ADMIN_TOKEN=$HASH|" .env
      ;;
    mongodb|gotify|nextcloud)
      sed -i "s|PASSWORD=.*|PASSWORD=$MASTER_PASS|" .env
      ;;
    adguard_home|uptime_kuma|watchtower|zoraxy)
      # no password needed
      ;;
  esac

  cd ../..
done

if [ "$AUTO_PASS" = "y" ]; then
  read -p "Start services automatically? (y/n): " AUTOSTART
  if [ "$AUTOSTART" = "y" ]; then
    ./start.sh
  fi
fi
