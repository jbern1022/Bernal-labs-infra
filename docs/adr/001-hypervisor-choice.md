# ADR 001: Hypervisor Selection — Proxmox VE over VMware ESXi

## Status
Accepted

## Context
Bernal Labs required a Type 1 hypervisor to host VMs and containers for a private cloud homelab. The primary candidates were Proxmox VE and VMware ESXi.

## Decision
Selected Proxmox VE as the primary hypervisor.

## Reasons
- Open source with no licensing cost vs ESXi's free tier limitations
- Native LXC container support alongside full VMs
- Built-in web UI, backup scheduler, and cluster support
- Active community and long-term viability (not subject to Broadcom acquisition uncertainty)
- Debian-based — familiar package management and tooling

## Consequences
- No VMware-specific tooling or vCenter integration
- Must manage Proxmox updates manually
- Proxmox backup format differs from VMware — not portable to vSphere environments
