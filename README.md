# HomeLab — Dockerized Personal Server Setup

This repository contains my personal home server setup using **Docker Compose**. Every service is organized in its own folder under `services/`, with individual `docker-compose.yml` and `.env.template` files.

All services run in a shared Docker network called `proxy`, so no ports need to be forwarded externally. Routing and TLS are handled via Zoraxy.

---

## Repository Structure

```
/homelab/
├── .automations/
│   ├── config.sh      # Sets up .env files, optionally generates passwords, can start services
│   ├── start.sh       # Starts all services automatically
│   └── stop.sh        # Stops all services automatically
├── services/
│   ├── adguard\_home/
│   │   └── docker-compose.yml
│   ├── gotify/
│   │   └── docker-compose.yml
│   ├── mongodb/
│   │   ├── .env.template
│   │   └── docker-compose.yml
│   ├── nextcloud/
│   │   ├── .env.template
│   │   └── docker-compose.yml
│   ├── uptime\_kuma/
│   │   └── docker-compose.yml
│   ├── vaultwarden/
│   │   ├── .env.template
│   │   └── docker-compose.yml
│   ├── watchtower/
│   │   └── docker-compose.yml
│   └── zoraxy/
│       └── docker-compose.yml
├── .gitignore
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

## Automations Scripts

### `.automations/config.sh`

* Copies `.env.template` files to `.env` in each service folder  
* Prompts user to generate passwords automatically `[Y/n]`  
* Generates passwords for services (Vaultwarden password is hashed via temporary container)  
* Optionally runs `start.sh` if passwords were auto-generated  

### `.automations/start.sh`

* Goes into every service folder containing a `docker-compose.yml`  
* Runs `docker compose up -d`  
* Starts all containers on the shared `proxy` network  

### `.automations/stop.sh`

* Goes into every service folder containing a `docker-compose.yml`  
* Runs `docker compose down`  
* Stops all containers cleanly  

> These scripts allow a new user to clone the repo and get the full environment running with minimal manual setup.  

---

## Environment Files

* `.env.template` – contains placeholders and explanations for credentials  
* `.env` – actual runtime file created from template by `config.sh`  
* Vaultwarden requires an **ADMIN_TOKEN** hashed string for admin access  
* Services without passwords do **not** require `.env` variables  

---

## DIY Backup Server (Planned / Idea)

I plan to add a low-power backup server using a **Raspberry Pi Zero 2W** with an attached HDD/SSD:

* The Pi would run a minimal Linux + Docker setup  
* Backup container could use `rsync`, `rclone`, or a custom Python script  
* Drive mounted at `/mnt/backup`  
* Scheduled backups via cron or container restart policies  
* Optional `.env` for credentials / destinations  

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
