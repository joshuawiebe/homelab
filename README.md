# HomeLab

A dockerised personal server, driven by one CLI.

Every service lives in its own folder under `services/` with a `docker-compose.yml` and
an `.env` (generated from `.env.template`). All services share the `proxy` network;
TLS terminates at **Traefik** and certificates come from an ACME **DNS challenge**, so
nothing needs to be reachable from the internet to get a certificate.

The `homelab` command replaces the old `.automations/*.sh` scripts and the
`auto_backup/` borg scripts. Those are gone; this one tool starts, inspects, verifies
and snapshots the stack.

---

## Requirements

* Docker Engine with the Compose v2 plugin
* Python **3.11+** (stdlib only, no pip packages)
* `openssl` or `htpasswd` when generating the dashboard password

---

## Install

```bash
git clone https://github.com/joshuawiebe/homelab.git
cd homelab

sudo ./install.sh                 # symlink into /usr/local/bin + bash completion
sudo ./install.sh --with-timer    # ... and install the nightly snapshot timer
```

Without installing, `./bin/homelab <command>` works from the checkout.

---

## Quick start

```bash
homelab config        # prompts for domains, email, DNS token; generates secrets
homelab doctor        # preflight: ports, env vars, resolver names, disk, pins
homelab up            # start everything in dependency order
homelab status        # container state, health, public URL
```

`homelab config` is interactive but not chatty: it shows the template comment for each
key, generates strong values for anything secret-looking, keeps existing values unless
you pass `--reconfigure`, and writes every `.env` with mode `600`. It also writes
`services/traefik/users` (an htpasswd entry for the dashboard) — the plaintext password
is never stored.

For unattended setup:

```bash
homelab config --non-interactive
```

---

## CLI reference

| Command | What it does |
|---|---|
| `homelab config [--reconfigure] [--non-interactive]` | create/refresh `.env` files and the dashboard htpasswd |
| `homelab doctor [--json] [--strict]` | preflight checks; exit 1 on a failure (or any warning with `--strict`) |
| `homelab up [SERVICE...] [--proxy NAME] [--wait N] [--dry-run]` | start in dependency order, wait for health |
| `homelab down [SERVICE...]` | stop in reverse order |
| `homelab restart [SERVICE...]` | down then up |
| `homelab status [--json]` | table of state, health, image and URL |
| `homelab urls` | print each service's public URL from its `.env` |
| `homelab logs SERVICE [-f] [-n N]` | tail one service |
| `homelab snapshot run` | pre-hooks, snapshot, retention, verify, notify |
| `homelab snapshot copy [--only NAME]` | replicate to each `[[snapshot.copies]]` target |
| `homelab snapshot list / verify / stats` | inspect the repository |
| `homelab snapshot extract SNAP DIR [--include PATH]` | put files back |
| `homelab snapshot install / uninstall` | systemd timer for the nightly run |
| `homelab migrate data [--to DIR] [--from HOST:ROOT] [--apply]` | copy service state out of the git tree (or straight off another host), verify it, record `DATA_DIR` |
| `homelab provision pi [--apply] [--yes]` | build the mirrored repo on the Pi |
| `homelab install [--prefix DIR]` | symlink the CLI into `PATH` |

Global flags: `--root DIR`, `--host NAME`, `--conf FILE`, `--verbose`, `--version`.

`--host` limits everything to one host's service list (`[hosts.nuc]` in `homelab.toml`),
so `homelab --host nuc up` starts exactly what runs on the NUC and nothing else.
`HOMELAB_CONF` works instead of `--conf`, which is how the Pi keeps its own file.

`--dry-run` prints the exact `docker`/`restic` commands without running them. Use it
when you are unsure; it is also what the test suite asserts against.

---

## What `doctor` checks

Ordered from "will not boot" to "smells":

* docker binary, daemon reachable, Compose v2
* `proxy` network exists
* per service: `.env` present, mode `600`, no leftover `(put your ...)` placeholders,
  every template key present, and **every `${VAR}` the compose file references defined**
  — this is what catches a renamed variable before you debug a silent failure
* ACME resolver: every `tls.certresolver=X` label points at a resolver the proxy
  actually defines
* dashboard htpasswd file exists and is `600`
* host ports 80/443/53 free (`systemd-resolved` will hold 53)
* image tags: `:latest` and untagged images are flagged
* `docker.sock` mounted read-write (root-equivalent)
* named volumes: state inside docker's data-root, which on a Pi is the microSD
* unbounded `json-file` logs: they fill the disk and wear out an SD card
* container state living inside the git tree
* free space on `data_dir` and the snapshot repo
* snapshot repo: present and mounted, newest snapshot younger than 36 hours, and every
  `[[snapshot.copies]]` target fresh — a backup that stopped three weeks ago is the most
  common homelab failure and the hardest to notice

Exit code is 1 on any `FAIL`, so it is safe to run from cron or a deploy script.

---

## Services

| Service | Role |
|---|---|
| `traefik` | reverse proxy, ACME DNS challenge, security headers, rate limit |
| `nextcloud` + `db` + `redis` | personal cloud storage |
| `vaultwarden` | Bitwarden-compatible password manager |
| `adguard_home` | network-wide DNS filtering |
| `gotify` | push notifications |
| `uptime_kuma` | uptime monitoring |
| `watchtower` | image updates — **opt-in per container** |
| `zoraxy` | alternative reverse proxy, mutually exclusive with Traefik |

Traefik and Zoraxy both publish 80/443, so `homelab up` refuses to start both unless
you pass `--allow-port-conflict`. Pick one with `--proxy` or `[general] proxy` in
`homelab.toml`.

Image versions are pinned through env vars so you never edit a compose file to pin:

```bash
# services/nextcloud/.env
NEXTCLOUD_IMAGE=nextcloud:32-apache
MARIADB_IMAGE=mariadb:11.4
```

Watchtower now runs with `--label-enable --interval 86400`: it only touches containers
labelled `com.centurylinklabs.watchtower.enable=true`, once a day. Nothing is upgraded
behind your back. Add the label to the services you are happy to see move.

---

## Snapshots

`homelab snapshot` wraps **restic** (default) or **borg**, configured in
`homelab.toml` (copy `homelab.toml.example`).

The intended shape is a **pull** model: the backup job runs on a small always-on machine
(a Pi 5 with SSDs), reads the server over SSH, and holds the repository passphrase.
The server being snapshotted never learns the passphrase and has no write access to the
repository, so a compromised server cannot delete its own history.

```
  NUC (proxmox -> docker VM)          Pi 5 (always on)
  /srv/homelab  ---- ssh pull ---->   restic repo on a md/LVM mirror
                                      restic copy -> second disk
                                      restic copy -> offsite storage box
```

Databases must not be copied as raw files. `[snapshot] pre` runs the dump commands
before the snapshot, which keeps the stack online:

```toml
pre = [
  "docker exec db sh -c 'exec mysqldump --single-transaction --quick --all-databases' > /srv/dumps/nextcloud.sql",
  "sqlite3 /srv/homelab/vaultwarden/vw-data/db.sqlite3 '.backup /srv/dumps/vaultwarden.sqlite'",
]
```

Run those hooks on the source host with `--remote user@host`:

```bash
homelab snapshot run --remote backups@nuc.lan
```

Retention and verification defaults: `keep-daily 7`, `keep-weekly 4`,
`keep-monthly 6`, plus a weekly `check --read-data-subset=5%`. Set
`[snapshot] healthcheck_url` to a dead-man's-switch ping URL — a snapshot that silently
stopped three weeks ago is the most common homelab failure, and that ping is the only
thing that catches it.

### Copies

`[[snapshot.copies]]` adds replicas. `homelab snapshot copy` runs `restic copy --repo2` to
each target and prunes it on its own retention, so the offsite copy can be longer-lived than
the primary:

```toml
[[snapshot.copies]]
name = "cold"
repo = "/srv/cold/restic"                     # separate HDD on the Pi
password_file = "/etc/homelab/restic-cold.password"
keep_daily = 14

[[snapshot.copies]]
name = "offsite"
repo = "sftp:u123456@u123456.your-storagebox.de:23//restic"
password_file = "/etc/homelab/restic-offsite.password"
limit_upload = 30000                          # KiB/s, keeps your uplink usable
```

`copy = true` under `[snapshot]` runs the copies at the end of every `snapshot run`.
Use a different passphrase per repository, and keep those passphrases somewhere that is not
these machines.

Test a recovery every few months:

```bash
homelab snapshot list
homelab snapshot extract latest /tmp/restore-check --include 'vaultwarden.sqlite'
```

---

## Security notes

* Secrets live in `services/*/.env` (mode `600`) and `services/traefik/users`; all are
  gitignored. Only templates are committed.
* The dashboard uses an htpasswd **file**, not `${USER}:${PASS}` labels — bcrypt hashes
  contain `$`, which Compose would try to interpolate.
* All routed services get `security-headers@docker` and `ratelimit@docker`
  (50 rps average, 100 burst). Tune in `services/traefik/docker-compose.yml`.
* Nextcloud is configured for a reverse proxy: `TRUSTED_PROXIES`, `OVERWRITEPROTOCOL`,
  `OVERWRITEHOST`, `APACHE_DISABLE_REWRITE_IP`.
* `docker.sock` is mounted read-write in `watchtower` and `zoraxy`. That is
  root-equivalent. If you do not need Zoraxy, delete it.
* Better than any WAF: put the whole stack behind Tailscale and stop publishing it.
  `homelab doctor` works either way.

---

## Layout

```
homelab/
├── bin/homelab                  # the CLI (single file, stdlib only)
├── completions/homelab.bash
├── install.sh
├── homelab.toml.example
├── docs/PLAN.md                 # hardware, phases, runbooks, failure modes
├── services/                    # what runs on the NUC
│   └── <name>/docker-compose.yml + .env.template
├── hosts/pi/                    # what runs on the Pi
│   ├── homelab.toml             # services_dir, provision, snapshot targets
│   └── services/<name>/docker-compose.yml
├── tests/test_homelab.py        # python3 -m unittest discover -s tests
└── .automations/                # thin shims that exec the CLI
```

Two hosts, two stacks, one CLI. The Pi's services are separate compose files on purpose:
AdGuard there needs host networking and port 53, not Traefik labels, and its UI belongs on
the LAN. `docs/PLAN.md` explains the whole topology, including the Proxmox VM and the
three-copy backup chain.

Container state must live outside the checkout, otherwise `git clean -xfd` deletes your
data with the rest of the untracked files. Every stateful bind mount is written as
`${DATA_DIR:-.}/<name>`, so a service's `.env` decides where its data lives without touching
the compose file, and `homelab migrate data --to /srv/homelab --apply` does the move and
verifies it.

---

## Tests

```bash
python3 -m unittest discover -s tests -v
```

53 tests covering env parsing, ordering, dry-run command construction, host filtering,
every doctor check (including the resolver and unset-variable regressions), config
generation, restic/borg command building, the copy chain, and the Pi provisioning
guardrails (a mounted disk, a disk with a filesystem on it, and the root device must all be
refused). It needs no running docker daemon — `docker compose config` is used only to
validate YAML when docker is present.

---

## License

MIT — free to use, adapt, and learn from. Do not commit live credentials.
