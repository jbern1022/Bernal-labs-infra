# Dashboards as code

Drop exported dashboard JSON here and Grafana picks it up automatically
(provisioned via `monitoring/grafana-provisioning/dashboards/dashboards.yml`,
polling this directory every 30s — no restart needed after adding a file).

## How to export an existing dashboard

This can only be done from the live Grafana UI (I couldn't do this part —
it needs an actual running instance to export from):

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
