# L3 VPN DCI — policy map, address families, and WAN MPLS validation

**Namespace:** `clab-srl-leaf-spine-dcgw`  
**Validated:** vnet-1 ↔ vnet-2 hub, vnet-5 ↔ vnet-2 hub-spoke (bidirectional `eth1` ping)  
**Last updated:** 2026-08-04

Companion docs: `DCI-ALIGNMENT.md` (service model), `CLAB-VALIDATION.md` (topology).

This document is the **authoritative policy map**: which routing policies and community sets are applied on which objects, why, and how fabric control-plane noise (leaf system IPs, VTEPs, EVPN routes) is kept off the WAN.

---

## 1. Why two transports and three BGP address families

Cross-DC L3 uses **different control planes on different legs**. That is intentional.


| Leg                                               | Network instance        | Encapsulation | BGP AFI / control                        | Why                                                                                                                 |
| ------------------------------------------------- | ----------------------- | ------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **Fabric** (leaf ↔ spine ↔ DCGW)                  | `router-1` / `router-2` | VXLAN         | **EVPN**                                 | L3 IRB on fabric: EVPN type-2 (MAC-IP) and type-5 (IP prefix). NH = local leaf/DCGW VTEP. |
| **RIC stitch** (service NI ↔ WAN NI on same DCGW) | `router-`* ↔ `default`  | MPLS / LDP    | **IPVPN** (`controlPlane: IPVPN` on RIC) | EDA leaks stitch RTs between service router and interconnect BGP instance.                                          |
| **WAN** (DCGW ↔ DCGW)                             | `default`               | MPLS / LDP    | **VPNv4 only** (`vpnIPv4Unicast`)        | Carries **stitch prefixes only** with **DCGW system IP** as BGP NH. EVPN disabled so fabric routes never cross WAN. |


---



## 2. Restricting fabric / system addresses from the WAN

**Goal:** Remote DC fabric must not learn local leaf loopbacks, VTEP addresses, EVPN type-2 host routes, or arbitrary EVPN type-5 prefixes across the DCI WAN. Only **intentional stitch service prefixes** (`101/24`, `201/24`, `151/24`) cross DCGW↔DCGW BGP.

**Problem if unrestricted:** With `l2VPNEVPN` enabled on WAN peers, BGP EVPN carries routes whose next-hop is a **remote leaf VTEP** or **system address**. MPLS/VXLAN would then try to reach fabric internals over the WAN — wrong encapsulation, broken forwarding, and security/scale issues.

**Mechanisms (layered):**

### 2.1 WAN BGP address families (`DefaultBGPPeer`)

Applied via `services/dci-policies/bgp-peers/wan-vpnv4-only-patch.json` on all four WAN peers.


| AFI              | Enabled   | Effect                                                                                                                    |
| ---------------- | --------- | ------------------------------------------------------------------------------------------------------------------------- |
| `ipv4Unicast`    | **false** | No plain BGP IPv4 on WAN (underlay uses OSPF in `default`). Blocks `/32` loopback-style IPv4 unicast leak.                |
| `l2VPNEVPN`      | **false** | **No EVPN on WAN** — remote fabric EVPN (type-2 MAC-IP, type-5 with VTEP NH, inclusive multicast, etc.) is not exchanged. |
| `vpnIPv4Unicast` | **true**  | Only MPLS VPN-IPv4 (IPVPN) stitch prefixes cross the WAN.                                                                 |


`nextHopSelf: true` on WAN peers rewrites exported VPNv4 next-hop to the **local DCGW system IP** (`11.0.0.7`, `11.0.0.15`, …), not a fabric VTEP.

### 2.2 WAN export policies (outbound from each DC)

Default action: **Reject**. Only explicit stitch RT matches are exported.


| Policy                           | Peers                            | Accept for export                                                                                           | Reject (fabric / loop protection)                                                     |
| -------------------------------- | -------------------------------- | ----------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `export-dc-1-routes-and-add-soo` | `dcgw-1-dcgw-3`, `dcgw-2-dcgw-4` | VPNv4 with `dci-rt-dc1-l3` (RT 100, vnet-1) or `dci-rt-vnet-5-stitch` (RT 102, vnet-5). Add SOO `soo-1122`. | All **EVPN** families. VPNv4/EVPN routes tagged `tag-20` (already imported from WAN). |
| `export-dc-2-routes-and-add-soo` | `dcgw-3-dcgw-1`, `dcgw-4-dcgw-2` | VPNv4 with `dci-rt-dc2-l3` (RT 101, vnet-2 hub). Add SOO `soo-2211`.                                        | All **EVPN** families. VPNv4/EVPN tagged `tag-10`.                                    |


**Why this blocks fabric addresses:** Fabric EVPN (including type-5 with leaf/DCGW VTEP NH) lives in the **EVPN** family on `default` after RIC leak. Export policies **reject all EVPN** before any accept — nothing from the fabric EVPN RIB is sent to WAN peers. Only VPNv4 routes tagged with stitch RT communities (from the IPVPN RIC leak path) are exported.

### 2.3 WAN import policies (inbound to each DC)


| Policy                     | Peers   | Accept                                                                             | Reject                                               |
| -------------------------- | ------- | ---------------------------------------------------------------------------------- | ---------------------------------------------------- |
| `import-dci-services-dc-1` | DC1 WAN | Remote VPNv4 matching `dci-rt-dc2-l3` (hub RT 101). Apply `tag-20`.                | All remote **EVPN**. EVPN with local SOO `soo-1122`. |
| `import-dci-services-dc-2` | DC2 WAN | Remote VPNv4 matching `dci-rt-dc1-l3` (RT 100) or `dci-rt-vnet-5-stitch` (RT 102). | All remote **EVPN**. EVPN with local SOO `soo-2211`. |


Even if a remote side misconfigured EVPN on WAN, **import rejects all EVPN** — remote fabric EVPN never enters local `default`.

### 2.4 Tags and SOO (WAN loop avoidance)


| Mark                    | Purpose                                                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `tag-10` / `tag-20`     | Applied on WAN **import**; opposite side **export** rejects routes bearing that tag → prevents re-export loops across redundant WAN links. |
| `soo-1122` / `soo-2211` | Added on WAN **export**; same-site SOO rejected on WAN **import** EVPN path.                                                               |


Tag sets: `services/dci-policies/tagsets/` (on cluster; apply via policy CRs referencing `tag-10` / `tag-20`).

### 2.5 RIC control plane separation

`RouterInterconnect` uses `controlPlane: IPVPN` — stitch leak between `router-*` and `default` is VPNv4-oriented on the WAN NI, not raw fabric EVPN re-advertisement.

**Summary:** Fabric system/VTEP reachability stays on **EVPN/VXLAN inside each DC**. WAN carries **VPNv4 stitch prefixes only**, with **DCGW system IPs** as next-hop, enforced by AFI disable + policy reject/accept rules.

---



## 3. End-to-end paths



### vnet-1 (spoke) ↔ vnet-2 (hub)

```
client-1 (101.1) → leaf-1 router-1 [EVPN/VXLAN]
  → dcgw-1 router-1 ──RIC IPVPN RT 100──► dcgw-1 default
  → WAN VPNv4/MPLS/LDP ──► dcgw-3 default
  → RIC multi-rt-import ──► dcgw-3 router-2
  → leaf-5/8 router-2 [EVPN/VXLAN] → client-3/4 (201.x)
```



### vnet-5 (spoke) ↔ vnet-2 (hub)

Same WAN path; vnet-5 uses stitch RT **102** on export; hub RIC imports **100 + 102** via `multi-rt-import` and community set `vpn-import-rts`.

---



## 4. Policy map — what is applied where



### Layer A — RouterInterconnect (RIC)


| CR                           | Router     | Control | Export         | Import                          | File                              |
| ---------------------------- | ---------- | ------- | -------------- | ------------------------------- | --------------------------------- |
| `router-interconnect-vnet-1` | `router-1` | IPVPN   | `target:1:100` | `target:1:101`                  | `router-interconnect-vnet-1.yaml` |
| `router-interconnect-vnet-2` | `router-2` | IPVPN   | `target:1:101` | `importPolicy: multi-rt-import` | `router-interconnect-vnet-2.yaml` |
| `router-interconnect-vnet-5` | `router-3` | IPVPN   | `target:1:102` | `target:1:101`                  | `router-interconnect-vnet-5.yaml` |


Hub import policy `multi-rt-import` matches community set `vpn-import-rts` (`100`, `102`). Spokes use **targets only** (import hub RT `101`).

### Layer B — DefaultBGPPeer (WAN) — **live policies**


| Policy                           | Attached to                      | Role                                         |
| -------------------------------- | -------------------------------- | -------------------------------------------- |
| `export-dc-1-routes-and-add-soo` | `dcgw-1-dcgw-3`, `dcgw-2-dcgw-4` | Export stitch VPNv4 RT 100 + 102 + SOO       |
| `export-dc-2-routes-and-add-soo` | `dcgw-3-dcgw-1`, `dcgw-4-dcgw-2` | Export stitch VPNv4 RT 101 + SOO             |
| `import-dci-services-dc-1`       | DC1 WAN peers                    | Import hub VPNv4 RT 101; reject EVPN         |
| `import-dci-services-dc-2`       | DC2 WAN peers                    | Import spoke VPNv4 RT 100 + 102; reject EVPN |


Peer patches: `services/dci-policies/bgp-peers/dcgw-*-import-vpn-patch.json` (policy lists + VPNv4 enable).

### Layer C — Community sets (live)


| Name                      | Members        | Used by                                                                             |
| ------------------------- | -------------- | ----------------------------------------------------------------------------------- |
| `dci-rt-dc1-l3`           | `target:1:100` | WAN export/import; vnet-1 RIC                                                       |
| `dci-rt-dc2-l3`           | `target:1:101` | WAN export/import; hub RIC export                                                   |
| `dci-rt-vnet-5-stitch`    | `target:1:102` | WAN export/import; vnet-5 RIC                                                       |
| `vpn-import-rts`          | `100`, `102`   | Hub RIC `multi-rt-import`                                                           |
| `soo-1122` / `soo-2211`   | origin SOO     | WAN export add / import EVPN reject                                                 |
| `dci-rt-hub-spoke-import` | `100`, `102`   | Used only by unused draft policy `import-dci-hub-spoke-stitch` (not in production) |


Files: `services/dci-policies/communitysets/`

### Layer D — Policies defined but **not** attached to live interconnects


| Policy                                         | Notes                                                    |
| ---------------------------------------------- | -------------------------------------------------------- |
| `import-dci-hub-spoke-stitch`                  | Draft / EVPN-lab only — **not attached** in production   |
| `export-dci-stitch-*`, `import-dci-hub-stitch` | EVPN control-plane stitch (`eda-dci-evpn-lab` trial)     |
| `export-wan-routes-only-dc-*`                  | Legacy primary-link model                                |
| `darren-*`                                     | Trial copies on cluster                                  |




### Layer E — VirtualNetwork IRB (fabric host routes)

Patch **vnet-1**, **vnet-2**, **vnet-5** for EVPN type-2 IP+MAC and host route populate:

`services/dci-policies/patches/vnet-irb-evpn-hostroutes-patch.json`

---



## 5. WAN MPLS / LDP validation

Stitch prefixes are **BGP VPNv4** across WAN. MPLS binds to **BGP next-hop** (remote DCGW system IP `/32`), not the stitch `/24` directly.


| DCGW   | System IP   | Remote WAN peer |
| ------ | ----------- | --------------- |
| dcgw-1 | `11.0.0.7`  | `11.0.0.15`     |
| dcgw-3 | `11.0.0.15` | `11.0.0.7`      |


```bash
docker exec dcgw-1 sr_cli 'show network-instance default protocols bgp routes l3vpn-ipv4-unicast summary'
docker exec dcgw-1 sr_cli 'show network-instance default protocols ldp ipv4 fec'
docker exec dcgw-1 sr_cli 'show network-instance default tunnel-table'
docker exec dcgw-1 sr_cli 'ping network-instance default 11.0.0.15 -c 3'
```

**Pass:** Remote stitch prefix in VPNv4 RIB, NH = remote DCGW system IP; LDP FEC `Used in Forwarding: true` for that `/32`.

### End-to-end ping (`eth1`)

```bash
docker exec client-1-vnet-1-dc1 ping -c 3 172.16.201.1
docker exec client-3-vnet-2-dc2 ping -c 3 172.16.101.1
docker exec client-5-vnet-5-dc1 ping -c 3 172.16.201.1
docker exec client-3-vnet-2-dc2 ping -c 3 172.16.151.1
```

---



## 6. Apply order

```bash
bash ~/eda-dci-lab/scripts/apply-dci-policies.sh   # community sets, WAN policies, peer patches
bash ~/eda-dci-lab/scripts/apply-l3-dci.sh       # RIC + multi-rt-import
bash ~/eda-dci-lab/scripts/apply-vnet-5-hub-spoke.sh  # vnet-5 spoke + WAN RT 102 refresh
```

Or: `bash ~/eda-dci-lab/scripts/apply-all.sh`

---



## 7. Status

| Item | Status |
| ---- | ------ |
| vnet-1 ↔ vnet-2 | **Working** |
| vnet-5 ↔ vnet-2 hub-spoke | **Working** |
| Hub RIC import | **`multi-rt-import`** + `vpn-import-rts` (`100`, `102`) |
| Fabric EVPN / system/VTEP on WAN | **Blocked** (AFI + policy) |
| EVPN control plane DCI trial | **Separate repo** `eda-dci-evpn-lab` — production stays IPVPN on RIC |

**EDA reconcile:** After `kubectl apply`, confirm `running-version` matches CR spec and no `failed-transaction` annotation before treating a change as deployed. EDA UI shows **running** config on the SRL nodes, not just CR intent.
