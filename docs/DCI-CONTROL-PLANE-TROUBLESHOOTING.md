# DCI control-plane troubleshooting (EVPN vs IPVPN)

Short tech note for **SRL** (`eda-dci-lab`) and **SROS** (`eda-dci-sros-lab`) DCGW labs.

**Before this note:** if TargetNodes are Ready but fabrics/interfaces are Down, restore missing CLAB dataplane veths (`sudo clab deploy -t <live-topo>`, no `--reconfigure`) — do not start at RIC/WAN policy. See lab README / skill **eda-branch**.

| Lab | Namespace | DCGW names | Typical RIC |
|-----|-----------|------------|-------------|
| SRL | `clab-srl-leaf-spine-dcgw` | `dcgw-1`…`dcgw-4` | **IPVPN** |
| SROS | `clab-3-tier-leaf-spine-dcgw` | `dc-gw-1`…`dc-gw-4` | **EVPN** or **IPVPN** (mode switch) |

Sibling copy: `eda-dci-sros-lab/docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` (keep in sync).

**SRL vs SROS DCGW RIB / wrong leaf VTEP NH:** `docs/SRL-vs-SROS-DCGW-RIB.md` (not an ISIS vs OSPF difference). **WAN IGP option 1 vs 2:** `docs/DCI-OPTIONS.md`.

---

## 1. Decision tree — which control plane?

```
What is RouterInterconnect.interconnectBGPInstance.controlPlane?
├─ IPVPN  → WAN should use vpnIPv4 / VPNv4 policies (IPVPN mode)
└─ EVPN   → WAN should use l2VPNEVPN / EVPN stitch policies (EVPN mode)

What is enabled on DefaultBGPPeer?
├─ vpnIPv4Unicast only  → attach IPVPN import/export pair
├─ l2VPNEVPN only       → attach EVPN import/export pair
└─ both / mixed          → avoid dual-mixed Policies; split peers or pick one mode
```

**Do not mix EVPN + IPVPN match statements in one Policy** (SROS lesson). Use mode-specific pairs. Best Practice, keep them separate

### Policies to attach (SROS)

| Mode | DC1 | DC2 |
|------|-----|-----|
| EVPN | `import-dci-evpn-dc-1` / `export-dci-evpn-dc-1` | `import-dci-evpn-dc-2` / `export-dci-evpn-dc-2` |
| IPVPN | `import-dci-ipvpn-dc-1` / `export-dci-ipvpn-dc-1` | `import-dci-ipvpn-dc-2` / `export-dci-ipvpn-dc-2` |

Peer fields: `importPolicies` / `exportPolicies`. See SROS `services/dci-policies/wan/README.md`.

### Policies (SRL — this lab)

| Role | Examples |
|------|----------|
| Import | `import-dci-services-dc-1` / `import-dci-services-dc-2` |
| Export | `export-dc-*-routes-and-add-soo`, `export-wan-routes-only-dc-*` |
| Fabric block | `reject-all-local-evpn` / `reject-all-remote-evpn` **required** |

Match protocol: **`BGP_IPVPN`**. Full map: `docs/L3VPN-DCI-GUIDE.md` §2.

---

## 2. Where to look on the DCGW

| Layer | What | Where |
|-------|------|--------|
| Fabric | Leaf/spine EVPN-VXLAN | Inside DC; VTEPs / system IPs |
| Service VRF | Customer / stitch prefixes | SRL: `network-instance router-*` · SROS: `service vprn "router-*"` |
| Interconnect (RIC) | Leak service ↔ WAN | Same DCGW; RT targets on RIC CR |
| WAN BGP | DCGW ↔ DCGW | **default / Base** NI + `DefaultBGPPeer` |

### SRL checkpoints

| Check | Expect |
|-------|--------|
| WAN EVPN | **No** remote leaf/spine system IPs (`reject-all-*-evpn`) |
| WAN VPNv4 | Stitch prefixes; NH = **remote DCGW system IP** |
| Fabric | EVPN/VXLAN stays site-local |

### SROS checkpoints

| Check | Expect |
|-------|--------|
| VPRN route-table | Local often **EVPN-IFL**; remote WAN often **BGP VPN** |
| Base vpn-ipv4 / EVPN | Matches peer AFI and mode policies |
| `allow-export-bgp-vpn` | Conditional on **EVPN RIC**; usually unset for **IPVPN RIC** |
| Policy | No `families:[IPv4]` for vpn-ipv4; SROS CommunitySet is **All-only** (EDA rejects `Any`) → one Accept per single-RT set; Policy uses **`statements`** |
| SROS hub import | Do **not** copy SRL multi-member `vpn-import-rts`; use one set/Accept per RT (`import-ric-vnet-2`) |
| Client FAIL / loopback OK | **MSG/GBP** before IRB |
| Multi-leaf same subnet | Enable IRB `hostRoutePopulate` / related EVPN host-route params when hosts span multiple leaves on one subnet (fabric host reachability; orthogonal to GBP) |
| Loopback Interface | **One member only** per CR; multi-member rejected by Interfaces app |

---

## 3. Validate MPLS vs VXLAN

| Domain | Transport | Confirm |
|--------|-----------|---------|
| **Fabric** | **VXLAN** | VTEP NH, EVPN routes, VXLAN tunnels |
| **WAN** | **MPLS / SR-ISIS** (live) or **LDP** (option 1) | Stitch via VPNv4/EVPN; NH = DCGW system `/32`; TTM `sr-isis` (or LDP FEC) |

**Pass:** VPNv4 (or WAN EVPN stitch) with NH = remote DCGW; **SR-ISIS** (live) or LDP used in forwarding to that `/32`.  
**Fail:** remote leaf VTEP/system IPs appear on WAN (SRL fabric leak).

---

## 4. Command cheat sheet

### SRL (`sr_cli`) — primary for this repo

```bash
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols bgp neighbor'
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols bgp routes l3vpn-ipv4-unicast summary'
docker exec dcgw-1 sr_cli -e 'show network-instance default tunnel-table'
docker exec dcgw-1 sr_cli -e 'info from state network-instance default tunnel-table ipv4'
docker exec dcgw-1 sr_cli -e 'info from state network-instance default protocols isis instance isis-instance-1 segment-routing mpls sid-database'
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols isis adjacency'
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols ldp ipv4 fec'
docker exec dcgw-1 sr_cli -e 'show network-instance router-1 route-table ipv4-unicast'
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols bgp neighbor <ip> advertised-routes evpn summary'
docker exec dcgw-1 sr_cli -e 'show network-instance default protocols bgp neighbor <ip> received-routes evpn summary'
```

Live WAN (2026-09-04) is **SR-ISIS**, not LDP. Full table + YANG→EQL hints: `docs/SRL-DCI-WAN-IGP-Tech-Note.md` §7.

### SROS (classic)

```text
show router bgp routes vpn-ipv4
show router bgp routes evpn
show router "router-1" route-table
show router tunnel-table
show router ldp bindings
```

---

## 5. Quick isolation order

1. RIC `controlPlane` + peer AFI agree.
2. Correct Policy pair attached.
3. Service route-table + WAN RIB.
4. NH = DCGW system → **SR-ISIS** tunnel (live) or LDP (option 1) (MPLS).
5. SROS client FAIL: GBP/MSG before IRB.
6. Multi-leaf hosts on same subnet: confirm IRB host-route populate (separate from GBP).
7. Loopback Interface: one member per CR — does not support multi-member.

### EQL / YANG state paths (verified on mixed SROS+SRL fabric lab, 2026-08-12)

**Roots:** SRL `.namespace.node.srl.*` · SROS `.namespace.node.sros.state.*`. Autocomplete: `?query=<path.>`.

| What | SRL EQL | SROS EQL / CLI fallback |
|------|---------|-------------------------|
| IP RIB/FIB | `...network-instance.route-table.ipv4-unicast.route` | Base `...state.router.route-table.unicast.ipv4.route` · VPRN `...state.service.vprn.route-table.unicast.ipv4.route` |
| EVPN type-5 | `...bgp-rib.afi-safi.evpn.{local-rib,rib-in-out.rib-in-post,rib-out-post}.ip-prefix-route` | No per-route EVPN in EQL → CLI `show router bgp routes evpn`; peer counts via `family-prefix.evpn` |
| EVPN type-2 | `...bgp-rib.afi-safi.evpn.*.mac-ip-route` | VPLS FDB `...state.service.vpls.fdb.mac` |
| MAC table | `...bridge-table.mac-table.mac` | same VPLS FDB path |
| VPNv4 / L3VPN | CLI `show network-instance default protocols bgp routes l3vpn-ipv4-unicast` (SRL IPVPN lab); AFI may be absent on fabric-only leaves | Peer `family-prefix.vpn-ipv4` + CLI `show router bgp routes vpn-ipv4` |
| LDP / SR-ISIS / tunnel | VXLAN VTEP `...srl.tunnel.vxlan-tunnel.vtep`; WAN TTM `...network-instance.tunnel-table.ipv4.tunnel` (`type`=`sr-isis` live; `ldp` when option 1); ISIS SID `...protocols.isis.instance.segment-routing.mpls.sid-database.prefix-sid` | `...state.router.ldp.bindings.active.prefixes` (+ nested `.in-label` / `.out-label`, leaf `label`) · `...tunnel-table.ipv4.tunnel` |

Related: `docs/L3VPN-DCI-GUIDE.md`, `docs/L2-DCI-GUIDE.md`, sibling SROS `docs/SROS-EVPN-DCI-GUIDE.md`.
