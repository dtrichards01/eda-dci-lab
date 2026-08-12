# L3 VPN DCI — policy map, address families, and WAN MPLS validation

**Namespace:** `clab-srl-leaf-spine-dcgw`  
**Validated:** vnet-1 ↔ vnet-2 hub, vnet-5 ↔ vnet-2 hub-spoke (bidirectional `eth1` ping)  
**Last updated:** 2026-08-04

Companion docs: `DCI-ALIGNMENT.md` (service model), `CLAB-VALIDATION.md` (topology).

This document is the **authoritative policy map**: which routing policies and community sets are applied on which objects, why, and how fabric control-plane noise (leaf system IPs, VTEPs, EVPN routes) is kept off the WAN.

---

## Lab / demo vs production

This repository describes a **CLAB + Talos EDA lab** design. It is suitable for **demonstration, learning, and controlled validation** — not as a blanket production reference architecture.

| Path | Lab / demo | Production recommendation |
|------|------------|---------------------------|
| **L3 hub-spoke** (IPVPN RIC + VPNv4 WAN) | **Validated** in this lab (`vnet-1` / `vnet-5` ↔ `vnet-2`) | Reasonable **lab demo** of DCI L3 stitch. For production, require Nokia EDA/SRL release notes, scale/security review, and your org’s change controls — do not deploy from this repo without vendor and internal sign-off. |
| **L2 cross-DC** (BDI + hybrid WAN EVPN type-2/3) | **Documented and demoable** (`vnet-3` ↔ `vnet-4`); end-to-end stitch may still need tuning | **Not recommended for production.** Enabling `l2VPNEVPN` on WAN peers increases exposure; isolation depends on policy discipline (RT 300/301 only). Prefer vendor-validated L2 DCI patterns and separate WAN policy review before any production use. |
| **L3 EVPN RIC** (`eda-dci-evpn-lab` trial) | Experimental; EDA reconcile issues observed | **Not for production.** Await EDA/platform fixes for EVPN control plane on `RouterInterconnect`. |

**Summary:** You can demo **both L2 and L3** with the current hybrid WAN policies on the same peers, but we **do not recommend** treating this combined L2+L3 WAN model as production-ready. Production L3 should stay on the validated **IPVPN RIC + VPNv4-only WAN** pattern until L2 WAN EVPN and/or EVPN L3 RIC are explicitly validated for your release and risk profile.

---

## 1. Why two transports and three BGP address families

Cross-DC L3 uses **different control planes on different legs**. That is intentional.


| Leg                                               | Network instance        | Encapsulation | BGP AFI / control                        | Why                                                                                                                 |
| ------------------------------------------------- | ----------------------- | ------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **Fabric** (leaf ↔ spine ↔ DCGW)                  | `router-1` / `router-2` | VXLAN         | **EVPN**                                 | L3 IRB on fabric: EVPN type-2 (MAC-IP) and type-5 (IP prefix). NH = local leaf/DCGW VTEP. |
| **RIC stitch** (service NI ↔ WAN NI on same DCGW) | `router-`* ↔ `default`  | MPLS / LDP    | **IPVPN** (`controlPlane: IPVPN` on RIC) | EDA leaks stitch RTs between service router and interconnect BGP instance.                                          |
| **WAN** (DCGW ↔ DCGW)                             | `default`               | MPLS / LDP    | **VPNv4** + **EVPN** (hybrid)            | L3: stitch prefixes (RT 100/101/102) via VPNv4. L2: EVPN type-2/3 only (RT 300/301). Fabric EVPN blocked by policy. |


---



## 2. Restricting fabric / system addresses from the WAN

**Goal:** Remote DC fabric must not learn local leaf loopbacks, VTEP addresses, or arbitrary fabric EVPN routes across the DCI WAN. **L3:** only stitch service prefixes (`101/24`, `201/24`, `151/24`) via VPNv4. **L2:** only EVPN type-2 (MAC) and type-3 (IMET) with stitch RTs `300`/`301` — see `docs/L2-DCI-GUIDE.md`.

**Problem if unrestricted:** With unrestricted EVPN on WAN peers, BGP EVPN carries routes whose next-hop is a **remote leaf VTEP** or fabric EVPN types beyond L2 stitch. MPLS/VXLAN would then try to reach fabric internals over the WAN — wrong encapsulation, broken forwarding, and security/scale issues.

**Mechanisms (layered):**

### 2.1 WAN BGP address families (`DefaultBGPPeer`)

| AFI              | Enabled   | Effect                                                                                                                    |
| ---------------- | --------- | ------------------------------------------------------------------------------------------------------------------------- |
| `ipv4Unicast`    | **false** | No plain BGP IPv4 on WAN (underlay uses OSPF in `default`).                                                               |
| `l2VPNEVPN`      | **true**  | EVPN on WAN — **only** L2 stitch type-2/3 with RT 300/301 allowed by policy (not fabric EVPN).                            |
| `vpnIPv4Unicast` | **true**  | MPLS VPN-IPv4 for L3 stitch prefixes (RT 100/101/102).                                                                  |

EVPN AFI enabled via `services/dci-policies/bgp-peers/wan-enable-evpn-patch.json` (`apply-l2-wan-evpn.sh`). L3 VPNv4 unchanged.

`nextHopSelf: true` on WAN peers rewrites exported VPNv4 next-hop to the **local DCGW system IP** (`11.0.0.7`, `11.0.0.15`, …), not a fabric VTEP.

### 2.2 WAN export policies (outbound from each DC)

Default action: **Reject**. L3 VPNv4 and L2 EVPN stitch matches are explicit; all other EVPN rejected.

| Policy | Peers | L3 (VPNv4) | L2 (EVPN) |
| ------ | ----- | ---------- | --------- |
| `export-dc-1-prefixes-and-add-soo` | `dcgw-1-dcgw-3` | RT 100 + 102 + SOO | type-2/3 RT **300** + SOO |
| `export-dc-1-routes-and-add-soo` | `dcgw-2-dcgw-4` | RT 100 + 102 + SOO | type-2/3 RT **300** + SOO |
| `export-dc-2-routes-and-add-soo` | `dcgw-3-dcgw-1`, `dcgw-4-dcgw-2` | RT 101 + SOO | type-2/3 RT **301** + SOO |

Each policy rejects imported routes tagged `tag-20`/`tag-10`, then accepts L2 EVPN **before** `reject-all-local-evpn`.

### 2.3 WAN import policies (inbound to each DC)

| Policy | Peers | L3 (VPNv4) | L2 (EVPN) |
| ------ | ----- | ---------- | --------- |
| `import-dci-services-dc-1` | DC1 WAN | RT 101 (hub) | type-2/3 RT **301** |
| `import-dci-services-dc-2` | DC2 WAN | RT 100 + 102 (spokes) | type-2/3 RT **300** |

L2 accept statements run **before** `reject-all-remote-evpn`. All other remote EVPN rejected.

### 2.4 Tags and SOO (WAN loop avoidance)


| Mark                    | Purpose                                                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `tag-10` / `tag-20`     | Applied on WAN **import**; opposite side **export** rejects routes bearing that tag → prevents re-export loops across redundant WAN links. |
| `soo-1122` / `soo-2211` | Added on WAN **export**; same-site SOO rejected on WAN **import** EVPN path.                                                               |


Tag sets: `services/dci-policies/tagsets/` (on cluster; apply via policy CRs referencing `tag-10` / `tag-20`).

### 2.5 RIC control plane separation

`RouterInterconnect` uses `controlPlane: IPVPN` — stitch leak between `router-*` and `default` is VPNv4-oriented on the WAN NI, not raw fabric EVPN re-advertisement.

**Summary:** Fabric system/VTEP reachability stays on **EVPN/VXLAN inside each DC**. WAN carries **VPNv4 L3 stitch** plus **selective EVPN L2 stitch** (type-2/3, RT 300/301), with **DCGW system IPs** as L3 next-hop, enforced by AFI + policy accept/reject rules. Full L2 map: `docs/L2-DCI-GUIDE.md`.

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

**SROS note:** that multi-member All pattern does **not** OR-match on SROS (All = AND; `Any` rejected). SROS hub uses `import-ric-vnet-2` with **one CommunitySet per RT** — see `eda-dci-sros-lab`.

### Layer B — DefaultBGPPeer (WAN) — **live policies**

| Policy | Attached to | Role |
| ------ | ----------- | ---- |
| `export-dc-1-prefixes-and-add-soo` | `dcgw-1-dcgw-3` | L3 VPNv4 RT 100+102 + L2 EVPN type-2/3 RT 300 + SOO |
| `export-dc-1-routes-and-add-soo` | `dcgw-2-dcgw-4` | Same as above |
| `export-dc-2-routes-and-add-soo` | `dcgw-3-dcgw-1`, `dcgw-4-dcgw-2` | L3 VPNv4 RT 101 + L2 EVPN type-2/3 RT 301 + SOO |
| `import-dci-services-dc-1` | DC1 WAN peers | Import hub VPNv4 RT 101; L2 EVPN type-2/3 RT 301; reject other EVPN |
| `import-dci-services-dc-2` | DC2 WAN peers | Import spoke VPNv4 RT 100+102; L2 EVPN type-2/3 RT 300; reject other EVPN |

Peer patches: `bgp-peers/dcgw-*-import-vpn-patch.json` (policy names + VPNv4). EVPN AFI: `wan-enable-evpn-patch.json` via `apply-l2-wan-evpn.sh`.

### Layer C — Community sets (live)


| Name                      | Members        | Used by                                                                             |
| ------------------------- | -------------- | ----------------------------------------------------------------------------------- |
| `dci-rt-dc1-l3`           | `target:1:100` | WAN export/import; vnet-1 RIC                                                       |
| `dci-rt-dc2-l3`           | `target:1:101` | WAN export/import; hub RIC export                                                   |
| `dci-rt-vnet-5-stitch`    | `target:1:102` | WAN export/import; vnet-5 RIC                                                       |
| `dci-rt-l2-export-dc1`    | `target:1:300` | L2 WAN export (DC1)                                                                 |
| `dci-rt-l2-export-dc2`    | `target:1:301` | L2 WAN export (DC2)                                                                 |
| `dci-rt-l2-import-dc1`    | `target:1:301` | L2 WAN import (DC1)                                                                 |
| `dci-rt-l2-import-dc2`    | `target:1:300` | L2 WAN import (DC2)                                                                 |
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

**Multi-leaf same subnet:** when hosts span multiple leaves on the **same** L2/L3 subnet, IRB `hostRoutePopulate` / related EVPN host-route settings are **required** for host-route advertisement between leaves. Single-leaf-per-subnet + type-5 stitch designs may disable host routes by choice — that is a different topology.

**Do not confuse with GBP:** on SROS, loopback OK + client FAIL with 0 packets on the remote host was **MSG/GBP**, not missing IRB host routes. Keep that golden rule; this note is only for multi-leaf same-subnet host reachability.

**Loopback Interface trap (EDA Interfaces app):** `type: Loopback` CRs allow **one member only**. Multi-member is rejected (`more than one members are provided for type [loopback]`). Anycast `/32` on another leaf → separate single-member Interface + second VirtualNetwork `routedInterfaces` entry.

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
bash ~/eda-dci-lab/scripts/apply-dci-policies.sh   # L3 WAN policies + VPNv4 on peers
bash ~/eda-dci-lab/scripts/apply-l2-wan-evpn.sh    # L2 EVPN on WAN + hybrid policy refresh
bash ~/eda-dci-lab/scripts/apply-l3-dci.sh         # RIC + multi-rt-import
bash ~/eda-dci-lab/scripts/apply-l2-dci.sh       # BDI + edges (calls apply-l2-wan-evpn)
bash ~/eda-dci-lab/scripts/apply-vnet-5-hub-spoke.sh
```

Or: `bash ~/eda-dci-lab/scripts/apply-all.sh`

---



## 7. Status

| Item | Status |
| ---- | ------ |
| vnet-1 ↔ vnet-2 | **Working** |
| vnet-5 ↔ vnet-2 hub-spoke | **Working** |
| Hub RIC import | **`multi-rt-import`** + `vpn-import-rts` (`100`, `102`) |
| Fabric EVPN / system/VTEP on WAN | **Blocked** (policy — only L2 stitch type-2/3 RT 300/301 allowed) |
| L2 vnet-3 ↔ vnet-4 | **Hybrid WAN EVPN** + BDI — see `docs/L2-DCI-GUIDE.md` |
| EVPN control plane DCI trial | **Separate repo** `eda-dci-evpn-lab` — production stays IPVPN on RIC |

**EDA reconcile:** After `kubectl apply`, confirm `running-version` matches CR spec and no `failed-transaction` annotation before treating a change as deployed. EDA UI shows **running** config on the SRL nodes, not just CR intent.
