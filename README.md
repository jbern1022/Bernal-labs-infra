# Bernal Labs — Private Cloud Infrastructure

Self-hosted private cloud running on Proxmox with Docker, built for security, privacy, and enterprise-grade practices.

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
| Wireguard | VPN remote access |
| Pi-hole + Unbound | Network-wide DNS privacy |
| Portainer | Container management 
| Authelia | SSO / single sign-on authentication |

## Security Stack (in progress)

| Authelia SSO — identity and access management
- CrowdSec — collaborative intrusion prevention
- Wazuh — SIEM and security monitoring
- HashiCorp Vault — secrets management and internal CA
- OpenLDAP — enterprise directory services
- Fail2ban — SSH intrusion prevention
- Trivy — container vulnerability scanning

## Structure
├── docker/
├── monitoring/
├── nginx-proxy-manager/
├── pi-hole/
├── unbound/
├── fail2ban/
├── wireguard/
└── vaultwarden/

## Domain

All services served over HTTPS via josephbernal.com with wildcard SSL.

---
*Built and maintained by Joe Bernal — Senior TPM with 13 years of enterprise IT experience.*
"""

with open('README.md', 'w') as f:
    f.write(readme)
print("README written successfully")


