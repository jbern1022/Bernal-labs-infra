#!/usr/bin/env bash
# Validates the most recent local vzdump backup for each VM/LXC: checks the
# file is non-zero bytes AND runs a real integrity test (not just "it
# exists"), alerting via ntfy on any failure.
#
# Runs on the PROXMOX HOST ITSELF (Omen), where vzdump writes locally --
# proxmox-config/storage.cfg shows the "local" dir store at /var/lib/vz.
# This is deliberately a second, independent check alongside Proxmox Backup
# Server's own verify jobs: PBS already dedups and can verify what it
# stores, but the legacy vzdump job (kept running alongside PBS on purpose,
# for redundancy) has no automatic verification of its own -- that's the
# gap this closes. Intended to run WEEKLY via the systemd timer below.
#
# CONFIGURE BEFORE USE:
#   NTFY_URL below is a placeholder -- fill in the real address. The repo's
#   existing convention (alertmanager/alertmanager.yml) posts to ntfy on
#   its docker-internal IP (192.168.32.2:80), which is NOT reachable from
#   the Proxmox host itself (different machine from docker-host). Use
#   docker-host's LAN IP + published port instead, e.g.
#   http://<docker-host-lan-ip>:8095/homelab-alerts -- same "homelab-alerts"
#   topic already used by Alertmanager, so it lands in the same ntfy feed.

set -uo pipefail  # not -e: keep checking remaining backups even if one fails

BACKUP_DIR="${BACKUP_DIR:-/var/lib/vz/dump}"
NTFY_URL="${NTFY_URL:-http://CHANGE_ME:8095/homelab-alerts}"
FAILURES=()

if [ ! -d "$BACKUP_DIR" ]; then
  FAILURES+=("Backup directory $BACKUP_DIR does not exist or isn't reachable.")
fi

# Only check the MOST RECENT backup per VMID, not every historical one --
# vzdump filenames are vzdump-qemu-<vmid>-<timestamp>.vma.zst or
# vzdump-lxc-<vmid>-<timestamp>.tar.zst (zstd is the default compressor as
# of Proxmox VE 7+; adjust the glob below if this host uses lzo/gzip instead).
shopt -s nullglob
declare -A latest_by_vmid
for f in "$BACKUP_DIR"/vzdump-*-*-*.vma.zst "$BACKUP_DIR"/vzdump-*-*-*.tar.zst; do
  vmid=$(basename "$f" | awk -F'-' '{print $3}')
  [ -z "$vmid" ] && continue
  if [ -z "${latest_by_vmid[$vmid]:-}" ] || [ "$f" -nt "${latest_by_vmid[$vmid]}" ]; then
    latest_by_vmid[$vmid]="$f"
  fi
done

if [ ${#latest_by_vmid[@]} -eq 0 ]; then
  FAILURES+=("No vzdump backup files found under $BACKUP_DIR -- check the path, or whether this host still runs vzdump at all.")
fi

for vmid in "${!latest_by_vmid[@]}"; do
  f="${latest_by_vmid[$vmid]}"
  size=$(stat -c%s "$f" 2>/dev/null || echo 0)
  if [ "$size" -eq 0 ]; then
    FAILURES+=("VMID $vmid: backup file $f is zero bytes.")
    continue
  fi
  if ! zstd -t "$f" >/dev/null 2>&1; then
    FAILURES+=("VMID $vmid: backup file $f failed zstd integrity test (zstd -t).")
  fi
done

if [ ${#FAILURES[@]} -gt 0 ]; then
  msg=$(printf '%s\n' "${FAILURES[@]}")
  echo "BACKUP VALIDATION FAILED:"
  echo "$msg"
  curl -sS -H "Title: Backup validation failed" -H "Priority: high" -d "$msg" "$NTFY_URL" >/dev/null || true
  exit 1
fi

echo "All ${#latest_by_vmid[@]} backup(s) passed validation."
