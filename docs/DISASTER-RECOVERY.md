# Disaster Recovery Playbook — Full Rebuild from Scratch

Written 2026-09-08, grounded in the actual `proxmox-config/` sync in this
repo (Proxmox VE config auto-synced from the Omen host) plus known backup
infrastructure. This assumes the worst case: the Omen hardware itself is
gone and everything has to be rebuilt from bare metal plus backups.

**What this can't cover from this repo alone:** anything living on
Powerstation (the separate Hyper-V host running Vault and Wazuh per
ADR 002) isn't captured in `proxmox-config/` — that sync only covers the
Omen Proxmox node. If Powerstation is also lost, its rebuild isn't
documented here and needs its own playbook.

---

## 1. Proxmox host provisioning (Omen)

From `proxmox-config/`, the current Omen node runs:

| VM/LXC ID | Name | Type | Specs | Static IP |
|---|---|---|---|---|
| 100 | docker-host | QEMU VM | 4 cores, 8GB RAM, 120GB disk, Ubuntu 26.04 | DHCP via vmbr0 |
| 301 | k3s-control-plane | QEMU VM | 2 cores, 4GB RAM, 32GB disk, Ubuntu 26.04 | DHCP via vmbr0 |
| 210 | futbol-db | LXC (Debian, unprivileged) | 2 cores, 4GB RAM, 32GB rootfs | 192.168.4.210/22, gw 192.168.4.1 |

Storage config (`proxmox-config/storage.cfg`): a `local` dir store at
`/var/lib/vz` (templates/backups/ISOs) plus an LVM-thin pool `local-lvm`
(vgname `pve`) for VM/container disks. Both VMs' disks and the LXC's
rootfs live on `local-lvm`.

**Rebuild steps:**
1. Install Proxmox VE fresh on the Omen hardware. Keyboard layout is
   `en-us` (from `datacenter.cfg`) — trivial, but it's the one setting
   actually captured, so worth matching.
2. Recreate the `local-lvm` thin pool on the same physical disk layout
   (120G + 32G + 32G minimum, plus headroom — the host had ~47% usage
   after the 2026-08-31 LVM extension, so size generously above the raw
   VM disk totals).
3. Recreate VM 100 (`docker-host`) and VM 301 (`k3s-control-plane`) with
   the exact core/memory/disk specs above, `onboot: 1` on both so they
   come up automatically after a host reboot, network on `vmbr0`.
4. Recreate LXC 210 (`futbol-db`) as an unprivileged Debian container with
   the static IP baked in (`192.168.4.210/22`, gw `192.168.4.1`) — several
   other services reference this IP directly (noted in memory as the
   Postgres host), so it has to land on the same address, not just "some
   address on the subnet."
5. Re-attach or restore the Proxmox Backup Server VM (192.168.4.82:8007,
   the 1.7TB dedup datastore) — if the datastore itself survived the
   failure (e.g. it was on separate/removable storage), reconnect it as a
   storage target in the new Proxmox install rather than recreating it
   empty. If the datastore itself was lost, this playbook is moot for
   `docker-host` and `k3s-control-plane` — full rebuild would fall back to
   step 2 below (rebuilding docker-host from this git repo instead of
   restoring its backup image).

## 2. docker-host VM: restore or rebuild

Two paths, in order of preference:

**A. Restore from Proxmox Backup Server (preferred, if PBS survived):**
Restore VM 100 from its most recent PBS backup. This brings back the VM
disk exactly as it was, including any local state not tracked in this git
repo (e.g. Docker's internal image cache, anything outside the bind-mounted
volume paths).

**B. Rebuild from scratch (if PBS backups didn't survive):**
1. Provision a fresh Ubuntu 26.04 VM matching the VM 100 spec above.
2. Install Docker + Docker Compose.
3. `git clone` this repo (`Bernal-labs-infra`) onto the new VM.
4. Restore each service's data directory from whatever backup source
   covers it (see the per-service "Data lives in" paths in
   `docs/RUNBOOKS.md` — `gitea/data/`, `vaultwarden/data/`,
   `authelia/config/` + `authelia/secrets/`, `wireguard/config/`, etc.)
   into the same relative paths, **before** the first `docker compose up`
   for each — several services (Vaultwarden especially) will silently
   initialize an empty state if they start against an empty volume, so
   restoring data late means starting over.
5. `authelia/secrets/` specifically is gitignored — it will NOT come back
   from `git clone` alone. It has to come from a real file-level backup.
   Losing this without a backup means the Authelia storage encryption key
   is gone and its storage backend (user 2FA registrations etc.) is
   unrecoverable — see `docs/RUNBOOKS.md`'s Authelia section.
6. `woodpecker/.env` is also gitignored (real secrets) — restore from
   backup or regenerate the agent secret and re-register the Gitea OAuth
   app if no backup exists.

## 3. Service startup order

Order matters here because several services depend on DNS or a shared
Docker network being up first:

1. **Pi-hole + Unbound** — DNS for the whole environment (Pi-hole at
   `10.13.13.1` per known network config). Several compose files
   (`gitea`, `wireguard`) hard-code `dns: 192.168.4.2` — if that resolver
   isn't up yet, those containers can still start but internal-hostname
   DNS lookups inside them will fail until it is.
2. **Monitoring stack** (`monitoring/docker-compose.yml`: Prometheus +
   Grafana + node-exporter + cadvisor) and **Alertmanager** — start these
   together; Alertmanager depends on the `monitoring_default` external
   network (added in the 2026-09-08 hardening pass), so bring the
   monitoring stack's `docker compose up -d` up first, then alertmanager.
3. **Nginx Proxy Manager** — needs to be up before any service behind it
   is reachable externally, and before Let's Encrypt cert renewal via the
   Cloudflare DNS challenge can run.
4. **Authelia** — needs its Postgres backend reachable (LXC 210,
   `192.168.4.210`) before it will start cleanly, so bring that LXC up
   before Authelia.
5. **Everything else** (Gitea, Vaultwarden, Wireguard, Uptime Kuma,
   Woodpecker, Portainer, etc.) — no strict ordering found between these
   in the current compose files; bring up in any order once the above are
   healthy.

## 4. Post-rebuild validation checklist

- [ ] `docker compose ps` on every stack shows `healthy`, not just `Up`
  (healthchecks were added across the board in the 2026-09-08 hardening
  pass — use them).
- [ ] DNS resolution works from inside a container on the docker-host
  (`docker exec <any container> nslookup gitea.josephbernal.com` or
  similar) — confirms Pi-hole/Unbound came up correctly and is reachable.
- [ ] Gitea: can clone/push over both HTTPS and SSH (port 222).
- [ ] Woodpecker: a test push to any repo triggers a CI run and the
  `validate-compose` + `gitleaks` pipeline steps both pass.
- [ ] Vaultwarden: existing vault items are visible after login (not just
  "login works") — confirms the data restore actually landed, not just an
  empty fresh database.
- [ ] Authelia: SSO login works end-to-end for at least one protected
  service, and an existing user's 2FA still works (confirms the storage
  encryption key restore was correct).
- [ ] Wireguard: at least one existing peer (phone/macbook/laptop)
  reconnects with its existing config, not a freshly generated one.
- [ ] Prometheus targets page shows all expected targets as `up`, and
  Alertmanager's own `/api/v2/status` shows it connected to Prometheus.
- [ ] Uptime Kuma shows all monitors green.
- [ ] futbol-db (LXC 210) is reachable at `192.168.4.210` and Authelia
  (and anything else depending on it) can actually connect.

## Known gap in this playbook

This was written from `proxmox-config/`'s captured VM/LXC definitions plus
what's already documented elsewhere in this repo — it has NOT been tested
by an actual rebuild. Treat step 4 (the validation checklist) as the real
test the first time this is ever needed for real, and update this doc with
whatever it misses.
