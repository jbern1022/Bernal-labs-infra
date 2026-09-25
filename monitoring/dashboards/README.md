# Dashboards as code

Drop exported dashboard JSON here and Grafana picks it up automatically
(provisioned via `monitoring/grafana-provisioning/dashboards/dashboards.yml`,
polling this directory every 30s — no restart needed after adding a file).

## What's here (2026-09-25)

- `futbol-modelo/` — provisioned live from `/home/joe/monitoring/dashboards`.
- `homelab/` — exported from the live Grafana's database on 2026-09-25
  (Cadvisor exporter, Docker and system monitoring, Futbol Model, Network
  Rate, Node Exporter Full). **Not provisioned yet:** the live Grafana runs
  from `/home/joe/monitoring`, not this repo, and these five still exist
  only as UI dashboards there. To provision them, copy `homelab/` into
  `/home/joe/monitoring/dashboards/` on docker-host. Each file keeps its
  `uid`, so Grafana should take over the existing dashboard rather than add
  a duplicate; check the UI afterwards.

## How to export an existing dashboard

From the Grafana API (no UI needed), on docker-host:

    docker exec grafana sh -c 'curl -s -u admin:$GF_SECURITY_ADMIN_PASSWORD \
      http://localhost:3000/api/dashboards/uid/<uid>' \
      | python3 -c 'import json,sys; d=json.load(sys.stdin)["dashboard"]; d["id"]=None; print(json.dumps(d, indent=2))'

Or from the UI:

1. Open the dashboard in Grafana.
2. Dashboard settings (gear icon) -> JSON Model.
3. Copy the JSON, or use Share -> Export -> "Save to file".
4. Save it here as `<short-name>.json` (e.g. `node-exporter-full.json`).
5. Commit it to git — that's what makes it survive a host rebuild
   (see docs/DISASTER-RECOVERY.md) instead of living only in
   `monitoring/data/grafana`, which is gitignored on purpose.

## Folders

`foldersFromFilesStructure: true` in dashboards.yml means a subdirectory
here becomes a Grafana folder, e.g. `monitoring/dashboards/security/foo.json`
shows up in a "security" folder in the UI. Flat files at the top level of
this directory land in Grafana's General folder.

## A note on IDs

If a dashboard JSON has an `"id"` field from the old instance, remove it
(leave `"uid"` alone, or set your own) before committing — Grafana treats
a numeric `id` as instance-specific and it can cause an import conflict;
`uid` is the portable identifier provisioning actually keys off of.
