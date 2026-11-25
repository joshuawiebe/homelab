# Project memory — joshuawiebe/homelab

## Shape
- Docker Compose stack, one folder per service under `services/`: traefik, nextcloud, vaultwarden,
  adguard_home, gotify, uptime_kuma, watchtower. `zoraxy` was removed in 1.1.0 (Traefik owns
  80/443 and TLS; a second proxy with its own ACME store was the problem, not the solution).
- `bin/homelab` is the single entry point: a ~1200-line, stdlib-only Python 3.11+ CLI
  (up/down/restart/status/logs/urls/config/doctor/snapshot/provision/install).
  `.automations/*.sh` are 3-line shims; `auto_backup/` was deleted as superseded.
- Tests: `python3 -m unittest discover -s tests` — 85 tests, no docker daemon needed.
- Two hosts, one CLI: `[hosts.nuc]` / `[hosts.pi]` in `homelab.toml`, Pi stack under
  `hosts/pi/services/`. `--host NAME` filters; `HOMELAB_CONF` swaps the whole config.
- `docs/PLAN.md` is the topology + runbook (Proxmox VM, md/LVM repo, restic copies).

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

## Gotchas added with the two-host work
- Compose `profiles:` services are invisible to a plain `up`; the CLI skips them with a
  notice unless `--profile NAME` is passed, and passes it through to compose.
- `--dry-run` must not skip read-only probes (`Shell.probe`), otherwise `provision --dry-run`
  reports every device as present and every step as already done.
- Doctor counts only `${VAR}` references *without* a default as "needs .env"; otherwise a
  compose file that defaults every variable looks like it is missing its env file.
- Hetzner Storage Box SFTP listens on port 23, and restic's URL carries it: `:23//path`.

## Data layout (settled Nov 2026)
- Stateful bind mounts are `${DATA_DIR:-.}/<name>`; each service `.env` sets
  `DATA_DIR=/srv/homelab/<service>` (templates carry that default). Unset resolves to the old
  in-tree path, so existing installs keep working.
- `homelab migrate data --to DIR --apply` = rsync + dry-run verification + `DATA_DIR` rewrite.
  Only services whose compose mentions `DATA_DIR` are migrated; traefik keeps `./letsencrypt`
  and `./users` in the tree on purpose (moving them would silently re-issue certs).
- History: the Pi was the primary with a USB stick as backup; the NUC is the new primary.
  Cutover order lives in `docs/PLAN.md` phase 0.
- rsync is NOT installed in the agent container (no root), so the migrate apply test uses a
  stub `rsync` shell script on PATH that does `cp -a "${src}." "$dst"`.

## User's actual Pi layout (confirmed)
- Repo AND all service data on the SSD; OS + `/var/lib/docker` on the microSD.
- Therefore: `git clean -xfd` on the Pi is destructive; do not copy data within the Pi (one
  disk, would double usage); pull straight to the NUC with
  `migrate data --from pi.lan:/opt/homelab --to /srv/homelab --apply`.
- `.env` files are gitignored, so they must be carried separately BEFORE `homelab config`,
  otherwise a fresh MYSQL_PASSWORD no longer matches the existing Nextcloud database.
- Doctor now checks named volumes (state in docker's root = the card) and log caps; all
  compose files carry an `x-logging` anchor (10m x 2).

## Release state (v1.0.0, Nov 2026)
- `main` is the only branch; all work lands there via short-lived PR branches that get deleted.
  `homelab --version` prints `VERSION` in `bin/homelab`; keep it equal to the newest git tag.
- `CHANGELOG.md` is the release body source (Keep a Changelog shape, one section per tag).

## Backup correctness rules (found the hard way, all doctor-checked)
- A dump redirected outside `data_dir`/`source` is NOT in the snapshot: the run succeeds and
  the file is missing. Hooks write to `/srv/homelab/dumps`, doctor warns otherwise
  ("snapshot hooks").
- `[snapshot] source` accepts a list. The Pi snapshots the NUC staging mount *and* its own
  `/srv/homelab`, otherwise AdGuard/Kuma/Gotify are never backed up.
- `pre` hooks run on the source host (`--remote` = over ssh); `pre_local` always runs locally.
- `restic copy --repo2` refuses a destination that was never `restic init`ed, so
  `homelab snapshot init` initialises main + every copy and generates one passphrase each.
- `snapshot install` must pin `--conf`: systemd does not inherit `HOMELAB_CONF`, and the Pi's
  config is `hosts/pi/homelab.toml`, not `<root>/homelab.toml`. Without it the timer fails
  before it can send the dead-man's-switch ping.
- `acme.json` must be 600 or Traefik refuses to start; `doctor` checks it. Copying
  `letsencrypt/` between machines also avoids the 5-duplicate-certs/week limit.
- lego has a native `ipv64` provider (since v4.13): `dnschallenge.provider=ipv64` +
  `IPV64_API_KEY`, no inbound port needed. Both hosts share one WAN IP, so a cutover moves
  the port forward, not the DNS record.

## Repo must stay generic (user's explicit requirement, Nov 2026)
- Nothing machine-specific is committed: `[provision.pi] devices` ships empty and
  `homelab config` fills it. It lists whole disks from `/dev/disk/by-id` that are not the root
  disk, not mounted and not a partition, then writes the picked by-id paths back with a regex
  that only replaces the `devices =` line (comments survive; TOML re-parsed after write).
- Discovery is testable without real disks: `DISK_BY_ID_DIR` and `MOUNTS_FILE` are module
  globals in `bin/homelab`; tests swap them for temp dirs. The root disk comes from the `/`
  line of the *injected* mounts file, not `/proc/mounts`.
- OS picks documented in the README: Debian 13 (trixie) netinst for the Proxmox VM (verified
  `debian-cd/current` serves 13.8.0), Raspberry Pi OS Lite 64-bit for the Pi. The debian.org
  releases page in this sandbox still claims 12 Bookworm is stable — cdimage is the reliable
  source.
