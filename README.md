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

    * Set the **base domain** (e.g., `example.com`)
    * Set **subdomains** for each service
    * Provide **ACME email** and **IPv64 DNS API token**
    * Optionally generate passwords automatically

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

``` filetree
/homelab/
├── .automations/
│   ├── config.sh
│   ├── start.sh
│   └── stop.sh
├── services/
│   ├── adguard_home/
│   ├── gotify/
│   ├── nextcloud/
│   ├── uptime_kuma/
│   ├── vaultwarden/
│   ├── watchtower/
│   └── traefik/
├── auto_backup/            # New Borg backup automation
│   ├── backup_setup.sh
│   ├── backup_start.sh
│   ├── backup_stop.sh
│   └── .env.sample
├── .gitignore
└── README.md
```

---

## Services

* **Nextcloud** – personal cloud storage (HSTS enabled)
* **Vaultwarden** – password manager (Bitwarden-compatible)
* **Traefik** – reverse proxy, HTTPS, ACME DNS challenge
* **AdGuard Home** – network-wide ad blocking
* **Gotify** – push notifications
* **Uptime Kuma** – uptime monitoring
* **Watchtower** – automatic container updates

---

## Automation Scripts

### `config.sh`

* Generates `.env` files from templates
* Configures base domain, subdomains, ACME email, and IPv64 token
* Generates secure passwords
* Generates hashed Vaultwarden admin token
* Optionally starts services

### `start.sh`

* Starts services in correct order
* Prompts to choose reverse proxy (Traefik or Zoraxy)

### `stop.sh`

* Stops all services safely in reverse order

---

## Auto Backup Automation (Borg)

The new `auto_backup/` folder provides a fully automated **daily backup system** using **Borg**. Backups run on a USB drive, prune old archives, and log activity.

### Folder structure

``` filetree
auto_backup/
├── backup_setup.sh      # Interactive setup, generates .env, systemd service/timer
├── backup_start.sh      # Runs the backup based on .env config
├── backup_stop.sh       # Stops or removes automation
├── .env.sample          # Sample configuration
```

### Features

* Interactive setup: USB label, mount path, source path, repo path, passphrase, backup time
* Daily backups with pruning (keep last 7 daily by default)
* Logs stored on the USB drive
* Systemd timer ensures automatic execution
* Stop or fully remove automation with `backup_stop.sh`

### Setup & Usage

1. **Run setup**:

    ```bash
    cd auto_backup
    ./backup_setup.sh
    ```

    * Answer prompts for USB label, mount path, repo path, backup source, passphrase, and daily backup time.
    * Generates `.env` file and systemd service/timer.

2. **Test backup manually**:

    ```bash
    systemctl start auto_backup.service
    journalctl -u auto_backup.service -n 50
    ```

3. **Stop automation**:

    ```bash
    ./backup_stop.sh
    ```

4. **Stop and remove automation** (optional):

    ```bash
    ./backup_stop.sh --remove
    ```

---

## Environment Files

* `.env.template` files hold placeholders
* `config.sh` creates `.env` files with secure values
* `auto_backup/.env` stores backup-specific config (USB, repo, schedule, passphrase)
* Do **not** commit `.env` files containing secrets

---

## Networking

* All services communicate via Docker network `proxy`
* Traefik handles HTTPS and routing
* Services are not directly exposed

---

## Data Persistence

* **Nextcloud**: `nextcloud/`, `db/`
* **Vaultwarden**: `vw-data/`
* **AdGuard Home**: `conf/`, `work/`
* **Gotify**: `data/`
* **Uptime Kuma**: `data/`
* **Traefik**: `acme.json` (certificates)
* **Backups**: stored on USB in `borgrepo` folder

---

## Vaultwarden Admin Token

```bash
docker run --rm -it vaultwarden/server /vaultwarden hash
```

* Enter password twice
* Copy PHC string into `services/vaultwarden/.env` under `ADMIN_TOKEN=`

---

## Verify Access

* Nextcloud: `https://nextcloud.BASE_DOMAIN`
* Vaultwarden: `https://vault.BASE_DOMAIN`
* Traefik Dashboard: `https://traefik.BASE_DOMAIN`
* Other services follow their configured subdomains

---

## Notes

* No secrets are committed; only `.env.template` and `.env.sample` are included
* Modular design allows easy addition of new services
* Traefik handles all HTTPS termination and routing
* Internal services communicate via proxy network

---

## License

MIT — free to use, adapt, and learn from. Do not commit live credentials.
