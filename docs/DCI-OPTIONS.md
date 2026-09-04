# DCI options (git index)

| | |
|---|---|
| **Status** | Canonical landing page for *which* DCI lab / overlay / WAN underlay is live |
| **Last updated** | 2026-09-04 |
| **Agent** | `~/.cursor/skills/eda-dci/SKILL.md` — then this file |

Do not mix these option sets. **WAN IGP option 1 vs 2** is only the Talos SRL lab. **3-site fabric options 1–4** are a different repo. **SRL vs SROS** is overlay/policy, not IGP.

---

## 1. Which lab

| Lab | Repo (git) | EDA instance | Namespace | Overlay |
|-----|------------|--------------|-----------|---------|
| **SRL IPVPN DCI** | [eda-dci-lab](https://github.com/dtrichards01/eda-dci-lab) | **#2 Talos** `https://100.124.186.55/` | `clab-srl-leaf-spine-dcgw` | RIC **IPVPN**, RTs `target:1:NNN` |
| **SROS EVPN DCI** | [eda-dci-sros-lab](https://github.com/dtrichards01/eda-dci-sros-lab) | **#3 WSL** `https://127.0.0.1:9443` | `clab-3-tier-leaf-spine-dcgw` | RIC **EVPN**, RTs `target:100:100` |
| **EVPN RIC trial** | `eda-dci-evpn-lab` | varies | experimental | Do not copy policies from here |
| **3-site D5+SR-1** | [eda-3-site-bl-spine](https://github.com/dtrichards01/eda-3-site-bl-spine) | **#2 Talos** | `clab-3-site-bl-spine` | Fabric **options 1–4** (live = **4** L2) |

Never copy Policy YAML between SRL and SROS without converting match syntax. Table: `~/.cursor/skills/eda-dci/reference.md`.

---

## 2. Talos SRL — WAN underlay (option 1 vs 2)

Same CLAB, same vnets/RIC/WAN BGP. Only IGP + tunnel type change. Overlay must stay.

| | **Option 1** | **Option 2 (live 2026-09-04)** |
|--|----------------|--------------------------------|
| IGP | OSPFv2 | IS-IS L2 |
| Tunnel | LDP | **SR-ISIS** (SR-MPLS) |
| RIC | `allowedTunnelTypes: [LDP]` | `encapsulation: MPLS`, `allowedTunnelTypes: [SR-ISIS]` |
| Switch **to** this | `scripts/switch-wan-ospf.sh` | `scripts/switch-wan-isis.sh` |
| YAML in git | `clab/eda-ospf/`, `clab/eda-mpls-ldp/`, `clab/eda-fabric/isls.yaml` | `clab/eda-isis/`, `clab/eda-sr-mpls/`, `clab/eda-fabric/isls-isis.yaml` |
| Confirm | LDP FEC / `nexthop-tunnel-type=ldp` | `show network-instance default tunnel-table` → **sr-isis**, owner `segrt_mgr` |

**Detail + cutover gotchas:** `docs/SRL-DCI-WAN-IGP-Tech-Note.md` (do not apply whole `fabrics.yaml`; strip leftover `ISL.spec.ospf.ospfv2`; delete leftover OSPF `system0` + Down LDP ifaces or Fabric health stays off 100; no user PE↔PE ISLs).

**PE ISIS `system0`:** keep DCGW user CRs `system-dcgw-*-system0-isis`. YAML still lists `system-sros-pe-*-system0-isis` — confirm vs Fabric-derived before deleting; `isis-instance-backbone` is required (Fabric does not emit a PE ISIS instance).

---

## 3. Overlay / GRT (SRL vs SROS) — not an IGP option

| | SRL (this repo) | SROS (`eda-dci-sros-lab`) |
|--|-----------------|---------------------------|
| WAN fabric EVPN | **Must** deny (`reject-all-local-evpn` egress, `reject-all-remote-evpn` ingress) | Not required |
| Wrong L3 NH | VPNv4 NH = remote **leaf VTEP** | Did not show this |
| Pass L3 | VPNv4 NH = remote **DCGW** `/32` + SR-ISIS/LDP tunnel | Same idea; EVPN RIC |

Canonical: `docs/SRL-vs-SROS-DCGW-RIB.md`. Score overlay from the **VPNv4** row, not “GRT empty of remote leaf `/32`s”.

---

## 4. 3-site fabric options (other repo)

Live **Option 4** (eBGP UL+OL, D5=`leaf`, SROS=`wan` borderleafs). Options 1–2 L3 passed; **Option 3 failed** (SROS spine NHS). YAML and fail matrix: `eda-3-site-bl-spine/docs/3-site-bl-spine-fabric-and-failure.md`.

---

## 5. Related docs in this repo

| Doc | Use |
|-----|-----|
| `docs/L3VPN-DCI-GUIDE.md` | Policies, AFIs, stitch RTs |
| `docs/L2-DCI-GUIDE.md` | BDI / hybrid L2 |
| `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` | EVPN vs IPVPN checks |
| `docs/DCI-ALIGNMENT.md` | Hub/spoke apply order |
