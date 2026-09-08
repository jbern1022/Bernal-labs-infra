# New Service Onboarding Checklist

Written 2026-09-08. Use this whenever adding a new service to the homelab, so
the `:latest` + inline-credentials pattern stops being the default just
because there's no documented alternative. Each item links to how it's
already done elsewhere in this repo, so there's a real example to copy from.

## Before writing the compose file

- [ ] **Pick a specific image tag, not `:latest` or `:stable`.** Check the
  image's actual release tags (GitHub releases or the registry's own tag
  list — Docker Hub's API wasn't reachable from Claude's sandbox as of
  2026-09-08, so this one may need to be done by hand). Example already
  done this way: `watchtower/docker-compose.yml` pins
  `ghcr.io/nicholas-fedor/watchtower:v1.19.0`.
- [ ] **Decide the Authelia auth posture up front**: does this service sit
  behind Authelia SSO, or is it an explicit, documented exception (e.g. it
  has its own auth, or it's internal-only and not exposed via NPM at all)?
  Don't leave it unauthenticated by omission.

## Compose file itself

- [ ] `restart: unless-stopped` — already universal across every service in
  this repo; keep it that way.
- [ ] A `healthcheck:` block, so Docker can tell "container running" apart
  from "app inside actually working." Copy the pattern from
  `gitea/docker-compose.yml` (HTTP-based, `wget --spider ...`) or
  `authelia/docker-compose.yml` (uses the image's own built-in
  `healthcheck` subcommand) depending on what the new image supports.
- [ ] **Secrets via `.env` / `_FILE` env vars, never literal values in the
  compose file.** Two patterns already in this repo to copy:
  - Plain `.env` substitution (`${VAR}` in the compose file, real values in
    a gitignored `.env`, a blank `.env.example` committed instead) — see
    `woodpecker/docker-compose.yml` + `woodpecker/.env.example`.
  - File-based secrets (`SOMETHING_FILE=/secrets/foo`, the actual secret in
    a gitignored file under `./secrets/`, mounted read-only) — see
    `authelia/docker-compose.yml` + `authelia/secrets/`. Use this pattern
    when the app supports `_FILE`-suffixed env vars, since it avoids the
    secret ever showing up in `docker inspect` output or process env.
- [ ] Check whether the port needs to be reachable on `0.0.0.0` at all, or
  whether it should bind to `127.0.0.1:port:port` instead and only be
  reached through NPM's internal Docker network. As of 2026-09-08 every
  service in this repo binds `0.0.0.0` by default — that's the existing
  pattern, not necessarily the right one for a new internal-only service.

## After the compose file

- [ ] **Renovate coverage** — confirm the new image/tag is covered by
  whatever Renovate config governs this repo. (Note: as of 2026-09-08 no
  `renovate.json` was found anywhere in this connected repo — it likely
  lives in a separate `renovate` folder. Confirm that folder actually
  covers this repo before assuming Renovate will catch future updates.)
- [ ] **Uptime Kuma monitor** — add an HTTP(S) monitor if this is a
  service anyone (or anything) depends on being reachable. Pattern: see
  the existing "Add Uptime Kuma HTTP monitors for all public-facing
  services" task for the current monitor list.
- [ ] **Prometheus alert rule**, if the service's failure should page
  someone rather than just show red in Uptime Kuma. Add to
  `monitoring/rules/alerts.yml` (loaded via `rule_files:` in
  `monitoring/prometheus.yml`, and Alertmanager is wired up as of the
  2026-09-08 hardening pass — this actually fires now). Follow the
  existing rules there (`InstanceDown`, `HostDiskUsage`, `HostMemoryUsage`,
  `HostHighLoad`) as a template: `expr`, `for`, `severity` label,
  `summary`/`description` annotations.
- [ ] **CI validation** — this repo's Woodpecker pipeline
  (`.woodpecker.yml`) runs `docker compose config --quiet` against every
  compose file and a Gitleaks secrets scan on every push as of the
  2026-09-08 CI fix. A new service's compose file gets validated for free
  once it's committed — no extra step needed, just don't bypass CI on the
  commit that adds it.
- [ ] **Write (or extend) a runbook** — see `docs/RUNBOOKS.md`. At minimum:
  where the service's data volume lives, what to check first if it's down,
  and the recovery steps if the host is rebuilt.
- [ ] Add it to the "Running Services" table in the root `README.md`.

## What NOT to do

- Don't add a service's compose file and defer the healthcheck/secrets/
  pinning items "for later" — that's exactly how the current backlog of
  ~14 unpinned images and universal `:latest` tags accumulated. Do the
  checklist at add-time; retrofitting later is strictly more work per
  service (this session's hardening pass touched 9+ files to catch up on
  just healthchecks and restart policies alone).
