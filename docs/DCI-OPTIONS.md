# DCI options (git index)

| | |
|---|---|
| **Status** | Canonical landing page for *which* DCI lab / overlay / WAN underlay / **use case** is live |
| **Last updated** | 2026-09-08 |
| **Share** | This file + sibling GitHub repos below. Cursor skill: `~/.cursor/skills/eda-dci/SKILL.md` |
| **EDA** | All instances **26.8.1** |

Do not mix these option sets. **WAN IGP option 1 vs 2** is only the Talos SRL lab. **3-site fabric options 1–4** are a different repo. **SRL vs SROS** is overlay/policy, not IGP.

GitHub (private unless noted): [eda-dci-lab](https://github.com/dtrichards01/eda-dci-lab) · [eda-dci-sros-lab](https://github.com/dtrichards01/eda-dci-sros-lab) · [eda-dci-evpn-lab](https://github.com/dtrichards01/eda-dci-evpn-lab) · [eda-3-site-bl-spine](https://github.com/dtrichards01/eda-3-site-bl-spine)

---

## 1. Which lab

| Lab | Repo (git) | EDA instance | Namespace | Overlay |
|-----|------------|--------------|-----------|---------|
| **SRL IPVPN DCI** | [eda-dci-lab](https://github.com/dtrichards01/eda-dci-lab) | **#2 Talos** `https://100.124.186.55/` | `clab-srl-leaf-spine-dcgw` | RIC **IPVPN**, RTs `target:1:NNN` |
| **SROS EVPN DCI** | [eda-dci-sros-lab](https://github.com/dtrichards01/eda-dci-sros-lab) | **#3 WSL** `https://127.0.0.1:9443` | `clab-3-tier-leaf-spine-dcgw` | RIC **EVPN**, RTs `target:100:100` |
| **EVPN RIC trial** | [eda-dci-evpn-lab](https://github.com/dtrichards01/eda-dci-evpn-lab) | varies | experimental | Do **not** copy policies from here |
| **3-site D5+SR-1** | [eda-3-site-bl-spine](https://github.com/dtrichards01/eda-3-site-bl-spine) | **#2 Talos** (CLAB on k0r4) | `clab-3-site-bl-spine` | Fabric **options 1–4** (live = **4** L2) |

Never copy Policy YAML between SRL and SROS without converting match syntax. Table: `~/.cursor/skills/eda-dci/reference.md` (also copied into each lab’s `.cursor/skills/eda-dci/`).

---

## 2. Use cases (validated — share this table)

Status as of **2026-09-08**. “Live” means that design is what the lab is running now, not that every row is pinging at this instant.

### Talos SRL (`eda-dci-lab`, #2)

| Use case | CRs / RTs | Status | Notes |
|----------|-----------|--------|--------|
| L3 hub-spoke IPVPN | vnet-1 `1:100`, hub vnet-2 `1:101` + `multi-rt-import`, spoke vnet-5 `1:105` | **Operational** (2026-08-24) | Ping vnet-1 ↔ hub; hub → spoke GW; spoke isolation vnet-1 → `151.254` fail by design |
| L2 BDI | vnet-3/4, RT `1:300`/`1:301` | In git | EVPN-MPLS on DCGW |
| L3 single-home | vnet-6/7 RT `400`/`401` | In git | |
| L3 MH (ESI LAG) | `vnet-mh-l3-dc1a/b`, `dc2a/b` | In git | AllActive / SingleActive on leaf `e1-10` |
| WAN IGP **option 2** | ISIS L2 + **SR-ISIS** | **Live 2026-09-04** | RIC `allowedTunnelTypes: [SR-ISIS]` |
| WAN IGP option 1 | OSPFv2 + LDP | Restore script | `scripts/switch-wan-ospf.sh` |
| Hybrid WAN EVPN+IPVPN | same WAN peers both AFIs | Demo only | Not production; do not mix statements in **one** Policy |

Pass L3: VPNv4 NH = remote **DCGW** `/32`, then SR-ISIS (or LDP) tunnel. SRL **must** reject fabric EVPN on WAN (`reject-all-local-evpn` / `reject-all-remote-evpn`).

### WSL SROS (`eda-dci-sros-lab`, #3)

| Use case | CRs / RTs | Status | Notes |
|----------|-----------|--------|--------|
| L3 EVPN RIC hub-spoke | vnet-1 `100:100`, hub vnet-2 `101:101` + `import-ric-vnet-2`, spoke `102:102` | **Operational** | Hub: **one CommunitySet + one Accept per RT** (SROS All-only) |
| L2 BDI | vnet-3/4 `300:300`/`301:301` | **Up** | MPLS; `bridge-domian-interconnect-vnet-4` name typo is live |
| WAN EVPN policies | `import/export-dci-evpn-dc-{1,2}` | Live pattern | Do **not** use obsolete `import-dci-services-dc-*` |
| WAN IPVPN policies | `import/export-dci-ipvpn-dc-{1,2}` | In git | Separate peers; never mix with EVPN in one Policy |
| Anycast IRB loopback | `arpDynamic` + `l3ProxyARPND` | Verified 2026-08-13 | Write via **EDA API**, not kubectl |
| Policy `configuredName` ≠ CR name | RIC-attached Policies | **Do not** | 26.8.1 txn 5103 `MGMT_CORE #240` |

EDA **26.8.1**. DCGW **SROS 26.3.R1** SR-1. SRL fabric **26.7.x** (README used to say 25.10 / 26.3.1 — stale). Limited-support 26.8.1 examples (NH match + RTM pref): `services/dci-policies/examples/26.8.1-bgp-nh-rtm-pref/` — **not** on live WAN peers.

### 3-site D5 + SR-1 (`eda-3-site-bl-spine`, #2 / k0r4)

| Fabric option | Overlay | L3 fail matrix | L2 MH | Live? |
|---------------|---------|----------------|-------|-------|
| **1** | one Fabric iBGP overlay | **Passed** | — | Snapshot YAML |
| **2** | per-site Fabric + iBGP RR–RR | **Passed** | **Passed** (T1+T4, AllActive) | Snapshot |
| **3** | eBGP UL+OL, SROS as **spine** | **Failed** | — | NHS = RFC 8365 §10.2 anti-pattern. Do not retry Configlet knobs |
| **4** | eBGP UL+OL, D5=`leaf`, SROS=`wan` BL | **L3 passed** | **L2 A/A unicast works** (T1). **Local T4 missing** (eBGP ASBR does not re-advertise ES-import RT) | **Live** `vnet-l2` |

Briefing master (do not regenerate): `eda-3-site-bl-spine/docs/EDA-3-site-overlay-options-RFC.pptx`. Fail matrix + RFC table: `docs/3-site-bl-spine-fabric-and-failure.md`.

### Related overlay (not DCI WAN)

| Use case | Repo / NS | Status |
|---------|-----------|--------|
| First EVPN VXLAN L2 on **7220 IXR-H5 TH** | Kind **#1** `clab-h5-2x2` · YAML `netbox-eda-lab/clab/` | **Up** 2026-09-03. Skill: `~/.cursor/skills/eda/h5-th-evpn.md` (not this repo) |

---

## 3. Talos SRL — WAN underlay (option 1 vs 2)

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

## 4. Overlay / GRT (SRL vs SROS) — not an IGP option

| | SRL (this repo) | SROS (`eda-dci-sros-lab`) |
|--|-----------------|---------------------------|
| WAN fabric EVPN | **Must** deny (`reject-all-local-evpn` egress, `reject-all-remote-evpn` ingress) | Not required |
| Wrong L3 NH | VPNv4 NH = remote **leaf VTEP** | Did not show this |
| Pass L3 | VPNv4 NH = remote **DCGW** `/32` + SR-ISIS/LDP tunnel | Same idea; EVPN RIC |

Canonical: `docs/SRL-vs-SROS-DCGW-RIB.md`. Score overlay from the **VPNv4** row, not “GRT empty of remote leaf `/32`s”.

---

## 5. 3-site fabric options (other repo)

See **§2** table. YAML and fail matrix: [3-site-bl-spine-fabric-and-failure.md](https://github.com/dtrichards01/eda-3-site-bl-spine/blob/main/docs/3-site-bl-spine-fabric-and-failure.md).

---

## 6. Related docs in this repo

| Doc | Use |
|-----|-----|
| `docs/L3VPN-DCI-GUIDE.md` | Policies, AFIs, stitch RTs |
| `docs/L2-DCI-GUIDE.md` | BDI / hybrid L2 |
| `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` | EVPN vs IPVPN checks |
| `docs/DCI-ALIGNMENT.md` | Hub/spoke apply order |
| `docs/SRL-DCI-WAN-IGP-Tech-Note.md` | WAN IGP option 1 vs 2 CLI/YANG |
| `docs/SRL-vs-SROS-DCGW-RIB.md` | GRT leak vs IGP |
