# HomeLab - Dockerized Personal Server Setup

This repository contains a personal home server setup using **Docker Compose**. Each service has its own folder under `services/` with individual `docker-compose.yml` and `.env.template` files.

All services run in a shared Docker network called `proxy`. Routing and TLS are handled via **Traefik** using ACME DNS challenge.

---

## Quick Start

1. **Clone the repository**:
```bash
git clone https://github.com/joshuawiebe/homelab.git
cd homelab
```

2. **Run configuration**:
```bash
./.automations/config.sh
```
- Set the **base domain** (e.g., `example.com`)
- Set **subdomains** for each service
- Provide **ACME email** and **IPv64 DNS API token**
- Optionally generate passwords automatically

3. **Start all services**:
```bash
./.automations/start.sh
```

4. **Stop services**:
```bash
./.automations/stop.sh
```

---

## Repository Structure

```
/homelab/
├── .automations/
│   ├── config.sh      # Generates .env files, passwords, and domain setup
│   ├── start.sh       # Starts services in correct order
│   └── stop.sh        # Stops services in reverse order
├── services/
│   ├── adguard_home/
│   │   ├── docker-compose.yml
│   │   └── conf/, work/
│   ├── gotify/
│   │   ├── docker-compose.yml
│   │   └── data/
│   ├── nextcloud/
│   │   ├── docker-compose.yml
│   │   ├── .env.template
│   │   └── nextcloud/, db/
│   ├── uptime_kuma/
│   │   ├── docker-compose.yml
│   │   └── data/
│   ├── vaultwarden/
│   │   ├── docker-compose.yml
│   │   ├── .env.template
│   │   └── vw-data/
│   ├── watchtower/
│   │   └── docker-compose.yml
│   └── traefik/
│       ├── docker-compose.yml
│       └── .env.template
├── .gitignore
└── README.md
```

---

## Services

- **Nextcloud** – personal cloud storage (HSTS enabled)  
- **Vaultwarden** – password manager (Bitwarden-compatible)  
- **Traefik** – reverse proxy, HTTPS, ACME DNS challenge  
- **AdGuard Home** – network-wide ad blocking  
- **Gotify** – push notifications  
- **Uptime Kuma** – uptime monitoring  
- **Watchtower** – automatic container updates  

---

## Automation Scripts

### `config.sh`
- Generates `.env` files from templates
- Configures base domain, subdomains, ACME email, and IPv64 token
- Generates secure passwords
- Generates hashed Vaultwarden admin token
- Optionally starts services

### `start.sh`
- Starts services in correct order
- Prompts to choose reverse proxy (Traefik or Zoraxy)

### `stop.sh`
- Stops all services safely in reverse order

---

## Environment Files

- `.env.template` files hold placeholders
- `config.sh` creates `.env` files with secure values
- Supports subdomains and domain configuration per service

---

## Networking

- All services communicate via Docker network `proxy`
- Traefik handles HTTPS and routing
- Services are not directly exposed

---

## Data Persistence

- **Nextcloud**: `nextcloud/`, `db/`  
- **Vaultwarden**: `vw-data/`  
- **AdGuard Home**: `conf/`, `work/`  
- **Gotify**: `data/`  
- **Uptime Kuma**: `data/`  
- **Traefik**: `acme.json` (certificates)  

---

## Vaultwarden Admin Token

```bash
docker run --rm -it vaultwarden/server /vaultwarden hash
```

- Enter password twice
- Copy PHC string into `services/vaultwarden/.env` under `ADMIN_TOKEN=`

---

## Verify Access

- Nextcloud: `https://nextcloud.BASE_DOMAIN`  
- Vaultwarden: `https://vault.BASE_DOMAIN`  
- Traefik Dashboard: `https://traefik.BASE_DOMAIN`  
- Other services follow their configured subdomains

---

## Notes

- No secrets are committed; only `.env.template` files are included  
- Modular design allows easy addition of new services  
- Traefik handles all HTTPS termination and routing  
- Internal services communicate via proxy network

---

## License

MIT — free to use, adapt, and learn from. Do not commit live credentials.