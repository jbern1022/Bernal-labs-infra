# ADR 002: Containerization Strategy — Docker Compose over Bare Metal

## Status
Accepted

## Context
Bernal Labs needed a strategy for deploying and managing 15+ services including reverse proxy, monitoring, auth, version control, password manager, and AI inference.

## Decision
All services deployed as Docker containers managed via Docker Compose on a dedicated Ubuntu VM (docker-host), with exceptions for services requiring VM-level isolation.

## Reasons
- Reproducible deployments via docker-compose.yml files committed to Git
- Easy service isolation without full VM overhead
- Simple rollback by pulling previous image versions
- Port mapping and network segmentation via Docker networks
- Services requiring stronger isolation (Wazuh SIEM, HashiCorp Vault) deployed as dedicated Hyper-V VMs on Powerstation

## Consequences
- All containers share the docker-host VM's resources — RAM pressure possible at scale
- Container-to-container DNS requires shared networks or explicit DNS configuration
- Docker socket exposure for tools like Portainer and cAdvisor carries security risk — mitigated by Authelia SSO
