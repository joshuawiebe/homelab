# My Homeserver Setup

This repository contains my personal homeserver configuration using Docker Compose.

### Included Services
- **Nextcloud** – file sync and personal cloud
- **Vaultwarden** – password manager (Bitwarden-compatible)
- **Zoraxy** – reverse proxy with UI, managing secure access to services

### Goals
- Minimal, maintainable stack
- Fully self-hosted
- Focus on privacy, reliability, and automation

### Notes
- Secrets and credentials are excluded or templated (see `.env.template`)
- Designed for Linux-based systems (I use Ubuntu Server on Raspberry Pi)
- Zoraxy handles TLS termination and routing

### Getting Started
1. Copy `.env.template` to `.env` and fill in your secrets
2. Run `docker-compose up -d` from the `docker/` directory
3. Access services via your reverse proxy hostname

> This setup reflects my actual live config — shared for learning, reproducibility, and collaboration.

### License
MIT — you're free to use, adapt, and learn from it. Just don’t blindly copy secrets or paths.

> ⚠️ Warning: This repo contains real configuration logic, but **no secrets** — those are excluded or redacted via `.env.template`.
