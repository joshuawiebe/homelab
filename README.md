# My Homeserver Setup

This repository contains my personal homeserver configuration using Docker Compose. Each service lives in its own folder under `services/`, with its own `docker-compose.yml` and `.env.template`.

## Repository Structure

```
/homelab/
├── services/
│   ├── nextcloud/
│   │   ├── docker-compose.yml
│   │   └── .env.template
│   ├── vaultwarden/
│   │   ├── docker-compose.yml
│   │   └── .env.template
│   └── zoraxy/
│       ├── docker-compose.yml
│       └── .env.template
├── .gitignore
└── README.md
```

## Included Services

* **Nextcloud** – file sync and personal cloud
* **Vaultwarden** – password manager (Bitwarden-compatible)
* **Zoraxy** – reverse proxy with UI, managing secure access to services

## Goals

* Minimal, maintainable stack
* Fully self-hosted
* Focus on privacy, reliability, and automation

## Notes

* Secrets and credentials are excluded or templated (see each service's `.env.template`)
* Designed for Linux-based systems (I use Ubuntu Server on Raspberry Pi)
* Zoraxy handles TLS termination and routing

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/yourusername/my-homeserver.git
cd my-homeserver
```

### 2. Create the Docker network

Create a shared network called `proxy` (used by all services):

```bash
docker network create proxy
```

### 3. Copy and edit environment files

```bash
cp services/nextcloud/.env.template services/nextcloud/.env
cp services/vaultwarden/.env.template services/vaultwarden/.env
cp services/zoraxy/.env.template services/zoraxy/.env
```

Edit each `.env` to include your secrets and tokens.

### 4. Generate a Vaultwarden Admin PHC String

Vaultwarden provides a built-in PHC generator. Replace `vwcontainer` with your Vaultwarden container name.

* **Using a running container** (Bitwarden defaults):

  ```bash
  ```

docker exec -it vwcontainer /vaultwarden hash

````
- **Using a temporary container**:
```bash
docker run --rm -it vaultwarden/server /vaultwarden hash
````

* **Using OWASP preset**:

  ```bash
  ```

docker exec -it vwcontainer /vaultwarden hash --preset owasp
docker run --rm -it vaultwarden/server /vaultwarden hash --preset owasp

````

Paste the resulting PHC string into `services/vaultwarden/.env` under `ADMIN_TOKEN=`.

### 5. Start Services
```bash
# Nextcloud
docker-compose -f services/nextcloud/docker-compose.yml up -d

# Vaultwarden
docker-compose -f services/vaultwarden/docker-compose.yml up -d

# Zoraxy
docker-compose -f services/zoraxy/docker-compose.yml up -d
````

### 6. Verify Access

* Nextcloud: `https://nextcloud.yourdomain.com`
* Vaultwarden: `https://vault.yourdomain.com`
* Zoraxy UI: `https://zoraxy.yourdomain.com:8000`

> This setup reflects my actual live config — shared for learning, reproducibility, and collaboration.

## License

MIT — you're free to use, adapt, and learn from it. Just don’t blindly copy secrets or paths.

> ⚠️ Warning: This repo contains real configuration logic, but **no secrets** — those are excluded or redacted via `.env.template`.
