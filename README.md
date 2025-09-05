# HomeLab - Dockerized Personal Server Setup

This repository contains my personal home server setup using **Docker Compose**. Every service is organized in its own folder under `services/`, with individual `docker-compose.yml` and `.env.template` files.

All services run in a shared Docker network called `proxy`, so no ports need to be forwarded externally. Routing and TLS are handled via Zoraxy.

## Quick Start

1. Clone this repository:
   ```bash
   git clone https://github.com/joshuawiebe/homelab.git
   cd homelab
   ```

2. Run the configuration script:
   ```bash
   ./.automations/config.sh
   ```

3. Start all services:
   ```bash
   ./.automations/start.sh
   ```

4. To stop all services:
   ```bash
   ./.automations/stop.sh
   ```

---

## Repository Structure

```
/homelab/
├── .automations/
│   ├── config.sh      # Sets up .env files, optionally generates passwords
│   ├── start.sh       # Starts all services in correct order
│   └── stop.sh        # Stops all services in reverse order
├── services/
│   ├── adguard_home/  # Network-wide ad blocking
│   │   ├── docker-compose.yml
│   │   ├── conf/      # AdGuard configuration
│   │   └── work/      # AdGuard working directory
│   ├── gotify/        # Push notification server
│   │   ├── docker-compose.yml
│   │   └── data/      # Application data and plugins
│   ├── mongodb/       # Database backend
│   │   ├── .env.template
│   │   ├── docker-compose.yml
│   │   └── data/      # Database files
│   ├── nextcloud/     # Personal cloud storage
│   │   ├── .env.template
│   │   ├── docker-compose.yml
│   │   ├── db/        # MariaDB database
│   │   └── nextcloud/ # Nextcloud data
│   ├── uptime_kuma/   # Uptime monitoring
│   │   ├── docker-compose.yml
│   │   └── data/      # Monitor data and screenshots
│   ├── vaultwarden/   # Password manager
│   │   ├── .env.template
│   │   ├── docker-compose.yml
│   │   └── vw-data/   # Encrypted vault data
│   ├── watchtower/    # Automatic container updates
│   │   └── docker-compose.yml
│   └── zoraxy/        # Reverse proxy & TLS
│       ├── docker-compose.yml
│       ├── config/    # Proxy configuration
│       └── plugin/    # Proxy plugins
├── .gitignore         # Excludes sensitive and runtime data
└── README.md
```

> Each service folder contains a `docker-compose.yml` for that service, and `.env.template` files for any sensitive information (passwords, tokens). Actual `.env` files are **generated/copied** by `config.sh` or manually filled by the user.  

---

## Included Services

* **Nextcloud** – personal cloud and file sync  
* **Vaultwarden** – password manager (Bitwarden-compatible)  
* **Zoraxy** – reverse proxy, TLS, and internal routing  
* **MongoDB** – database backend for apps  
* **AdGuard Home** – network-wide ad blocking  
* **Gotify** – notifications server  
* **Uptime Kuma** – uptime monitoring  
* **Watchtower** – auto-update Docker containers  

---

## Automation Scripts

### `.automations/config.sh`

This script handles the initial setup of your homelab:

* Creates `.env` files from `.env.template` for each service
* Offers to generate secure random passwords automatically
* Properly hashes the Vaultwarden admin token
* Can optionally start services after configuration
* Validates environment files before starting

Usage:
```bash
./.automations/config.sh
```

### `.automations/start.sh`

This script starts all services in the correct order:

1. Starts Zoraxy (reverse proxy) first
2. Launches databases (MongoDB)
3. Starts core services (Nextcloud, Vaultwarden)
4. Initializes auxiliary services (AdGuard, Gotify, etc.)
5. Finally starts monitoring (Uptime Kuma, Watchtower)

Usage:
```bash
./.automations/start.sh
```

### `.automations/stop.sh`

This script safely stops all services in reverse order:

1. Stops monitoring services first
2. Shuts down auxiliary services
3. Stops core applications
4. Stops databases last
5. Optionally removes the proxy network

Usage:
```bash
./.automations/stop.sh
```

> The scripts ensure proper startup/shutdown order and handle the shared proxy network.

---

## Environment Files

Each service that requires configuration has a `.env.template` file:

* **MongoDB**: Database credentials and configuration
* **Nextcloud**: Admin password, database settings
* **Vaultwarden**: Admin token (automatically hashed) and SMTP settings

The `config.sh` script will:
1. Copy templates to `.env` files
2. Generate secure random passwords
3. Hash sensitive tokens where required
4. Validate the configuration

## Data Persistence

All service data is stored in volume mounts:

* **AdGuard Home**: `conf/` and `work/` directories
* **Gotify**: `data/` for application state and plugins
* **MongoDB**: `data/` for database files
* **Nextcloud**: `nextcloud/` for files, `db/` for database
* **Uptime Kuma**: `data/` for monitoring history
* **Vaultwarden**: `vw-data/` for encrypted vaults
* **Zoraxy**: `config/` and `plugin/` for configuration

These directories are automatically excluded from git via `.gitignore`.

## Networking

Services communicate through the `proxy` network:

* Zoraxy handles all external traffic
* Internal services are not exposed to the internet
* TLS termination is handled by Zoraxy
* Services reference each other by container name

## Maintenance

1. **Updates**:
   * Watchtower automatically updates containers
   * Check service logs for update status
   * Manual updates possible via `docker compose pull`

2. **Backups**:
   * Each service has its own data directory
   * Back up the entire `services/` directory
   * Critical data in volume mounts (see Data Persistence)
   * Consider using `docker compose down` before backups

3. **Monitoring**:
   * Uptime Kuma provides service monitoring
   * Check container logs: `docker compose logs`
   * Monitor system resources with `docker stats`

> Currently this is **only a plan**. The implementation will follow later once the main HomeLab stack is stable.  

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/joshuawiebe/homelab.git
cd homelab
````

### 2. Run the configuration script

```bash
./.automations/config.sh
```

* Generates `.env` files from templates
* Auto-generates passwords if chosen
* Optionally starts services

### 3. Start / Stop services manually

```bash
./.automations/start.sh
./.automations/stop.sh
```

---

### 4. Vaultwarden Admin Token

Generate hashed admin token using temporary container:

```bash
docker run --rm -it vaultwarden/server /vaultwarden hash
```

Follow prompts to enter your chosen password twice, then paste the resulting PHC string into `services/vaultwarden/.env` under `ADMIN_TOKEN=`.

---

### 5. Verify Access

* Nextcloud: `https://nextcloud.yourdomain.com`
* Vaultwarden: `https://vault.yourdomain.com`
* Zoraxy UI: `https://zoraxy.yourdomain.com`
* Other services: accessible internally via the proxy network

---

## Notes

* No secrets are committed; `.env.template` files only provide placeholders
* All services communicate internally through `proxy` network
* Modular design makes it easy to add new services or features (like DIY backup server)

---

## License

MIT — free to use, adapt, and learn from. Do not copy live credentials or secret paths.
