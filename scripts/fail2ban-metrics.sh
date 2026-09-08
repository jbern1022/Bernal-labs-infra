#!/usr/bin/env bash
# Exports fail2ban ban counts as Prometheus textfile-collector metrics, for
# node-exporter's --collector.textfile.directory (see monitoring/docker-compose.yml).
#
# IMPORTANT: fail2ban itself is not containerized in this repo (fail2ban/ only
# has jail.local, no docker-compose.yml) -- it runs natively on whichever host
# actually has fail2ban-client installed. This script has to run on THAT SAME
# HOST, natively (via the systemd unit below), not inside a container. If
# fail2ban runs somewhere other than docker-host, point OUT_DIR at wherever
# that host can reach the path node-exporter's textfile_collector volume
# mounts from (e.g. an NFS/shared mount), or adjust the approach entirely.
#
# Field names ("Currently banned", "Total banned") verified against fail2ban's
# own source (fail2ban/server/actions.py, Actions.status()), not guessed.

set -euo pipefail

OUT_DIR="${FAIL2BAN_METRICS_DIR:-/opt/Bernal-labs-infra/monitoring/data/textfile_collector}"
OUT_FILE="$OUT_DIR/fail2ban.prom"

mkdir -p "$OUT_DIR"
TMP_FILE="$(mktemp "$OUT_DIR/.fail2ban.prom.XXXXXX")"
trap 'rm -f "$TMP_FILE"' EXIT

{
  echo "# HELP fail2ban_currently_banned Number of IPs currently banned in this jail."
  echo "# TYPE fail2ban_currently_banned gauge"
  echo "# HELP fail2ban_total_banned Cumulative number of IPs banned in this jail since fail2ban started."
  echo "# TYPE fail2ban_total_banned counter"

  jails=$(fail2ban-client status 2>/dev/null | grep "Jail list:" | awk -F':' '{print $2}' | tr ',' '\n' | tr -d ' \t\r' || true)

  for jail in $jails; do
    [ -z "$jail" ] && continue
    status=$(fail2ban-client status "$jail" 2>/dev/null || true)
    currently=$(echo "$status" | grep "Currently banned" | grep -oE '[0-9]+' | tail -1 || true)
    total=$(echo "$status" | grep "Total banned" | grep -oE '[0-9]+' | tail -1 || true)
    [ -n "${currently:-}" ] && echo "fail2ban_currently_banned{jail=\"$jail\"} $currently"
    [ -n "${total:-}" ] && echo "fail2ban_total_banned{jail=\"$jail\"} $total"
  done
} > "$TMP_FILE"

# Atomic replace -- node-exporter's textfile collector never sees a half-written file.
mv "$TMP_FILE" "$OUT_FILE"
trap - EXIT
