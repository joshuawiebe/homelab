# Plan: two hosts, one stack, three copies

The goal is a server you can leave alone. Everything below serves that: the NUC does the
work, the Pi keeps the lights on and holds the backups, and this repo is the only thing you
edit.

```
   internet --> :443                 +--------------------------+
                                     |  NUC (Proxmox 8)         |
                                     |   + VM 100: docker       |
                                     |      traefik, nextcloud  |
                                     |      vaultwarden, adguard|
                                     |   /dev/sdb --> /srv      |
                                     +--------------------------+
                                                  ^  ssh, read-only
                                     +--------------------------+
                                     |  Pi 5 (always on)        |
                                     |   adguard (primary DNS)  |
                                     |   uptime-kuma, gotify    |
                                     |   /srv/repo  = md mirror |
                                     |   /srv/cold  = HDD       |
                                     +--------------------------+
                                                  |
                                                  | restic copy
                                                  v
                                     Hetzner Storage Box
```

## 1. What each box is for

| Box | Job | Never does |
|---|---|---|
| NUC | serves nextcloud, vaultwarden, the proxy | hold the only copy of anything |
| Pi 5 | DNS, alerting, snapshots, offsite uplink | serve user data over the internet |
| Storage Box | third copy, offsite | anything interactive |

The split exists so that **the machine being backed up does not hold the passphrase and has
no write access to the repository**. A compromised NUC cannot delete its own history.

## 2. Hardware

### NUC

| Part | Use |
|---|---|
| NVMe, 256 GB or more | Proxmox boot, VM disks, LVM-thin |
| 1 TB SATA SSD | `/srv` inside the VM, passed through |
| 16 GB RAM | about 8 GB to the VM, the rest for Proxmox and page cache |

The 1 TB disk is passed through to the VM as a whole disk, not as a directory on
`local-lvm`. That keeps the data out of the Proxmox backup story and lets you move the VM
without copying a terabyte.

### Pi 5

| Part | Use |
|---|---|
| microSD | boot only, see the warning below |
| 2 x SSD, same size | `mdadm` mirror -> LVM -> `/srv/repo` |
| 1 x HDD | `/srv/cold`, an independent second repository |
| USB-SATA bridges | fine for the HDD, not for the mirror |

> **The microSD is the weakest part of this plan.** It wears out, and a dead card means the
> box is down until you reflash. Either boot from a small USB SSD or keep a written-down,
> tested image of the card.

> **Do not span the two SSDs with LVM alone.** One USB bridge dropping out of a concatenated
> volume leaves the whole volume unusable. `mdadm` RAID 1 first, LVM on top.

## 3. Network

| Name | Address | Notes |
|---|---|---|
| `nuc.lan` | DHCP reservation | Proxmox host |
| `homelab.lan` | VM 100 | the stack |
| `pi.lan` | DHCP reservation | DNS and snapshots |

* The router hands out **`pi.lan` as primary DNS and `homelab.lan` as secondary**, so DNS
  keeps working while either box reboots. AdGuard on the NUC keeps its own copy of the
  blocklists so it can answer alone.
* Ports 80 and 443 are forwarded to the VM only if you decide to publish. **Tailscale is the
  better answer**: `hosts/pi/services/tailscale/` exists for that, and advertising the LAN
  route gives you everything without opening a port.
* The DNS-01 challenge keeps working as long as the `ipv64` token stays in
  `services/traefik/.env`. It never needs to leave the NUC.

## 4. Who holds which secret

| Secret | Lives on | Readable by |
|---|---|---|
| `services/*/.env` (app passwords) | NUC | root |
| `services/traefik/users` (dashboard htpasswd) | NUC | root, traefik |
| `restic.password` (repository key) | Pi | root |
| `restic-cold.password` | Pi | root |
| `restic-offsite.password` | Pi | root |
| Storage Box SFTP key | Pi | root |

The NUC never sees the restic passphrase, so `homelab snapshot run` on the NUC is only for
local testing. The timer runs on the Pi.

Keep one copy of all three passphrases somewhere that is not these machines: paper, or your
password manager. A restic repository without its passphrase is a random binary blob.

## 5. Phases

Each phase ends in something you can use. Do not skip ahead.

### Phase 0 - cut over from the Pi (an afternoon)

Your layout today: **the repo and every service's data are on the SSD**, the OS and
`/var/lib/docker` are on the microSD. Two consequences, both easy to get wrong:

* the checkout *is* the data, so `git clean -xfd` on the Pi deletes Nextcloud. Never run it
  there.
* nothing needs to be copied within the Pi, and copying into `/srv` on the same disk would
  double the space used. Copy **straight from the Pi to the NUC**.

1. **Freeze the old stack.** On the Pi: `homelab down`. No writes after this point.
2. **On the NUC**, clone this repo, then pull the state over ssh in one verified step:

   ```bash
   sudo homelab migrate data --from pi.lan:/opt/homelab --to /srv/homelab --apply
   ```

   `--from` reads the compose files *here*, maps each bind mount to the same relative path
   under the Pi's checkout, copies with `rsync` (never deletes), verifies every copy with a
   dry-run itemize diff, and records `DATA_DIR` here. Nothing on the Pi is written to, so it
   stays a working fallback.

   Replace `/opt/homelab` with wherever the Pi keeps its checkout (`pwd` on the Pi).
3. **Carry the secrets.** They are gitignored, so a fresh clone does not have them:

   ```bash
   rsync -a --numeric-ids --include='*/' --include='.env' --include='users' --exclude='*' \
     pi.lan:/opt/homelab/services/ ./services/
   ```

   Do this **before** `homelab config`. If `config` generates fresh secrets, the Nextcloud
   database and its `MYSQL_PASSWORD` no longer match and the app refuses to start. Add
   `--include='letsencrypt'` if you also want the existing certificates; otherwise Let's
   Encrypt re-issues them, which is fine once.
4. **Start the NUC stack** (`homelab config`, `homelab doctor`, `homelab up`) and check the
   three things that always break: Nextcloud login, Vaultwarden login, AdGuard answering on
   53. `doctor` must say `data location: OK` and `named volumes: OK` - the second one means
   no state is hiding in `/var/lib/docker` (which on the Pi is the microSD).
5. **Move DNS and the port forwards** to the NUC. Keep the Pi's AdGuard answering until the
   NUC does.
6. **Do not wipe anything for a week.** The Pi's in-tree data and the USB stick are your only
   copy until the new chain has produced and verified one.

Only after that does the Pi get repurposed as the backup box (phases 3 to 5). Its microSD
then holds an OS and a few container images, so cap the container logs (the compose files in
`hosts/pi/services/` already do) or the card writes itself to death.

### Phase 1 - NUC: Proxmox (half a day)

1. Install Proxmox 8 from USB. Hostname `nuc`, static address or DHCP reservation.
2. Post-install, as root. The community-scripts helper is convenient; read it first, then
   do the two things it does that matter:

   ```bash
   # disable the enterprise repo (it needs a subscription you do not have)
   sed -i 's/^deb .*enterprise.*$/# &/' /etc/apt/sources.list.d/pve-enterprise.list
   apt update && apt full-upgrade -y
   ```

3. Create the VM:

   ```bash
   qm create 100 --name homelab --memory 8192 --cores 4 \
     --scsihw virtio-scsi-pci --ostype l26 --agent enabled=1 --onboot 1 \
     --net0 virtio,bridge=vmbr0 --scsi0 local-lvm:64 \
     --ide2 local:iso/<the-debian-12-netinst-iso-you-uploaded>
   ```

   Pass the 1 TB disk through by id, never by `/dev/sdb`:

   ```bash
   qm set 100 --scsi1 /dev/disk/by-id/<your-1tb-ssd>,backup=0
   ```

   `backup=0` matters: that disk is snapshotted by restic, not by Proxmox.

4. Install Debian 12 in the VM, then inside it:

   ```bash
   apt install -y docker.io docker-compose-plugin sqlite3 rsync openssh-server
   usermod -aG docker <you>
   ```

5. Clone this repo to `/opt/homelab`, then:

   ```bash
   cp homelab.toml.example homelab.toml
   sudo ./install.sh
   homelab config          # prompts for domains, email, DNS token; generates secrets
   homelab doctor
   homelab up
   ```

### Phase 2 - NUC: data where it belongs (an hour)

1. Format and mount the passthrough disk:

   ```bash
   mkfs.ext4 -m 1 -L homelab /dev/sdb
   mkdir -p /srv && mount /dev/sdb /srv
   echo "UUID=$(blkid -o value -s UUID /dev/sdb) /srv ext4 defaults,noatime 0 2" >> /etc/fstab
   ```

2. `mkdir -p /srv/homelab /srv/dumps && chown 1000:1000 /srv/homelab`.
3. Move the bind-mount sources there. Every service already reads `${DATA_DIR}`, so set
   `DATA_DIR=/srv/homelab` in `services/*/.env` and re-run `homelab up`.
4. `homelab doctor` must say `data location: OK`. If it warns, something is still writing
   inside the git tree, and `git clean -xfd` would eat it.

### Phase 3 - Pi: storage (an hour, once)

```bash
sudo apt install -y mdadm lvm2 rsync restic sqlite3
ls -l /dev/disk/by-id/          # note the two SSDs
```

Edit `[provision.pi] devices` in `hosts/pi/homelab.toml`, then read the plan before you run
it:

```bash
homelab --conf hosts/pi/homelab.toml provision pi            # prints, touches nothing
homelab --conf hosts/pi/homelab.toml provision pi --apply    # asks you to type 'yes'
```

The tool refuses to continue if a device is missing, mounted, still holds a filesystem
signature, or is the root device. It never wipes anything: if a disk is dirty it tells you to
run `wipefs -a` yourself. That is deliberate, because the one thing a provisioning tool must
not do is guess.

Then:

```bash
homelab --conf hosts/pi/homelab.toml doctor
```

### Phase 4 - Pi: services (half a day)

```bash
homelab --conf hosts/pi/homelab.toml up        # adguard, uptime-kuma, gotify
homelab --conf hosts/pi/homelab.toml status
```

1. `http://pi.lan:3000` - finish AdGuard's wizard: listen on 53, pick upstreams. Then point
   the router's DHCP DNS at `pi.lan` and `homelab.lan`.
2. `http://pi.lan:3001` - Uptime Kuma. Monitor `homelab.lan:443`, `pi.lan:53` (TCP monitor),
   the Storage Box, and **the snapshot age** through the `healthcheck_url` push.
3. `http://pi.lan:8080` - Gotify. Create an app token, put it in `hosts/pi/homelab.toml` as
   `gotify_token`.
4. Optional: `docker compose --profile vpn up -d` for Tailscale, then approve the advertised
   route in the admin console.

### Phase 5 - Pi: pull and snapshot (half a day)

The Pi pulls; the NUC never pushes.

```bash
# on the NUC: an account for the Pi to read from
useradd -m -d /home/backup -s /bin/bash backup
mkdir -p /home/backup/.ssh && chown -R backup: /home/backup/.ssh

# on the Pi
ssh-keygen -t ed25519 -f /root/.ssh/id_ed25519_backup -N ""
ssh-copy-id -i /root/.ssh/id_ed25519_backup backup@homelab.lan

# on the NUC: no shell needed once the key is in place
usermod -s /usr/sbin/nologin backup
```

Then lock that key down on the NUC. sshfs only needs the sftp subsystem, so give it exactly
that and nothing else:

```
# /home/backup/.ssh/authorized_keys
restrict,command="internal-sftp" ssh-ed25519 AAAA...
```

Mount the data on the Pi with systemd, read-only and reconnecting:

```ini
# /etc/systemd/system/srv-mnt-nuc-srv.mount
[Unit]
Description=read-only staging mount of the NUC data

[Mount]
What=backup@homelab.lan:/srv
Where=/srv/mnt/nuc/srv
Type=fuse.sshfs
Options=idmap=backup,ro,reconnect,_netdev,ServerAliveInterval=15,ConnectTimeOut=10

[Install]
WantedBy=remote-fs.target
```

```bash
systemctl enable --now srv-mnt-nuc-srv.mount
```

Read-only with `reconnect` matters: if the NUC reboots, the mount comes back by itself
instead of going silently stale, and nothing on the Pi can damage the source.

Then run it by hand once:

```bash
homelab --conf hosts/pi/homelab.toml snapshot run --remote backup@homelab.lan
```

`--remote` runs the `pre` dump hooks on the NUC over ssh, then snapshots the staging mount.
Databases are dumped, not copied live. The first run takes a while; later ones are
incremental.

Finally the timer, on the Pi only:

```bash
sudo homelab --conf hosts/pi/homelab.toml snapshot install
systemctl list-timers 'homelab-*'
```

### Phase 6 - three copies (an hour, then a night)

```bash
# on the Pi, once per repository
restic init --repo /srv/cold/restic --password-file /etc/homelab/restic-cold.password
restic init --repo sftp:u123456@u123456.your-storagebox.de:23//restic \
  --password-file /etc/homelab/restic-offsite.password
```

The Storage Box speaks SFTP on **port 23**, not 22, and restic's URL carries it as `:23`.

`homelab snapshot copy` then runs, per target:

```bash
restic -r /srv/repo/restic copy --repo2 <target> --password-file2 <target.pw>
restic -r <target> forget --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
```

`copy = true` under `[snapshot]` runs this after every night's snapshot. The offsite target
carries `limit_upload = 30000` (KiB/s) so a snapshot does not saturate your uplink. Use a
different passphrase per repository.

### Phase 7 - prove it (an hour, every quarter)

```bash
homelab snapshot list
homelab snapshot verify
homelab snapshot extract latest /tmp/restore-check --include 'vaultwarden.sqlite'
sqlite3 /tmp/restore-check/vaultwarden.sqlite 'select count(*) from ciphers;'
```

If that last command fails, you do not have backups, you have a cron job. Put it in the
calendar.

## 6. Failure modes

| What breaks | What happens | What you do |
|---|---|---|
| Pi is down | no DNS, no snapshots, alerting silent | fix the Pi; add a public resolver as a second upstream so DNS degrades instead of stopping |
| NUC is down | sites gone, DNS still answers | snapshots keep running; the staging mount fails and the dead-man's-switch fires |
| A mirror disk dies | `mdadm` degrades, repo still mounted | replace the disk, `mdadm --add`, wait for the resync |
| Repository corrupted | `restic check` fails | `restic check --read-data`, then restore from `cold` |
| microSD dies | Pi is gone | reflash, re-clone, re-mount the mirror; the repository is on the SSDs |
| Ransomware on the NUC | cannot reach the repository | it never had the passphrase; restore from the Pi |
| Wrong `--prune` | snapshots gone from the primary | `cold` is a separate disk with longer retention |

## 7. Open questions

* **Do you publish this to the internet?** Every forwarded port is a liability. My
  suggestion: Tailscale only, no port forwarding, and treat certificates as a convenience
  for LAN clients.
* **How much data?** It decides whether a Storage Box BX11 (1 TB) is enough or you need
  BX21. Under 500 GB, BX11 with the retention above fits comfortably.
* **What happens to the USB stick?** Retire it once the three-copy chain has been verified
  once. It was a single, unversioned copy on flash, which is exactly the failure this design
  removes, but until the new chain works it is still the only copy.
* **Do you want a second DNS on the NUC?** `adguard_home` stays in `[hosts.nuc]` for exactly
  that, but it doubles the blocklist maintenance. The alternative is `dnsmasq` on the NUC
  pointing at the Pi.
