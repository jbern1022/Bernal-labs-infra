#!/usr/bin/env bash
# Move one service on docker-host from its untracked ~/<svc>/docker-compose.yml
# (or a standalone container) to the compose file in this repo clone.
#
#   ~/Bernal-labs-infra/scripts/cutover.sh <service>      # e.g. watchtower
#
# The repo's compose files were generated from the running containers
# (2026-10-01), so a cutover should change nothing but the container's
# compose labels -- this script proves it: it saves `docker inspect` before,
# brings the service up from the repo, and diffs image, mounts, ports,
# networks and environment afterwards.
#
# Secrets: if <service>/.env is missing, it's built from the running
# containers' own environment for the keys in .env.example (chmod 600), so no
# secret is typed or copied by hand. Vaultwarden needs its data moved first:
# see docs/RUNBOOKS.md "Reconcile cutover".
set -euo pipefail

SVC="${1:?usage: cutover.sh <service>}"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="$REPO/$SVC/docker-compose.yml"
BK="$HOME/reconcile-backups-$(date +%Y%m%d)"
mkdir -p "$BK"
[[ -f "$FILE" ]] || { echo "no $FILE" >&2; exit 1; }

# Containers this file defines (container_name, or <project>-<service>-1).
mapfile -t NAMES < <(docker compose -p "$SVC" -f "$FILE" config --format json 2>/dev/null \
  | python3 -c 'import json,sys
d=json.load(sys.stdin)
for s,c in d["services"].items(): print(c.get("container_name") or f"{d[\"name\"]}-{s}-1")')

echo "==> $SVC: ${NAMES[*]}"
for n in "${NAMES[@]}"; do
  docker inspect "$n" > "$BK/$n-before.json" 2>/dev/null || echo "   (no running container $n yet)"
done

# .env from the running containers, for the keys .env.example lists.
if [[ -f "$REPO/$SVC/.env.example" && ! -f "$REPO/$SVC/.env" ]]; then
  python3 - "$REPO/$SVC" "$BK" "${NAMES[@]}" <<'EOF'
import json, os, sys
d, bk, names = sys.argv[1], sys.argv[2], sys.argv[3:]
envs = {}
for n in names:
    p = os.path.join(bk, f"{n}-before.json")
    if os.path.exists(p):
        envs[n] = dict(e.split("=", 1) for e in json.load(open(p))[0]["Config"]["Env"])
out = []
for line in open(os.path.join(d, ".env.example")):
    var = line.strip().rstrip("=")
    if not var:
        continue
    val = next((e[var] for e in envs.values() if var in e), None)
    if val is None:
        sys.exit(f"cannot find a running value for {var}; write {d}/.env by hand")
    out.append(f"{var}={val}")
fd = os.open(os.path.join(d, ".env"), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
os.write(fd, ("\n".join(out) + "\n").encode())
os.close(fd)
print(f"   wrote {d}/.env ({len(out)} key(s), from the running containers)")
EOF
fi

# A standalone container, or one from another compose project (CUPS ran as
# project "joe"), would clash on container_name: remove it -- its inspect is
# saved above, and its data lives in host paths / named volumes.
for n in "${NAMES[@]}"; do
  proj=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$n" 2>/dev/null || true)
  if docker inspect "$n" >/dev/null 2>&1 && [[ "$proj" != "$SVC" ]]; then
    echo "   removing $n (project '${proj:-none}') so compose can recreate it"
    docker rm -f "$n" >/dev/null
  fi
done

docker compose -p "$SVC" -f "$FILE" up -d

sleep 5
echo "==> comparing with the containers it replaced"
status=0
for n in "${NAMES[@]}"; do
  [[ -f "$BK/$n-before.json" ]] || continue
  docker inspect "$n" > "$BK/$n-after.json"
  python3 - "$BK/$n-before.json" "$BK/$n-after.json" <<'EOF' || status=1
import json, sys
a, b = (json.load(open(p))[0] for p in sys.argv[1:3])
def norm(c):
    return {
        "image": c["Image"],
        "mounts": sorted((m["Type"], m.get("Source") if m["Type"] == "bind" else m.get("Name"), m["Destination"], m.get("RW")) for m in c["Mounts"]),
        "ports": c["HostConfig"].get("PortBindings") or {},
        "networks": sorted((c["NetworkSettings"].get("Networks") or {}).keys()),
        "env": sorted(c["Config"].get("Env") or []),
        "restart": c["HostConfig"]["RestartPolicy"]["Name"],
        "cmd": c["Config"].get("Cmd"),
        "caps": sorted(c["HostConfig"].get("CapAdd") or []),
    }
x, y = norm(a), norm(b)
name = b["Name"].lstrip("/")
diff = [k for k in x if x[k] != y[k]]
running = b["State"]["Status"]
if not diff and running == "running":
    print(f"   {name}: identical, {running}")
else:
    print(f"   {name}: {running}; differs in {diff}")
    for k in diff:
        if k == "env":  # names only: values can be secrets
            ka = {e.split('=')[0] for e in x[k]}; kb = {e.split('=')[0] for e in y[k]}
            print(f"     env keys added {sorted(kb - ka)} removed {sorted(ka - kb)}; changed values: {sorted(e.split('=')[0] for e in set(y[k]) - set(x[k]) if e.split('=')[0] in ka)}")
        else:
            print(f"     before: {x[k]}\n     after:  {y[k]}")
    sys.exit(1)
EOF
done
[[ $status -eq 0 ]] && echo "==> $SVC now runs from $FILE" || echo "==> $SVC: review the differences above (expected ones are listed in docs/RUNBOOKS.md)"
exit $status
