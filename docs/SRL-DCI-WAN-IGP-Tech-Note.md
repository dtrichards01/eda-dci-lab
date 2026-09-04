# Nokia EDA — SRL DCI WAN IGP options (OSPFv2+LDP vs IS-IS+SR-MPLS)

| | |
|---|---|
| **Document ID** | EDA-DCI-WAN-TN-001 |
| **Document owner** | Darren Richards, Cloud & Enterprise |
| **Status** | Lab tech note |
| **Scope** | Two WAN underlay options for SRL DCGW + 7250 IXR-X1b PEs (`sros-pe-1/2`) in Talos NS `clab-srl-leaf-spine-dcgw`; IGP leak of remote-site system IPs into DC spines/leafs; switch procedure |
| **EDA release** | 26.8.1 |
| **Last updated** | 2026-09-04 |
| **Lab** | **#2 Talos** UI `https://100.124.186.55/` — NS `clab-srl-leaf-spine-dcgw` |
| **YAML** | `clab/eda-ospf/`, `clab/eda-mpls-ldp/`, `clab/eda-isis/`, `clab/eda-sr-mpls/`, `clab/eda-fabric/isls.yaml`, `clab/eda-fabric/isls-isis.yaml` |

This is lab documentation, not Nokia product documentation. **Option picker (which lab / which WAN):** `docs/DCI-OPTIONS.md`. Agent index: `~/.cursor/skills/eda-dci/SKILL.md`. Service overlay (RIC, VPNv4, stitch RTs) is unchanged: `docs/L3VPN-DCI-GUIDE.md`.

---

## Purpose

Record **two interchangeable WAN underlays** for the same SRL DCI lab so we can switch without rebuilding vnets, RIC, or WAN BGP:

1. **Option 1 (default, validated):** OSPFv2 + MPLS LDP  
2. **Option 2 (live on Talos 2026-09-04):** IS-IS L2 + SR-MPLS (`SR-ISIS` tunnels, RIC encap MPLS)

Also record **SRL IGP leak behaviour**: both OSPF and IS-IS flood remote-site system `/32`s across the WAN IGP into the local DCGW default NI. Fabric eBGP will re-advertise those `/32`s onto **DC spines and leafs** unless a policy rejects IGP prefixes on the DCGW→spine export. That is the same problem for ISIS as for OSPF.

---

## Table of contents

1. [What stays the same](#1-what-stays-the-same)
2. [Option 1 — OSPFv2 + LDP](#2-option-1--ospfv2--ldp)
3. [Option 2 — IS-IS + SR-MPLS](#3-option-2--is-is--sr-mpls)
4. [SRL leak: remote system IPs on spines/leafs](#4-srl-leak-remote-system-ips-on-spinesleafs)
5. [How to switch](#5-how-to-switch)
6. [Validation](#6-validation)
7. [CLI confirmation (SR-ISIS / SR-MPLS)](#7-cli-confirmation-sr-isis--sr-mpls)
8. [What not to do](#8-what-not-to-do)
9. [References](#9-references)

---

## 1. What stays the same

Both options use the same CLAB cables and the same overlay.

| Piece | Unchanged |
|-------|-----------|
| Topology | SRL leaf/spine/DCGW + X1b `sros-pe-1` / `sros-pe-2` (`ixr-x1b`) |
| DC fabrics | `pod-1` / `pod-2` **eBGP** underlay, **iBGP** overlay, DCGW superSpine / RR |
| WAN BGP | `DefaultBGPPeer` DCGW↔DCGW, VPNv4 (+ hybrid L2 EVPN if enabled) |
| Services | `RouterInterconnect` IPVPN, stitch RTs `1:100/101/105`, vnets 1–7 / MH |
| Isolation goal | Remote **leaf/spine** system IPs must not appear on local DC spines/leafs. Remote **DCGW** `/32` **must** be on the local DCGW GRT (VPNv4 NH + tunnel) |

RIC `mpls.allowedTunnelTypes` **does** change with the option: `LDP` vs `SR-ISIS`. Overlay CRs are patched by the switch scripts, not rewritten in git as the only copy.

---

## 2. Option 1 — OSPFv2 + LDP

Recorded option. Restore with `scripts/switch-wan-ospf.sh` (not live on Talos after the 2026-09-04 cutover).

| Object | Role |
|--------|------|
| `DefaultOSPFInstance` `ospf-instance-1` / `ospf-instance-2` | DC1 / DC2 DCGW OSPFv2 |
| `DefaultOSPFArea` `backbone-0` | Area `0.0.0.0` |
| `DefaultOSPFInterface` `system-dcgw-*-system0-ipv4` | Passive DCGW `/32` |
| Fabric `backbone-simulation` | Underlay **OSPFv2** on X1b PEs (PE↔PE TopoLinks) |
| `ISL` `clab/eda-fabric/isls.yaml` | DCGW mesh + DCGW↔PE, `ospf.enabled: true` |
| `DefaultLDPRouter` / `DefaultLDPInterface` | LDP on DCGW + PE WAN ports |
| RIC `allowedTunnelTypes` | `LDP` |

PE OSPF instance name (Fabric-derived): `backbone-simulation-ospfv2-ipv4`, area `backbone-simulation-ospfv2-ipv4-0.0.0.0`.

Apply (does not cut ISIS if you only want CRs present): `bash scripts/apply-ospf.sh` then `apply-fabric-mpls.sh`. Full restore from option 2: `bash scripts/switch-wan-ospf.sh`.

---

## 3. Option 2 — IS-IS + SR-MPLS

EDA 26.8.1 on this cluster has first-class IS-IS CRs (`DefaultISISInstance`, `DefaultISISInterface`) and Fabric underlay enum **`ISIS`**. `DefaultISISInstance.spec.segmentRouting.mpls` is the SR-MPLS hook (SRGB `LabelBlock` + node SID `IndexAllocationPool`). RIC tunnel enum includes **`SR-ISIS`**.

| Object | Role |
|--------|------|
| `DefaultISISInstance` `isis-instance-1` / `isis-instance-2` | DC1 / DC2 DCGW IS-IS L2, area `49.0001`, SR-MPLS on |
| `DefaultISISInterface` `system-dcgw-*-system0-isis` | Passive DCGW `/32` (node SID) |
| Fabric `backbone-simulation` | Underlay **ISIS** (PE↔PE). Switch script patches **only** `spec.underlayProtocol.protocols` so live IP pools (`wan-interface-ipv4-pool`) stay |
| `DefaultISISInstance` `isis-instance-backbone` | X1b PEs — Fabric does **not** emit a kube `DefaultISISInstance` when underlay is ISIS |
| `ISL` `clab/eda-fabric/isls-isis.yaml` | Six DCGW mesh + DCGW↔PE links only. `isis.enabled: true`, `ospf.enabled: false`. Do **not** add user PE↔PE ISLs (conflicts with Fabric-derived `isl-sros-pe-*-c5/c6`) |
| `LabelBlock` `srgb-wan` | Static **18432–20431** (SROS SRGB start; 16000 failed X1b `MGMT_CORE #3001`) |
| `IndexAllocationPool` `sr-node-sid-pool` | Node SID indexes 1–64 |
| RIC `allowedTunnelTypes` | `SR-ISIS` (encapsulation **MPLS**) |
| LDP | `DefaultLDPRouter.spec.enabled: false` (CRs kept, tunnels gone once Down) |

**Cutover gotcha:** `kubectl apply -f isls-isis.yaml` is a merge. Nested `spec.ospf.ospfv2` (still pointing at `backbone-simulation-ospfv2-ipv4`) stays even when `ospf.enabled: false`. EDA then Degrades DCGW↔PE ISLs: *Default OSPF instance could not be resolved* and never programs ISIS on `ethernet-1/5` / `ethernet-1/6`. `switch-wan-isis.sh` runs `scripts/strip-isl-ospfv2.py` after apply.

**Validated on Talos (2026-09-04):** Fabric `protocols: [ISIS]`; `pod-1` / `pod-2` / `backbone-simulation` **Up/100** after leftover OSPF system0 + Down LDP ifaces were deleted; all six user ISLs Up; `dcgw-1` L2 adj `ethernet-1/3` (dcgw-2) + `ethernet-1/5` (PE-1); **5 SR-ISIS tunnels** (no LDP) to remote DCGW/PE `/32`s; RIC `encapsulation: MPLS` + `allowedTunnelTypes: [SR-ISIS]`; hub-spoke ping 0% loss. Spoke isolation vnet-1↛vnet-5 still holds. CLI proof: [§7](#7-cli-confirmation-sr-isis--sr-mpls).

SRL allows SR-MPLS on **one** IS-IS instance in the **default** NI per node. Each node runs a single instance (`isis-instance-1/2` on DCGWs, `isis-instance-backbone` on PEs).

---

## 4. SRL leak: remote system IPs on spines/leafs

**Do not confuse this with SRL vs SROS “all remote leaf `/32`s on the DCGW”.** That was **WAN BGP EVPN** into the GRT (BGP, not IGP) and wrong **service NH** (leaf VTEP). Canonical split: `docs/SRL-vs-SROS-DCGW-RIB.md`. This section is only **WAN IGP `/32`s leaking DCGW → local spines**.

### What we saw on OSPF (and expect on ISIS)

WAN IGP is **one domain** across both DCs: DC1 DCGW ↔ X1b PE-1 ↔ PE-2 ↔ DC2 DCGW (plus DCGW pair mesh). Passive `system0` injects each DCGW `/32`. PEs inject their system `/32`s.

SRL installs IGP-learned `/32`s in the DCGW **default** NI. That is required for:

- VPNv4 next-hop = remote DCGW system IP  
- LDP / SR-ISIS tunnel to that `/32`

If Fabric underlay eBGP on the DCGW (superSpine ↔ spine) **exports those IGP `/32`s**, local **spines and leafs** learn remote-site system addresses. Overlay then has extra underlay reachability it should not use. Remote **leaf/spine** `/32`s appear the same way if they were ever redistributed into the WAN IGP (BGP→OSPF/ISIS). Even **without** redistribution, **remote DCGW `/32`s** still leak onto spines unless eBGP export rejects protocol `OSPFv2` / `ISIS`.

**Confirmed on ISIS (2026-09-04):** `srl-spine-1` still has DC2 `11.0.0.9/32`–`11.0.0.14/32` as **BGP** in the default NI. `reject-igp-to-fabric` is applied as a Policy CR but is **not** chained on Fabric eBGP export (see attach caution below). Same leak profile as OSPF.

### Policy (both options)

`services/dci-policies/policies/reject-igp-to-fabric.yaml`:

| Statement | Match | Result |
|-----------|--------|--------|
| `reject-ospfv2` | `protocol: OSPFv2` | Reject |
| `reject-isis` | `protocol: ISIS` | Reject |
| default | — | Accept (Local system `/32` still exported) |

This is **not** the WAN BGP stitch policy (`export-wan-routes-only-dc-*` / `import-dci-services-dc-*`). Those stop **EVPN/VPNv4** fabric leak across the WAN. This policy stops **IGP `/32`s** leaking **down into the DC fabric**.

**Attach caution:** `Fabric.spec.underlayProtocol.bgp.exportPolicies` replaces the **auto** fabric eBGP export for **every** ISL in `pod-1`/`pod-2`, not only DCGW. Do not set it until a spine still has its local DCGW `/32` via eBGP. Lab default: apply the Policy CR (`apply-isis.sh` / `apply-dci-policies.sh`) and confirm leak with `validate-wan-igp.sh` on `srl-spine-1` before chaining it onto Fabric.

**Pass:** DCGW default NI has remote DCGW `/32` (and PE `/32`s). Spine/leaf default NI does **not** have remote leaf/spine `/32`s and should not need remote DCGW `/32`.

---

## 5. How to switch

CRs for both options stay in git and on the cluster. Switch **disables** the unused IGP/transport; it does not delete OSPF, LDP, ISIS, or SRGB objects.

```bash
# From Windows/WSL — copy YAML + scripts
bash ~/Documents/eda-dci-lab/scripts/sync-repo-to-talos.sh

# On Talos
bash ~/eda-dci-lab/scripts/wan-igp-status.sh

# Option 2
bash ~/eda-dci-lab/scripts/switch-wan-isis.sh
bash ~/eda-dci-lab/scripts/validate-wan-igp.sh

# Back to option 1
bash ~/eda-dci-lab/scripts/switch-wan-ospf.sh
bash ~/eda-dci-lab/scripts/validate-wan-igp.sh
```

`switch-wan-isis.sh` does **not** apply `fabrics.yaml` as a whole (live backbone uses `wan-interface-ipv4-pool` + `ipMTU: 1500`; the repo export is stale on those fields). It only patches `backbone-simulation.spec.underlayProtocol.protocols`, applies `isls-isis.yaml`, deletes leftover user PE↔PE ISLs, **JSON-patches out** `spec.ospf.ospfv2`, and **deletes** leftover `DefaultOSPFInterface` (DCGW `system0`) plus `DefaultLDPInterface` CRs. Disabling OSPF/LDP is not enough: Down system-OSPF and WAN-LDP ifaces sit on `DefaultRouter` and keep Fabric health off 100. `switch-wan-ospf.sh` re-applies those CRs.

Expect a short DCI hit while IGP adjacencies and tunnels rebuild. Overlay BGP peers stay; VPNv4 is unresolved until SR-ISIS or LDP tunnels exist.

---

## 6. Validation

`scripts/validate-wan-igp.sh` on k0r4 (docker + kubectl):

| Check | Option 1 | Option 2 |
|-------|----------|----------|
| IGP adj | OSPF neighbors on `dcgw-1` | IS-IS adjacency on `dcgw-1` |
| Transport | LDP neighbor + tunnel-table | `tunnel-table` **sr-isis** to remote DCGW `/32`; LDP FEC empty |
| Leak | `srl-spine-1` IPv4 RIB — no DC2 leaf/spine `11.0.0.x` | Same |
| Service | `scripts/test-l3-cross-dc-ping.sh` hub-spoke | Same |

EDA: Fabric `backbone-simulation` protocols, `ISL` `spec.ospf.enabled` / `spec.isis.enabled`, RIC `allowedTunnelTypes`.

---

## 7. CLI confirmation (SR-ISIS / SR-MPLS)

Live snapshot **2026-09-04** on Talos (`docker exec <node> sr_cli -e '…'`). Overlay VPNv4 next-hop is the remote DCGW `/32`; that `/32` is in TTM as **sr-isis** with next-hop type **mpls**. LDP is not in the forwarding path.

### Commands (SRL DCGW)

```bash
# IS-IS L2 WAN adj (dcgw-1: mesh + PE)
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols isis adjacency'

# TTM — WAN /32s must be Tunnel Type sr-isis, Next-hop (Type) mpls. No ldp rows.
docker exec dcgw-1 sr_cli -e 'show network-instance default tunnel-table'
docker exec dcgw-3 sr_cli -e 'show network-instance default tunnel-table'

# YANG (best EQL source): type sr-isis, owner segrt_mgr, id = node SID
docker exec dcgw-1 sr_cli -e 'info from state network-instance default tunnel-table ipv4'

# Node SIDs in SRGB 18432–20431
docker exec dcgw-1 sr_cli -e 'info from state network-instance default protocols isis instance isis-instance-1 segment-routing mpls sid-database'
docker exec dcgw-3 sr_cli -e 'info from state network-instance default protocols isis instance isis-instance-2 segment-routing mpls sid-database'

# VPNv4 stitch NH = remote DCGW system IP (then join TTM)
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols bgp routes l3vpn-ipv4-unicast summary'
docker exec dcgw-3 sr_cli -e 'show network-instance default protocols bgp routes l3vpn-ipv4-unicast summary'

# Negative: LDP must be empty
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols ldp ipv4 fec'
docker exec dcgw-1 sr_cli -e 'info from state network-instance default protocols ldp'
```

Do **not** treat `info from state … protocols bgp segment-routing-mpls` as the WAN dataplane. On this lab it is `admin-state disable` (BGP-SR). WAN SR-MPLS is **ISIS SR** (`segrt_mgr` / `sr-isis` TTM).

### Commands (SROS X1b PE — classic CLI)

`sr_cli` is not in the SRSIM container PATH. Use MD-CLI / classic on the node (or EDA EQL `.namespace.node.sros.state.*`):

```text
show router isis adjacency
show router tunnel-table
show router isis prefix-sids
show router ldp bindings
```

Expect tunnel-table **sr-isis** (not LDP) to DCGW `/32`s.

### What we saw (dcgw-1 / dcgw-3)

| Prefix | Role | Tunnel type | SID / tunnel-id | TTM next-hop |
|--------|------|-------------|-----------------|--------------|
| `11.0.0.7/32` | dcgw-1 (local on dcgw-1; remote on dcgw-3) | sr-isis on **dcgw-3** | 18433 | PE `ethernet-1/6` mpls |
| `11.0.0.8/32` | dcgw-2 | sr-isis | 18434 | dcgw-1: mesh `e1-3` mpls |
| `11.0.0.15/32` | dcgw-3 | sr-isis | 18437 | dcgw-1: PE `e1-5` mpls |
| `11.0.0.16/32` | dcgw-4 | sr-isis | 18435 | via PE |
| `11.0.0.17/32` | sros-pe-2 | sr-isis | 18438 | via PE |
| `11.0.0.18/32` | sros-pe-1 | sr-isis | 18436 | dcgw-1: PE `e1-5` mpls |

dcgw-1 TTM summary: **5 SR-ISIS active, 0 LDP**. Local fabric `11.0.0.1–4` remain **vxlan** (unchanged).

VPNv4: dcgw-1 uses `172.16.201.0/24` NH **`11.0.0.15`** (sr-isis 18437). dcgw-3 uses `172.16.101.0/24` NH **`11.0.0.7`** (sr-isis 18433).

EDA CR: RIC `encapsulation: MPLS`, `mpls.allowedTunnelTypes: [SR-ISIS]`. Fabric `backbone-simulation` `protocols: [ISIS]`, health 100.

### YANG → EQL (not yet run in EDA UI)

SRL `info from state` trees below are the translation targets (`?query=` autocomplete). Roots: `.namespace.node.srl.*`.

| Confirm | SRL YANG / likely EQL |
|---------|------------------------|
| WAN tunnel type | `network-instance.tunnel-table.ipv4.tunnel` — keys `ipv4-prefix` + `type` (`sr-isis`); `owner` = `segrt_mgr`; `id` = node SID |
| Tunnel counts | `network-instance.tunnel-table.ipv4.tunnel-summary.tunnel-type` (`sr-isis` vs `vxlan`; no `ldp`) |
| Node SIDs | `network-instance.protocols.isis.instance.segment-routing.mpls.sid-database.prefix-sid` (`sid-label-value`, `flags.node-sid`) |
| ISIS adj | `network-instance.protocols.isis.instance.interface.adjacencies` (CLI `show … isis adjacency` until EQL is confirmed) |
| VPNv4 NH | still CLI `show … bgp routes l3vpn-ipv4-unicast`; then join NH `/32` to TTM `type=sr-isis` |

SROS EQL (option 2 PE): `.namespace.node.sros.state.router.tunnel-table.ipv4.tunnel` (same join: prefix → type). LDP path `.state.router.ldp.bindings…` should be empty/unused.

---

## 8. What not to do

- Do not `kubectl apply -f clab/eda-fabric/fabrics.yaml` as part of IGP switch — it can rewrite backbone ISL pools.  
- Do not run option 2 by only applying `eda-isis/` while OSPF ISLs and LDP stay enabled — two IGPs + TTM preferring LDP. Use the switch script.  
- Do not enable SR-MPLS on a second IS-IS instance on the same SRL default NI.  
- Do not create user ISLs on PE↔PE `c5`/`c6` — Fabric already owns those TopoLinks.  
- Do not leave option-1 `DefaultOSPFInterface` `system-dcgw-*-system0-ipv4` or Down `DefaultLDPInterface` CRs in place after an ISIS cutover — they score DefaultRouter health to 0/Down and hold `pod-1`/`pod-2`/`backbone-simulation` off 100. Delete them (restore script re-applies).  
- Do not copy this WAN model onto the SROS EVPN lab (`eda-dci-sros-lab`) without converting CRs.  
- Do not treat `export-wan-routes-only-dc-*` as the spine leak filter — that is WAN BGP loop avoidance.  
- Do not confuse `bgp segment-routing-mpls` (disabled here) with ISIS SR-ISIS TTM.

---

## 9. References

- `clab/eda-ospf/README.md`, `clab/eda-isis/README.md`, `clab/eda-sr-mpls/README.md`, `clab/eda-mpls-ldp/README.md`  
- `docs/L3VPN-DCI-GUIDE.md` — VPNv4 / EVPN WAN policies  
- `services/dci-policies/draft/underlay/README-UNDERLAY-ISOLATION.md` — EVPN/VTEP isolation (different layer)  
- EDA CRDs on cluster: `DefaultISISInstance.spec.segmentRouting.mpls`, `ISL.spec.isis`, Fabric `underlayProtocol.protocols: ISIS`, RIC `allowedTunnelTypes: SR-ISIS`  
- SRL: SR-MPLS on one IS-IS instance in default NI (Nokia SR Linux Segment Routing Guide)
