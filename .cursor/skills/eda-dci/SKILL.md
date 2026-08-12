---
name: eda-dci
description: >-
  SRL IPVPN DCI lab — VPNv4 WAN, fabric EVPN isolation, vnet stitch, client
  matrix. Use in eda-dci-lab for DCGW policies, MH/ESI, or cross-DC debugging.
---

# eda-dci-lab

**Namespace:** `clab-srl-leaf-spine-dcgw`  
**RIC:** IPVPN · **RT format:** `target:1:NNN`  
**DCGW nodes:** `dcgw-1`…`dcgw-4`

## Read first (this repo)

1. `docs/L3VPN-DCI-GUIDE.md`
2. `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` — EVPN vs IPVPN, DCGW checks, MPLS/VXLAN, CLI
3. `docs/EDGE-INTERFACES.md` — client ↔ vnet ↔ leaf port mapping
4. `docs/L2-DCI-GUIDE.md`

## Quick checks

| Test | From |
|------|------|
| DCI control-plane | `ping 2.2.2.2 -I 1.1.1.1` on service router |
| Client end-to-end | ping/traceroute from client eth1 |

## SRL-specific rules

- **Block fabric EVPN** on WAN import/export (`reject-all-local/remote-evpn`)
- **No Policy `metadata.annotations`** (strip descriptive / loop-avoidance annotations from CR YAMLs)
- VPN match: `protocol: BGP_IPVPN` (not SROS `BGP_VPN`)
- Hub: `multi-rt-import` + `vpn-import-rts` may work on **SRL**; **do not copy to SROS** — SROS CommunitySet is All-only (no `Any`); use one set/Accept per RT (`import-ric-vnet-2` in eda-dci-sros-lab)
- Do not copy SROS EVPN RIC policies here without conversion
- Policy CR field: **`statements`** (plural)
- **Loopback Interface:** single-member only (`type: Loopback`).
- **Multi-leaf same subnet:** enable IRB `hostRoutePopulate` / related EVPN host-route params when hosts span multiple leaves.
- **EQL cheat sheet:** `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` §4; live aliases/catalog in **eda-mcp** UI.

## Client / vnet matrix (summary)

| Clients | VNet | Notes |
|---------|------|-------|
| client-1/2 | vnet-1 | DC1 L3 |
| client-3/4 | vnet-2 | DC2 L3 hub |
| client-5 | vnet-5 | DC1 spoke |
| client-6/7 | vnet-3/4 | L2 BDI |

Clients: `default via <irb-gw>` on eth1.

## Personal skill (full reference)

`~/.cursor/skills/eda-dci/` — WAN policy tables, debugging workflow, Talos notes.

## Keep this skill updated

When you fix policies, find a root cause, or learn a repo-specific quirk, update this file and/or `~/.cursor/skills/eda-dci/`. Share cross-project lessons in the personal skill; keep repo paths and scripts here.
