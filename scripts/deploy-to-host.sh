#!/usr/bin/env bash
# Deploy this session's hardening changes to docker-host.
# Run this from your Mac's own Terminal (not through Cowork).
#
# BEFORE RUNNING — edit these two lines to match your real setup:
DOCKER_HOST="docker"                      # your SSH alias/hostname for docker-host
REMOTE_REPO="~/Bernal-labs-infra"         # path to the repo on docker-host

set -e

echo "== 1. Pull latest commits on docker-host =="
ssh "$DOCKER_HOST" "cd $REMOTE_REPO && git pull origin main"

echo
echo "== 2. Copy gitignored secrets from this Mac to docker-host =="
echo "   (these never went through git — they're deliberately excluded)"
scp -r ~/Bernal-labs-infra/authelia/secrets "$DOCKER_HOST:$REMOTE_REPO/authelia/"
scp    ~/Bernal-labs-infra/woodpecker/.env  "$DOCKER_HOST:$REMOTE_REPO/woodpecker/.env"

cat <<'EOF'

== 3. MANUAL STEP — do this before starting Woodpecker ==
woodpecker/.env on docker-host still has blank
WOODPECKER_GITEA_CLIENT / WOODPECKER_GITEA_SECRET.
Register an OAuth2 application in Gitea first:
  gitea.josephbernal.com -> Settings -> Applications
  -> Manage OAuth2 Applications -> Create a new OAuth2 Application
Then SSH in and fill in the two values (using the $DOCKER_HOST /
$REMOTE_REPO you set at the top of this script):
  ssh "$DOCKER_HOST" "nano $REMOTE_REPO/woodpecker/.env"
(Woodpecker will start without this, but CI activation for repos will
not work correctly until it's set.)

EOF

echo "== 4. Pull new images and restart each touched stack =="
for svc in monitoring alertmanager watchtower gitea authelia vaultwarden uptime-kuma woodpecker; do
  echo "--- $svc ---"
  ssh "$DOCKER_HOST" "cd $REMOTE_REPO/$svc && docker compose pull && docker compose up -d"
done

echo
echo "== 5. Quick validation =="
ssh "$DOCKER_HOST" "cd $REMOTE_REPO && for s in monitoring alertmanager watchtower gitea authelia vaultwarden uptime-kuma woodpecker; do echo \"--- \$s ---\"; docker compose -f \$s/docker-compose.yml ps; done"

cat <<'EOF'

Done. Worth checking by hand afterward (see docs/RUNBOOKS.md and
docs/DISASTER-RECOVERY.md's validation checklist for the full list):
  - Prometheus -> Status -> Rules shows the 4 new alert rules
  - Alertmanager's status page shows it connected to Prometheus
  - Watchtower logs show clean check cycles, no API version errors
  - Authelia still logs in fine and existing sessions/2FA still work
  - Gitea/Vaultwarden/Uptime Kuma all show "healthy" in docker compose ps
EOF
