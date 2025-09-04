#!/bin/bash
set -e

# HomeLab Services
SERVICES=("adguard_home" "gotify" "mongodb" "nextcloud" "uptime_kuma" "vaultwarden" "watchtower" "zoraxy")
ROOT_DIR="$(pwd)"
NETWORK_NAME="proxy"

echo "=========================="
echo " HomeLab Configuration"
echo "=========================="

# Create Docker network if it doesn't exist
if ! docker network inspect $NETWORK_NAME >/dev/null 2>&1; then
  echo "Creating Docker network: $NETWORK_NAME"
  docker network create $NETWORK_NAME
else
  echo "Docker network '$NETWORK_NAME' already exists."
fi

# Ask user if passwords should be auto-generated
read -p "Generate passwords automatically for services that need them? [Y/n]: " AUTO_PASS
AUTO_PASS=${AUTO_PASS:-Y}

# Generate one master password for hashing Vaultwarden
if [[ "$AUTO_PASS" =~ ^[Yy]$ ]]; then
  MASTER_PASS=$(openssl rand -base64 24)
  echo "Generated master password for Vaultwarden hashing."
else
  echo "You will need to manually fill passwords in .env files for each service."
fi

# Iterate through all services
for SERVICE in "${SERVICES[@]}"; do
  SERVICE_DIR="$ROOT_DIR/services/$SERVICE"
  cd "$SERVICE_DIR"

  # Copy .env.template to .env if not exists
  if [ ! -f .env ]; then
    if [ -f .env.template ]; then
      cp .env.template .env
      echo "Created .env for $SERVICE"
    fi
  fi

  # Auto-generate passwords
  if [[ "$AUTO_PASS" =~ ^[Yy]$ ]]; then
    case $SERVICE in
      vaultwarden)
        # Vaultwarden requires hashing via Docker
        HASH=$(docker run --rm -i vaultwarden/server /vaultwarden hash <<<"$MASTER_PASS"$'\n'"$MASTER_PASS")
        sed -i "s|ADMIN_TOKEN=.*|ADMIN_TOKEN=$HASH|" .env
        echo "Set Vaultwarden ADMIN_TOKEN (hashed) in .env"
        ;;
      mongodb|nextcloud)
        DB_PASS=$(openssl rand -base64 24)
        sed -i "s|MYSQL_PASSWORD=.*|MYSQL_PASSWORD=$DB_PASS|" .env || true
        sed -i "s|MYSQL_ROOT_PASSWORD=.*|MYSQL_ROOT_PASSWORD=$DB_PASS|" .env || true
        echo "Set database password for $SERVICE in .env"
        ;;
      gotify)
        GOTIFY_PASS=$(openssl rand -base64 24)
        sed -i "s|GOTIFY_ADMIN_PASSWORD=.*|GOTIFY_ADMIN_PASSWORD=$GOTIFY_PASS|" .env || true
        echo "Set Gotify admin password in .env"
        ;;
    esac
  fi

  cd "$ROOT_DIR"
done

# Ask if services should start automatically
if [[ "$AUTO_PASS" =~ ^[Yy]$ ]]; then
  read -p "Start all services now? [Y/n]: " AUTOSTART
  AUTOSTART=${AUTOSTART:-Y}
  if [[ "$AUTOSTART" =~ ^[Yy]$ ]]; then
    bash ./.automations/start.sh
  fi
fi

echo "Configuration complete."
