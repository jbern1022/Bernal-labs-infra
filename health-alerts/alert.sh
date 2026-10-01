#!/bin/sh
# Post to ntfy when a container's healthcheck changes: unhealthy (alert) and
# back to healthy after that (recovered). Docker emits health_status events
# on changes, so this only speaks on transitions. On start it also reports
# anything already unhealthy, so a restart of this watcher can't hide one.
set -u
: "${NTFY_URL:?set NTFY_URL, e.g. http://192.168.4.20:8095/homelab_alerts}"
HOST="${ALERT_HOST:-docker-host}"
STATE=/tmp/unhealthy
touch "$STATE"

notify() { # title priority tags message
  wget -q -O /dev/null --header "Title: $1" --header "Priority: $2" --header "Tags: $3" \
    --post-data "$4" "$NTFY_URL" || echo "ntfy post failed: $1" >&2
}

for name in $(docker ps --filter health=unhealthy --format '{{.Names}}'); do
  echo "$name" >> "$STATE"
  notify "$HOST: $name is unhealthy" high warning "$name was already unhealthy when the watcher started. Check: docker inspect --format '{{json .State.Health}}' $name"
done
echo "watching health events (already unhealthy: $(wc -l < "$STATE"))"

docker events --filter type=container --filter event=health_status \
  --format '{{.Actor.Attributes.name}} {{.Action}}' |
while read -r name status; do
  case "$status" in
    *unhealthy)
      grep -qx "$name" "$STATE" && continue
      echo "$name" >> "$STATE"
      last=$(docker inspect --format '{{with .State.Health}}{{range .Log}}exit {{.ExitCode}}: {{.Output}}{{"\n"}}{{end}}{{end}}' "$name" 2>/dev/null | grep . | tail -n 1 | cut -c1-300)
      notify "$HOST: $name is unhealthy" high warning "Healthcheck failing. Last output: ${last:-n/a}" ;;
    *healthy)
      grep -qx "$name" "$STATE" || continue
      grep -vx "$name" "$STATE" > "$STATE.new"; mv "$STATE.new" "$STATE"
      notify "$HOST: $name recovered" default white_check_mark "$name is healthy again." ;;
  esac
done
echo "docker events stream ended; exiting so the restart policy reconnects" >&2
exit 1
