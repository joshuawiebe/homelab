# HomeLab

Two machines, one CLI, three copies of everything.

A personal server: a NUC running a Docker Compose stack behind Traefik, a Pi 5 that holds
the backups and the DNS filter, and one `homelab` command that starts, inspects, verifies
and snapshots all of it.

- Every service is a folder under `services/` with a `docker-compose.yml` and an `.env`
  generated from `.env.template`.
- All services share one `proxy` network; TLS terminates at **Traefik** and certificates come
  from an ACME **DNS challenge**, so nothing has to be reachable from the internet to get a
  certificate.
- Backups run on the Pi and **pull** from the NUC. The machine being backed up never learns
  the repository passphrase and cannot delete its own history.
- `homelab doctor` is the part worth having: it checks the things that fail silently - a
  backup that stopped three weeks ago, a dump written outside the snapshot, a `certresolver`
  nobody defined, an `acme.json` Traefik will refuse to start with.

---

## Contents

1. [Architecture](#architecture)
2. [Hardware](#hardware)
3. [Requirements](#requirements)
4. [Install](#install)
5. [Quick start](#quick-start)
6. [Configuration](#configuration)
7. [CLI reference](#cli-reference)
8. [Services](#services)
9. [Networking and TLS](#networking-and-tls)
10. [Choosing an OS](#choosing-an-os)
11. [Backups](#backups)
12. [The Pi](#the-pi)
13. [What `doctor` checks](#what-doctor-checks)
14. [Troubleshooting](#troubleshooting)
15. [Development](#development)
16. [License](#license)

---

## Architecture

```
    internet
       |
   router -- 443 forward (only if you publish; Tailscale otherwise)
       |
  +----+-----------------------------+          +--------------------------+
  | NUC (Proxmox -> one Docker VM)   |          | Pi 5 (always on)         |
  |                                  |          |                          |
  |  traefik   nextcloud  vaultwarden| ssh pull |  restic repo             |
  |  adguard   gotify     watchtower | -------> |  (md + LVM mirror, 2 SSD)|
  |                                  |read-only |                          |
  |  /srv/homelab  <- service data   |          |  adguard  uptime_kuma    |
  +----------------------------------+          |  gotify   tailscale      |
                                                +-----------+--------------+
                                                            | restic copy
                                        +-------------------+--------------+
                                        | second disk on the Pi            |
                                        | offsite: Hetzner Storage Box     |
                                        +----------------------------------+
```

Two rules make the rest of this document make sense:

- **Data lives outside the checkout.** Every stateful bind mount is written
  `${DATA_DIR:-.}/<name>`, so `DATA_DIR=/srv/homelab` puts state on a real filesystem and
  `git clean -xfd` cannot delete it. On the old Pi the checkout *was* the data directory,
  which is why `homelab migrate data` exists.
- **The backup host pulls.** The NUC has no credentials for the backup target and no
  knowledge of the passphrase. Compromise the NUC and the history is still intact.

`docs/PLAN.md` is the long version: hardware decisions, the seven cutover phases, and the
failure modes each phase is designed to survive.

## Hardware

| Box | Role | Notes |
|---|---|---|
| Intel NUC, 16 GB RAM | primary server | Proxmox host; one Docker VM gets a passed-through disk and `/srv` |
| Raspberry Pi 5 + 2 SSDs | backups, DNS, monitoring | md RAID1 + LVM; OS and `/var/lib/docker` on microSD, data on the mirror |
| Hetzner Storage Box | offsite copy | a **sub-account** with its own key, so a stolen Pi key reaches only backups |

The Pi's microSD is treated as disposable: `doctor` fails on state hidden in a named volume
and warns on unbounded container logs, because both wear out or fill an SD card.

## Requirements

* Docker Engine with the Compose v2 plugin
* Python **3.11+** (stdlib only - `tomllib`, no pip packages)
* `openssl` or `htpasswd` when generating the dashboard password
* On the Pi: `mdadm lvm2 rsync restic sqlite3 sshfs fuse3`

## Install

```bash
git clone https://github.com/joshuawiebe/homelab.git
cd homelab

sudo ./install.sh                 # symlink into /usr/local/bin + bash completion
sudo ./install.sh --with-timer    # ... and install the nightly snapshot timer
```

`--prefix DIR` changes the target. Without installing, `./bin/homelab <command>` works
straight from the checkout.

## Quick start

```bash
homelab config        # prompts for domains, email, DNS token; generates secrets
homelab doctor        # preflight: ports, env vars, resolver names, disk, image pins
homelab up            # start everything in dependency order
homelab status        # container state, health, public URL
```

`homelab config` is interactive but not chatty: it shows each template's comment, generates
strong values for anything secret-looking, keeps existing values unless you pass
`--reconfigure`, and writes every `.env` with mode `600`. It also writes
`services/traefik/users` (an htpasswd entry for the dashboard) - the plaintext password is
never stored. For unattended setup: `homelab config --non-interactive`.

## Configuration

Two files, one principle: **nothing secret is in git.**

| File | Contents | In git |
|---|---|---|
| `homelab.toml` | hosts, start order, data_dir, snapshot targets | no (example is committed) |
| `services/<name>/.env` | domains, tokens, generated passwords, image pins | no (templates are) |
| `services/traefik/users` | dashboard htpasswd | no |
| `/etc/homelab/*.password` | restic passphrases, on the Pi only | no |

```bash
cp homelab.toml.example homelab.toml      # then edit
```

`homelab.toml` decides which services run where:

```toml
[general]
proxy = "traefik"            # the only service allowed to publish 80/443
services_dir = "services"
data_dir = "/srv/homelab"
order = ["adguard_home", "nextcloud", "vaultwarden", "watchtower"]

[hosts.nuc]
services = ["traefik", "adguard_home", "nextcloud", "vaultwarden", "watchtower"]

[hosts.pi]
services_dir = "hosts/pi/services"
services = ["adguard_home", "uptime_kuma", "gotify"]
```

`homelab --host nuc up` starts exactly that list and nothing else. The Pi keeps its own file
at `hosts/pi/homelab.toml`, found through `--conf` or `HOMELAB_CONF`.

## CLI reference

| Command | What it does |
|---|---|
| `homelab config [--reconfigure] [--non-interactive]` | create/refresh `.env` files and the dashboard htpasswd |
| `homelab doctor [--json] [--strict]` | preflight checks; exit 1 on a failure (or any warning with `--strict`) |
| `homelab up [SERVICE...] [--proxy NAME] [--wait N]` | start in dependency order, wait for health |
| `homelab down [SERVICE...]` | stop in reverse order |
| `homelab restart [SERVICE...]` | down then up |
| `homelab status [--json]` | table of state, health, image and URL |
| `homelab urls` | print each service's public URL from its `.env` |
| `homelab logs SERVICE [-f] [-n N]` | tail one service |
| `homelab snapshot init` | create each repository and its passphrase, idempotently |
| `homelab snapshot run [--remote HOST] [--no-check]` | pre-hooks, snapshot, retention, verify, notify |
| `homelab snapshot copy [--only NAME]` | replicate to each `[[snapshot.copies]]` target |
| `homelab snapshot list / verify [--full] / stats` | inspect the repository |
| `homelab snapshot extract SNAP DIR [--include PATH]` | put files back |
| `homelab snapshot install / uninstall` | systemd timer for the nightly run |
| `homelab migrate data [--to DIR] [--from HOST:ROOT] [--apply]` | move service state out of the git tree (or straight off another host), verify it, record `DATA_DIR` |
| `homelab provision pi [--apply] [--yes]` | build the mirrored repository on the Pi |
| `homelab install [--prefix DIR]` / `uninstall` | symlink the CLI into `PATH` |

Global flags: `--root DIR`, `--host NAME`, `--conf FILE`, `--verbose`, `--version`.
`--dry-run` (where accepted) prints the exact `docker`/`restic`/`rsync` commands without
running them - it is also what the test suite asserts against, so the printed commands are
the ones that actually run.

## Services

| Service | Role |
|---|---|
| `traefik` | reverse proxy, ACME DNS challenge, security headers, rate limit |
| `nextcloud` + `db` + `redis` + `cron` | personal cloud storage |
| `vaultwarden` | Bitwarden-compatible password manager |
| `adguard_home` | network-wide DNS filtering (also runs on the Pi) |
| `gotify` | push notifications (also on the Pi) |
| `uptime_kuma` | uptime monitoring (also on the Pi) |
| `watchtower` | image updates - **opt-in per container** |

Only one service may publish 80/443. `homelab up` refuses to start a second one unless you
pass `--allow-port-conflict`, and `[general] proxy` names the one that owns the ports.

Image versions are pinned through env vars, so pinning never means editing a compose file:

```bash
# services/nextcloud/.env
NEXTCLOUD_IMAGE=nextcloud:32-apache
MARIADB_IMAGE=mariadb:11.4
```

Watchtower runs with `--label-enable --interval 86400`: it only touches containers labelled
`com.centurylinklabs.watchtower.enable=true`, once a day. Nothing upgrades behind your back.

**Adding a service** is three files: `services/<name>/docker-compose.yml`,
`services/<name>/.env.template`, and a line in `homelab.toml`. The CLI discovers services by
directory, so there is no registry to update. Join the `proxy` network, add the usual three
labels (`traefik.enable`, `...routers.<name>.rule`, `...tls.certresolver`) and it is routed
with a certificate.

## Networking and TLS

Traefik publishes 80/443, terminates TLS, and redirects HTTP to HTTPS. Every routed service
gets `security-headers@docker` and `ratelimit@docker` (50 rps average, 100 burst).

Certificates come from a **DNS-01 challenge** through the `ipv64` provider:

```bash
# services/traefik/.env
BASE_DOMAIN=example.ipv64.net
EMAIL=you@example.com
IPV64_API_KEY=...
```

Traefik's ACME client is lego, which has had a native `ipv64` provider since v4.13 (provider
code `ipv64`, env `IPV64_API_KEY`), so any Traefik v3 image can do this. The practical
consequences:

- **No inbound port is needed for a certificate.** Port 80 is only for the HTTP redirect.
- **Wildcards work**, which HTTP-01 cannot do.
- Your DynDNS record points at your WAN address, not at a machine. Both boxes sit behind the
  same router, so moving the stack from the Pi to the NUC moves a **port forward**, not a DNS
  record, and the updater can stay where it is.

`services/traefik/letsencrypt/acme.json` holds the private keys. Traefik **refuses to start**
unless that file is mode `600` - `doctor` checks it, because a `cp` during a cutover lands it
at 644 and the resulting error message does not mention ACME at all.

If you do not need to publish anything, put the stack behind Tailscale
(`hosts/pi/services/tailscale/`) and skip the port forwards entirely. `doctor` works either
way.

## Choosing an OS

**The NUC's Docker VM: Debian 13 (trixie), minimal, no desktop.**

- Same base as Proxmox itself, so the guest and host tooling stay familiar, and the `virtio`
  drivers are in the stock kernel.
- The netinst ISO with only "SSH server" and "standard system utilities" gives you a small
  system with no GUI, no snapd, and no surprises.
- Docker from Docker's own apt repository (`docker-ce`, `docker-compose-plugin`), not
  Debian's older `docker.io`.
- 4 vCPU / 8 GB is plenty for this stack. Pass the whole 1 TB disk through as a raw disk
  instead of a qcow2 file: `DATA_DIR` writes then hit the real device, and the Pi's pull
  reads a real filesystem rather than an image.
- Add `qemu-guest-agent` so Proxmox can report the IP and freeze the filesystem for
  host-level snapshots.
- Ubuntu Server 24.04 LTS is a fine alternative if you want the longer support window. Avoid
  the desktop images on a server.

**The Pi 5: Raspberry Pi OS Lite (64-bit), the current release.**

- It is the only distribution that ships the Pi's own bootloader and firmware tooling
  (`rpi-eeprom`, `vcgencmd`) and the kernel with the right SD and USB quirks. On a box whose
  job is `mdadm` + `sshfs` + `restic`, boring and supported wins.
- Take the **64-bit** image. A 32-bit userland caps one process at 4 GB of address space,
  which is exactly what `restic prune` runs into on a large repository.
- Flash with Raspberry Pi Imager and set the hostname, SSH key and locale before first boot.
- Plain Debian arm64 also works, but you lose the firmware tooling and end up adding the
  Raspberry Pi archive by hand for kernel updates.

Both machines: `noatime` on the data filesystems, `journald` capped (`SystemMaxUse=200M`),
and swap off or on zram. The microSD in the Pi is the part that fails first, and every write
you remove from it buys time.

## Backups

`homelab snapshot` wraps **restic** (default) or **borg**, configured under `[snapshot]` in
`homelab.toml`.

### What gets backed up

`source` is one path **or a list**. The Pi uses a list, because it holds two things worth
keeping:

```toml
# hosts/pi/homelab.toml
source = ["/srv/mnt/nuc/srv/homelab", "/srv/homelab"]
```

- `/srv/mnt/nuc/srv/homelab` - the NUC's data, over a read-only sshfs mount
- `/srv/homelab` - the Pi's own AdGuard, Kuma and Gotify state

Without the second entry the Pi would back up everything except itself.

### Database dumps

Copying a live database gives you a corrupt restore months later, so `[snapshot] pre` runs
dump commands first and the stack stays online:

```toml
pre = [
  "mkdir -p /srv/homelab/dumps && docker exec db sh -c 'exec mysqldump --single-transaction --quick --all-databases' > /srv/homelab/dumps/nextcloud.sql",
  "mkdir -p /srv/homelab/dumps && sqlite3 /srv/homelab/vw-data/db.sqlite3 '.backup /srv/homelab/dumps/vaultwarden.sqlite'",
]
```

**Dumps must land inside `data_dir`.** A dump written to `/srv/dumps` sits next to the
snapshot instead of inside it and is never backed up - the backup succeeds, the file is
simply not in it. `doctor` warns about exactly this.

`pre` hooks run on the machine that owns the data: over ssh with `--remote user@host`,
locally without it. Hooks that must run *here* even when `--remote` is used go in
`pre_local` - that is how the Pi dumps Kuma and Gotify while the NUC's MariaDB is dumped over
ssh.

### Run it

```bash
# on the NUC, manually
homelab snapshot run

# the real job: on the Pi, pulling from the NUC
homelab --conf hosts/pi/homelab.toml snapshot run --remote backup@homelab.lan
```

Retention defaults: `keep-daily 7`, `keep-weekly 4`, `keep-monthly 6`, then
`check --read-data-subset=5%`. Set `[snapshot] healthcheck_url` to a dead-man's-switch URL: a
snapshot that silently stopped three weeks ago is the most common homelab failure and the
hardest to notice. `gotify_url`/`gotify_token` add a push notification.

### Copies

`[[snapshot.copies]]` adds replicas. `homelab snapshot copy` runs `restic copy --repo2` per
target and prunes it on its own retention, so a replica can be longer-lived than the primary:

```toml
[[snapshot.copies]]
name = "cold"                                  # second disk on the Pi
repo = "/srv/cold/restic"
password_file = "/etc/homelab/restic-cold.password"
keep_daily = 14

[[snapshot.copies]]
name = "offsite"                               # Hetzner Storage Box
repo = "sftp:u123456-sub1@u123456-sub1.your-storagebox.de:23//restic"
password_file = "/etc/homelab/restic-offsite.password"
limit_upload = 30000                           # KiB/s, keeps your uplink usable
```

`copy = true` under `[snapshot]` runs the copies at the end of every `snapshot run`.

Creating the repositories is one command - it generates a passphrase per repository (mode
600) and initialises only what is not initialised yet, so it is safe to re-run:

```bash
sudo homelab --conf hosts/pi/homelab.toml snapshot init
```

Put every passphrase in your password manager immediately. A repository without its
passphrase is a random binary blob, and nobody - including you - can open it.

For the Storage Box: use a **sub-account** (own username, own home, own keys, so a stolen Pi
key reaches only backups), add the Pi's public key to it, and remember that SFTP is on port
**23** and the double slash in the URL means an absolute path.

### Prove it works

```bash
homelab snapshot list
homelab snapshot extract latest /tmp/restore-check --include 'vaultwarden.sqlite'
sqlite3 /tmp/restore-check/srv/homelab/dumps/vaultwarden.sqlite '.tables'
```

Do this every few months. An untested backup is a hypothesis.

### What is *not* backed up

- **Docker images and `/var/lib/docker`** - rebuildable from the compose files.
- **The OS.** Reinstall and run `homelab up`.
- **The checkout itself** - it is in git.
- **`services/*/.env`** - they live in the checkout, which is usually not a snapshot source.
  Either add the checkout to `source`, or keep the files in your password manager. `doctor`
  warns about this ("secret coverage") because losing them means losing every database
  password and app secret at once.

## The Pi

The Pi has its own config and its own service set:

```bash
sudo ln -s /opt/homelab/hosts/pi/homelab.toml /etc/homelab/homelab.toml
export HOMELAB_CONF=/etc/homelab/homelab.toml

homelab provision pi            # prints the plan, touches nothing
homelab provision pi --apply    # asks you to type 'yes'
homelab doctor
homelab up
```

`homelab config` lists the candidate disks on this host (whole disks, not partitions, not the
root disk, not anything mounted) and writes the two you pick into `[provision.pi] devices`, so
the committed config stays generic and the same repo works on your Pi and anyone else's.

`provision pi` then builds the md RAID1 mirror, LVM volume, filesystem, label and fstab entry
from those devices. It refuses to continue if a device is missing, mounted, still holds
a filesystem signature, or is the root device, and it never wipes anything: if a disk is
dirty it tells you to run `wipefs -a` yourself. That is deliberate - the one thing a
provisioning tool must not do is guess.

**Warning:** this wipes the disks. Until a `snapshot extract` has put a file back on the NUC,
the Pi's SSD may be your only copy.

The nightly timer is installed on the Pi only:

```bash
sudo homelab --conf hosts/pi/homelab.toml snapshot install
systemctl list-timers 'homelab-*'
```

The unit pins the config path it was installed with, because systemd does not inherit
`HOMELAB_CONF` - without that, the timer would run with an empty config and fail before it
could send the dead-man's-switch ping.

## What `doctor` checks

Ordered roughly from "will not boot" to "smells":

* docker binary, daemon reachable, Compose v2
* the `proxy` network exists
* per service: `.env` present, mode `600`, no leftover `(put your ...)` placeholders, every
  template key present, and **every `${VAR}` the compose file references defined** - this
  catches a renamed variable before you debug a silent failure
* ACME resolver: every `tls.certresolver=X` label points at a resolver the proxy defines
* `acme.json` exists and is mode `600` (Traefik refuses to start otherwise)
* dashboard htpasswd exists and is `600`
* host ports 80/443/53 free (`systemd-resolved` holds 53)
* image tags: `:latest` and untagged images are flagged
* `docker.sock` mounted read-write (root-equivalent)
* state hidden in a named volume (on the Pi that means the microSD)
* unbounded `json-file` logs (they fill the disk and wear out an SD card)
* container state living inside the git tree
* free space on `data_dir` and the snapshot repo
* snapshot repo mounted, newest snapshot younger than 36 hours, every copy target fresh
* snapshot hooks: a dump that writes outside `data_dir` and every source
* secret coverage: `.env` files that no snapshot covers
* provision devices: chosen, present, and not a `CHANGE-ME` placeholder

Exit code is 1 on any `FAIL`, so it is safe to run from cron or a deploy script.

## Troubleshooting

**`homelab up` fails: port 53 in use.** `systemd-resolved` binds it. Disable its stub
listener (`DNSStubListener=no` in `/etc/systemd/resolved.conf`), or run AdGuard on another
host - it runs on the Pi for exactly this reason.

**Traefik exits immediately, log mentions `acme.json` permissions.** `chmod 600
services/traefik/letsencrypt/acme.json`. Traefik refuses to start with anything else.

**Certificate requests fail with "too many certificates already issued".** Let's Encrypt
allows five duplicate certificates per week. Copy `letsencrypt/acme.json` between machines
instead of re-issuing, and use the staging CA while you experiment.

**A service starts but has no route.** Check `homelab doctor` for the resolver check, then
`docker logs traefik`. The usual cause is a label pointing at a `certresolver` that does not
exist, or a container not on the `proxy` network.

**The nightly backup silently stopped.** That is what `healthcheck_url` is for. Then:
`systemctl list-timers 'homelab-*'`, `journalctl -u homelab-snapshot -n 50`, and
`homelab snapshot list` - if the newest snapshot is old, `doctor` will say so.

**`git clean -xfd` deleted my data.** It deleted state that was in the tree because
`DATA_DIR` was unset. `homelab migrate data --to /srv/homelab --apply` moves state out and
verifies the copy; do it before you clean.

**Restore succeeded but the app will not start.** The data came back, the `.env` did not (see
"What is *not* backed up"). Restore the env files, or re-run `homelab config --reconfigure`
and fix the credentials inside the app.

## Development

```bash
python3 -m unittest discover -s tests -v
```

93 tests: env parsing, ordering, dry-run command construction, host filtering, every doctor
check (including the resolver, unset-variable, hook-target and secret-coverage regressions),
config generation, restic/borg command building, the copy chain, snapshot init, disk
discovery (root disk, mounted disks and partitions are never offered), and the Pi
provisioning guardrails. No docker daemon needed - `docker compose config` is used only to
validate YAML when docker is present.

Layout:

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
│   ├── homelab.toml
│   └── services/<name>/docker-compose.yml
├── tests/test_homelab.py
└── .automations/                # deprecated shims that exec the CLI
```

Versioning is by git tag (`v1.0.0`); `homelab --version` prints the same number.

## License

MIT - free to use, adapt, and learn from. Do not commit live credentials.
