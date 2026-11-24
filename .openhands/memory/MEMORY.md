# Project memory — joshuawiebe/homelab

## Shape
- Docker Compose stack, one folder per service under `services/`: traefik, nextcloud, vaultwarden,
  adguard_home, gotify, uptime_kuma, watchtower, zoraxy.
- `bin/homelab` is the single entry point: a ~1200-line, stdlib-only Python 3.11+ CLI
  (up/down/restart/status/logs/urls/config/doctor/snapshot/install).
  `.automations/*.sh` are 3-line shims; `auto_backup/` was deleted as superseded.
- Tests: `python3 -m unittest discover -s tests` — 34 tests, no docker daemon needed.

## Facts that were expensive to learn
- `docker compose -f X config` validates YAML **without** a running daemon. Used as the
  verification harness for compose edits, and in the test suite when docker exists.
- The ACME resolver is named `dns`, shared by every service label and by traefik's flags.
  The lego provider env var is `IPV64_API_KEY` (the template used to say IPV64_TOKEN — that
  mismatch alone produced zero certificates).
- Dashboard auth uses `basicauth.usersfile=/etc/traefik/users`. Bcrypt hashes contain `$`,
  and Compose interpolates `$` inside `.env` values *and* label values, so inline
  `user:hash` cannot work reliably.
- `((VAR++))` under `set -e` exits when VAR was 0 (returns the old value). Use `VAR=$((VAR+1))`.
  This silently killed start.sh/stop.sh/config.sh after one iteration.
- `homelab up` with no explicit services skips a second 80/443 binder with a notice; only
  naming both proxies explicitly raises a conflict error.
- Nextcloud behind the proxy needs TRUSTED_PROXIES, OVERWRITEPROTOCOL, OVERWRITEHOST and
  APACHE_DISABLE_REWRITE_IP, otherwise "untrusted domain" / redirect loops.

## User hardware plan (Nov 2026)
- NUC: NVMe (OS) + 1 TB SATA SSD (`/srv/homelab`), 16 GB RAM. Wants Proxmox as a thin
  admin layer with one Docker VM, pass-through of the 1 TB disk, LVM-thin on the NVMe.
- Pi 5: microSD OS (flagged: weakest link), several SSD/HDD to be pooled. Intended restic
  target with a pull model, plus AdGuard/alerting. Offsite: Hetzner Storage Box.
- Preferences: CLI-driven tooling, minimal dependencies, no invented image tags.
