# Service Runbooks — Critical Services

Written 2026-09-08. Covers what to do when one of these fails, where its data
lives, and how to bring it back — for gitea, vaultwarden, authelia, and
wireguard. **Nextcloud is not included** — see the note at the bottom; it
turned up a real gap.

All paths below are relative to the repo root (`Bernal-labs-infra/`) on the
docker-host VM. All services use `restart: unless-stopped`, so Docker itself
will retry a crashed container — these runbooks are for when that isn't
enough (data corruption, config errors, host rebuild).

---

## How services are deployed (since 2026-10-01)

Every service on docker-host runs from this repo's clone at
`~/Bernal-labs-infra/<service>/docker-compose.yml`, project name =
directory name. Before 2026-10-01, 21 of 22 ran from untracked
`~/<service>/docker-compose.yml` files that no longer matched the running
containers; the compose files here were generated from `docker inspect` of
those containers, then each service was cut over with `scripts/cutover.sh`,
which diffed the new container against the old one (all identical except
CUPS's network, from its rename out of project `joe`).

- **Data and config stay where they were:** compose files use absolute
  host paths (`/home/joe/<service>/data`, `/home/joe/monitoring/prometheus.yml`,
  ...). The repo holds compose files only; the old `~/<service>/docker-compose.yml`
  files are history, don't run them.
- **Secrets:** `<service>/.env` next to the compose file (chmod 600, never
  committed); `.env.example` lists the keys.
- **Images:** pinned `tag@sha256:digest`, exactly what was running. Updates
  come from Renovate PRs. Watchtower is stopped (it can't talk to this
  Docker engine's API and had been crash-looping, updating nothing).
- **Change a service:** edit here, commit, pull on docker-host, then
  `docker compose -p <service> -f <service>/docker-compose.yml up -d`.
- **Cross-project networks** are declared `external` (NPM joins
  `gitea_default` and `vaultwarden_default`; Authelia joins
  `nginx-proxy-manager_default`; Alertmanager joins `ntfy_default`). Leaving
  one out breaks the proxying.
- **Anonymous volumes** holding state (CUPS config, pgAdmin, Alertmanager)
  are referenced by their exact names as `external`; don't delete them.

---

## Gitea

- **Container:** `gitea` — image `gitea/gitea:latest`
- **Ports:** `3000` (web/API), `222` (SSH, mapped from container's `22`)
- **Data lives in:** `gitea/data/` — this is everything: repos, the sqlite3
  database (`GITEA__database__DB_TYPE=sqlite3`), and app config. One
  directory, no external DB to worry about.
- **Health check:** `wget --spider http://localhost:3000/api/healthz`

**If it's down / unhealthy:**
1. `docker compose -f gitea/docker-compose.yml logs --tail 100 gitea`
2. Most common cause for a self-hosted sqlite Gitea: disk full, or the sqlite
   file locked by an unclean shutdown. Check disk space first.
3. `docker compose -f gitea/docker-compose.yml restart gitea` — safe to try
   before anything more invasive since there's no separate DB to desync.

**Recovery from backup / host rebuild:**
1. Restore `gitea/data/` from backup to the same path.
2. `docker compose -f gitea/docker-compose.yml up -d`
3. Confirm SSH clone/push still works on port 222 (Woodpecker CI and any
   local clones depend on this) — see the `dns: 192.168.4.2` line in the
   compose file, this container needs the internal DNS resolver reachable
   at boot or git operations against internal hosts will fail.

**Known gap:** image is pinned to `:latest`, not a specific version — a
Gitea auto-update via Watchtower could land a schema migration with no
warning. Tracked separately under the image-pinning task.

---

## Vaultwarden

- **Container:** `vaultwarden` — image `vaultwarden/server:latest`
- **Ports:** `8080` (mapped from container's `80`)
- **Data lives in:** `/home/joe/vaultwarden/data/` (moved there from inside
  the old repo clone on 2026-10-01; `data.stale-20260831` beside it is an
  older, unused copy) — sqlite DB (`db.sqlite3`),
  attachments, sends, and the RSA keys used to sign auth tokens. Losing this
  directory without a backup means every vault is unrecoverable — there is
  no server-side password recovery by design.
- **Health check:** `/healthcheck.sh` (built into the image)

**If it's down / unhealthy:**
1. `docker compose -f vaultwarden/docker-compose.yml logs --tail 100 vaultwarden`
2. Check for sqlite lock/corruption errors specifically — this is the
   highest-value data in the whole stack (password manager), treat any
   corruption warning as urgent, not routine.
3. `docker compose -f vaultwarden/docker-compose.yml restart vaultwarden`

**Recovery from backup / host rebuild:**
1. Restore `vaultwarden/data/` from backup to the same path *before* first
   start — do not `up -d` an empty data dir if a restore is pending, or
   Vaultwarden will initialize a fresh empty database over the mount point.
2. `docker compose -f vaultwarden/docker-compose.yml up -d`
3. Have at least one person confirm they can log in and see their existing
   vault items before considering the restore verified.

**Signups:** `SIGNUPS_ALLOWED=false` and `DOMAIN` set 2026-10-01. Before
that, registration was open (the setting existed only in a stale file).
Check with a registration attempt, not `/api/config`: in this version its
`disableUserRegistration` stays false either way. Expected reply to
`POST /identity/accounts/register/send-verification-email`:
"Registration not allowed or user already exists".

---

## Authelia

- **Container:** `authelia` — image `authelia/authelia:latest`
- **Ports:** `9091`
- **Data lives in:**
  - `authelia/config/` — `configuration.yml` and related config (tracked in
    git as of the 2026-09-08 hardening pass).
  - `authelia/secrets/` — `session_secret`, `jwt_secret`,
    `storage_encryption_key` (gitignored, chmod 600; see below).
- **Health check:** `authelia healthcheck` (built into the image)

**If it's down / unhealthy:**
1. `docker compose -f authelia/docker-compose.yml logs --tail 100 authelia`
2. Config-validation errors on startup are the most likely cause after any
   edit to `configuration.yml` — Authelia refuses to start on invalid YAML
   or missing required keys rather than degrading, so a bad edit here locks
   everyone out of every Authelia-protected service at once. Test config
   changes don't have a dry-run flag built in; keep a copy of the last-known-
   good `configuration.yml` before editing.
3. If login works but sessions don't persist (users keep getting bounced
   back to the login page), check that `session_secret` hasn't changed —
   changing it invalidates every active session.

**Recovery from backup / host rebuild:**
1. Restore `authelia/config/` and `authelia/secrets/` together — the
   secrets directory is gitignored, so a plain `git clone` will NOT bring it
   back. It has to come from an actual file backup or be regenerated.
2. **If `storage_encryption_key` is lost and not restored from backup,**
   Authelia's storage backend (user preferences, 2FA registrations, etc.)
   is unrecoverable — this key was deliberately left un-rotated during the
   2026-09-08 hardening pass for exactly this reason. Never regenerate it
   casually; use `authelia storage encryption change-key` if a rotation is
   ever actually needed, never a fresh random value.
3. `docker compose -f authelia/docker-compose.yml up -d`

---

## Wireguard

- **Container:** `wireguard` — image `lscr.io/linuxserver/wireguard:latest`
- **Ports:** `51820/udp`
- **Data lives in:** `wireguard/config/` — this holds the server keypair and
  **every peer's config/QR code** (`PEERS=phone,macbook,laptop`). This
  directory is the only record of those peer configs; losing it means
  regenerating and manually redistributing new configs to every device that
  uses the VPN.
- **No health check configured** — not caught in the 2026-09-08 healthcheck
  pass since it's not an HTTP service; `docker ps` container-state plus
  "can a peer actually connect" is the real signal here. Worth a
  socket/handshake-based check if this becomes a recurring pain point.

**If it's down / unresponsive:**
1. `docker compose -f wireguard/docker-compose.yml logs --tail 100 wireguard`
2. Common cause for this image specifically: `NET_ADMIN`/`SYS_MODULE`
   capabilities or the `/lib/modules` mount not being available after a host
   kernel update — check those two lines in the compose file are still
   valid for the current host kernel.
3. `docker compose -f wireguard/docker-compose.yml restart wireguard` — this
   is disruptive to anyone currently connected over VPN, so do it only when
   actually broken.

**Recovery from backup / host rebuild:**
1. Restore `wireguard/config/` from backup — this is the step that matters
   most here, since it's the only copy of every peer's private config.
2. `docker compose -f wireguard/docker-compose.yml up -d`
3. Confirm at least one peer (phone/macbook/laptop) can reconnect with its
   existing config before assuming the restore worked — a subtly wrong
   restore (e.g. server keypair mismatch) breaks all peers silently until
   someone tries to connect.

---

## Nextcloud — not actually deployed in this repo

**Update 2026-10-01:** explanation (1) was right: it ran from untracked
`~/nextcloud/docker-compose.yml`. It's in `nextcloud/` now, data at
`/home/joe/nextcloud/data`. The note below is kept as history.

The original task asked for a runbook covering "gitea, vaultwarden, authelia,
nextcloud, wireguard" — but `nextcloud/` in this repo is an **empty
directory**, and `git log` shows no history for it either. There is no
`docker-compose.yml`, no data volume, nothing to write a runbook for.

This isn't just a missing runbook — it means two other open tasks reference
a Nextcloud that doesn't exist in this repo's configuration:
- "Add healthchecks to critical services (... nextcloud)" — can't add a
  healthcheck block to a service with no compose file.
- "Add Uptime Kuma HTTP monitors for all public-facing services" — lists a
  Nextcloud URL to monitor.

Possible explanations, in rough order of likelihood: (1) Nextcloud runs from
a separate compose file or folder that isn't part of this connected repo —
same pattern as the Vault CA VM and the Renovate config both turning out to
live outside this checkout; (2) it was planned (it's in the README's
"Running Services" table) but never actually deployed; (3) it runs on a
different host entirely. This needs Joe to confirm before a runbook can be
written or the two dependent tasks can be completed as scoped.
