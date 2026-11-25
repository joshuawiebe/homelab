# Changelog

All notable changes to this repository. Versions match `homelab --version` and the git tag.

## [1.0.0] - 2026-11-25

First tagged release. The `homelab` CLI replaces the `.automations/*.sh` scripts and the
`auto_backup/` borg scripts, which are removed.

### Added

- `homelab` CLI (single file, Python stdlib only): `config`, `doctor`, `up`, `down`,
  `restart`, `status`, `urls`, `logs`, `snapshot`, `migrate`, `provision`, `install`,
  `uninstall`, with `--root`, `--host`, `--conf`, `--verbose`, `--dry-run` and `--version`.
- `homelab doctor`: preflight from "will not boot" to "smells", exit 1 on failure. Covers
  undefined `${VAR}` references, `certresolver` labels pointing nowhere, `acme.json`
  permissions, named-volume state, unbounded container logs, floating image tags, port
  conflicts, disk space, snapshot freshness and copy freshness.
- `homelab snapshot`: restic (default) or borg, with `init`, `run`, `list`, `verify`,
  `stats`, `copy`, `extract` and a systemd timer via `install`/`uninstall`.
- Pull-model backups: the backup host reads the server over ssh and holds the passphrase;
  the server never learns it. `--remote HOST` runs database dump hooks on the source host.
- `homelab migrate data`: move service state out of the git tree, verify the copy, record
  `DATA_DIR`. `--from HOST:ROOT` pulls an existing host's state straight over ssh.
- `homelab provision pi`: md RAID1 + LVM + filesystem + fstab on the Pi, with guardrails
  against mounted disks, foreign filesystem signatures and the root device.
- Two-host layout: `services/` for the NUC, `hosts/pi/services/` for the Pi, each with its
  own `homelab.toml`.
- Bash completion and `install.sh` (`--prefix`, `--with-timer`).

### Changed

- Stateful bind mounts use `${DATA_DIR:-.}/<name>`, so data can live outside the checkout
  without editing compose files.
- Every container caps its `json-file` logs (`x-logging` anchor), because unbounded logs
  fill a disk and wear out an SD card.
- `snapshot run` accepts one source or a list, so one snapshot can cover the NUC's data and
  the backup host's own services.
- `pre_local` hooks run on the local machine even with `--remote`, for data that never
  leaves the backup host.

### Fixed

- TLS never worked: the proxy's `certresolver` name did not match any configured resolver,
  and the ACME email placeholder was not interpolated. Certificates now come from a DNS-01
  challenge through the `ipv64` provider (`IPV64_API_KEY`, native in lego >= 4.13).
- Database dumps were written to `/srv/dumps`, outside `data_dir` and therefore outside the
  snapshot: the backup succeeded and the dump was never in it. Hooks now write into
  `data_dir`, and `doctor` warns about any hook that writes outside the snapshot.
- The installed snapshot timer ran without `--conf`. On a host whose config is not
  `<root>/homelab.toml` it loaded an empty config, failed, and never sent the dead-man's
  switch ping. The unit now pins the absolute config path.
- Vaultwarden's data path in the example config was wrong (`vaultwarden/vw-data` instead of
  `vw-data`), so the sqlite dump silently dumped nothing.
- `snapshot install --dry-run` wrote to `/etc/systemd/system`; it now prints the units.

### Security

- Secrets stay in gitignored `.env` files (mode 600) and `/etc/homelab/*.password`; only
  templates are committed. The dashboard uses an htpasswd file, not `${USER}:${PASS}` labels,
  because bcrypt hashes contain `$` and Compose would interpolate them.
- The offsite copy is meant to be a Storage Box **sub-account** with its own key, so a
  compromised backup host cannot reach anything but backups.
- `doctor` warns when `.env` files are not covered by any snapshot source ("secret
  coverage"), since losing them means losing every database password at once.
