# Bernal Labs — Private Cloud Infrastructure

Self-hosted private cloud running on Proxmox with Docker, built for security, privacy, and enterprise-grade practices.

## Architecture

- **Hypervisor:** Proxmox VE on HP Omen (always-on)
- **Compute:** Docker host VM + Ryzen 7 9800X3D / RTX 5070 AI inference node
- **Network:** eero mesh, Pi-hole + Unbound for private DNS, Wireguard VPN
- **SSL:** Let's Encrypt wildcard cert via Cloudflare DNS challenge
- **GitOps:** Gitea → Woodpecker CI → Argo CD (in progress)

## Running Services

| Service | Purpose |
|---|---|
| Nginx Proxy Manager | Reverse proxy + SSL termination |
| Gitea | Self-hosted Git |
| Vaultwarden | Self-hosted password manager |
| Nextcloud | Self-hosted cloud storage |
| Prometheus + Grafana | Metrics and observability |
| Uptime Kuma | Uptime monitoring |
| Wireguard | VPN
eof
