#!/bin/bash
set -e

# ===========================
# HomeLab Configuration
# ===========================

# Function to log messages
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log "Error: Docker is not running or not accessible"
        exit 1
    fi
}

# Function to check if image exists and pull if needed
ensure_docker_image() {
    local image="$1"
    if ! docker image inspect "$image" >/dev/null 2>&1; then
        log "Pulling Docker image: $image"
        if ! docker pull "$image"; then
            log "Error: Failed to pull Docker image $image"
            return 1
        fi
    fi
    return 0
}

echo "=========================="
echo " HomeLab Configuration"
echo "=========================="

# Check Docker status
check_docker

# Create Docker network if it doesn't exist
if ! docker network inspect proxy >/dev/null 2>&1; then
    docker network create proxy
    echo "Docker network 'proxy' created."
else
    echo "Docker network 'proxy' already exists."
fi

# Ask if passwords should be auto-generated
read -p "Generate passwords automatically for services that need them? [Y/n]: " AUTO_PASS
AUTO_PASS=${AUTO_PASS:-Y}

# Generate a master password for Vaultwarden hashing
if [[ "$AUTO_PASS" =~ ^[Yy]$ ]]; then
    MASTER_PASS=$(openssl rand -base64 32)
    echo "Generated master password for Vaultwarden hashing."
fi

# Function to hash Vaultwarden admin token
vaultwarden_hash() {
    local PASS="$1"
    if [ -z "$PASS" ]; then
        log "Error: No password provided to vaultwarden_hash"
        return 1
    fi

    # Ensure Vaultwarden image exists
    if ! ensure_docker_image "vaultwarden/server"; then
        log "Error: Failed to ensure Vaultwarden image is available"
        return 1
    fi
    
    # Try to hash the password
    local hash_output
    if ! hash_output=$(echo -n "$PASS" | docker run --rm -i vaultwarden/server /usr/bin/argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4 2>&1); then
        log "Error: Failed to hash password with Vaultwarden"
        log "Error details: $hash_output"
        return 1
    fi
    
    # Get the last line which should contain only the hash
    echo "$hash_output" | tail -n 1
}

# Function to validate .env template exists
check_env_template() {
    local service="$1"
    local template="services/$service/.env.template"
    if [ ! -f "$template" ]; then
        log "Error: $template does not exist"
        return 1
    fi
    return 0
}

# Services and their env files
declare -A SERVICES
SERVICES=(
    ["mongodb"]="PASSWORD"
    ["nextcloud"]="MYSQL_PASSWORD"
    ["vaultwarden"]="ADMIN_TOKEN"
)

# Loop over services
for SERVICE in "${!SERVICES[@]}"; do
    ENV_TEMPLATE="services/$SERVICE/.env.template"
    ENV_FILE="services/$SERVICE/.env"

    # Check if template exists
    if ! check_env_template "$SERVICE"; then
        log "Skipping $SERVICE due to missing template"
        continue
    fi

    # Copy .env.template if .env doesn't exist
    if [ ! -f "$ENV_FILE" ]; then
        cp "$ENV_TEMPLATE" "$ENV_FILE"
        log "Created $ENV_FILE from template"
    fi

    # Fill passwords if auto-generate is chosen
    if [[ "$AUTO_PASS" =~ ^[Yy]$ ]]; then
        case $SERVICE in
            vaultwarden)
                if [ -z "$MASTER_PASS" ]; then
                    MASTER_PASS=$(openssl rand -base64 32)
                fi
                if HASHED=$(vaultwarden_hash "$MASTER_PASS"); then
                    grep -q "^ADMIN_TOKEN=" "$ENV_FILE" || echo "ADMIN_TOKEN=" >> "$ENV_FILE"
                    sed -i "s|^ADMIN_TOKEN=.*|ADMIN_TOKEN=$HASHED|" "$ENV_FILE"
                    log "Set admin token for Vaultwarden in $ENV_FILE"
                else
                    log "Failed to set Vaultwarden admin token"
                    continue
                fi
                ;;
            mongodb)
                PASS=$(openssl rand -base64 24)
                grep -q "^PASSWORD=" "$ENV_FILE" || echo "PASSWORD=" >> "$ENV_FILE"
                sed -i "s|^PASSWORD=.*|PASSWORD=$PASS|" "$ENV_FILE"
                log "Set database password for MongoDB in $ENV_FILE"
                ;;
            nextcloud)
                PASS=$(openssl rand -base64 24)
                grep -q "^MYSQL_PASSWORD=" "$ENV_FILE" || echo "MYSQL_PASSWORD=" >> "$ENV_FILE"
                sed -i "s|^MYSQL_PASSWORD=.*|MYSQL_PASSWORD=$PASS|" "$ENV_FILE"
                log "Set database password for Nextcloud in $ENV_FILE"
                ;;
        esac
    else
        log "Please fill passwords manually in $ENV_FILE"
    fi
done

# Ask if start.sh should run automatically
if [[ "$AUTO_PASS" =~ ^[Yy]$ ]]; then
    read -p "Start all services automatically? [Y/n]: " AUTOSTART
    AUTOSTART=${AUTOSTART:-Y}
    if [[ "$AUTOSTART" =~ ^[Yy]$ ]]; then
        if [ -f "./.automations/start.sh" ]; then
            log "Starting services..."
            bash ./.automations/start.sh
        else
            log "Error: start.sh not found in .automations directory"
        fi
    fi
fi

log "Configuration finished."
