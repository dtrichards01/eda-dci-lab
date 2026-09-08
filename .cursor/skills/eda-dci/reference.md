# EDA DCI reference

SRL vs SROS policy tables. **Env URLs / 26.8.1 instances:** [eda/26.8.1-changes.md](../eda/26.8.1-changes.md) (#2 Talos `.55` for SRL DCI + k0r4 3-site; #3 WSL `:9443` for SROS EVPN). **EVPN on 7220 IXR-H5 TH** (Kind #1 `clab-h5-2x2`): [eda/h5-th-evpn.md](../eda/h5-th-evpn.md) — first L2 VXLAN on Tomahawk H5 (2026-09-03). **RoCEv2/DCQCN QoS:** [eda/qos-rocev2.md](../eda/qos-rocev2.md). This file has no 26.4 UI URLs. **Use-case catalog (share):** `eda-dci-lab/docs/DCI-OPTIONS.md` §2.

## SRL (eda-dci-lab) vs SROS (eda-dci-sros-lab)

| Topic | SRL `eda-dci-lab` | SROS `eda-dci-sros-lab` |
|-------|-------------------|-------------------------|
| Namespace | `clab-srl-leaf-spine-dcgw` | `clab-3-tier-leaf-spine-dcgw` |
| DCGW nodes | `dcgw-1`…`dcgw-4` | `dc-gw-1`…`dc-gw-4` (BGP CRs: `dcgw-*`) |
| RIC `controlPlane` | `IPVPN` | `EVPN` |
| RT format | `target:1:100` | `target:100:100` |
| VPN match | `protocol: BGP_IPVPN` | `BGP_VPN` + **one CommunitySet / Accept per RT**. SROS `matchSetOptions` = **All only** (EDA rejects `Any`). Multi-member All = AND. Policy CR uses **`statements`** (not `statement`). Never `BGP_IPVPN` / `families:[IPv4]` for vpn-ipv4. |
| Hub RIC import | Often `multi-rt-import` + multi-member `vpn-import-rts` | **`import-ric-vnet-2`** + `vpn-import-rt-100` / `vpn-import-rt-102`; `exportTarget: 101:101`. Do not use multi-member All for OR. |
| Fabric EVPN on WAN | **Must** block (`reject-all-local-evpn` **egress**, `reject-all-remote-evpn` **ingress`). Else GRT fills with remote leaf `/32`s as **BGP** and stitch NH can become a **leaf VTEP**. Not an ISIS/OSPF issue. Canonical: `eda-dci-lab/docs/SRL-vs-SROS-DCGW-RIB.md` | Not required — platform does not leak fabric EVPN to WAN. GRT has local fabric + remote DCGW only |
| WAN underlay (Talos SRL, 2026-09-04) | **Live IS-IS + SR-ISIS** (RIC MPLS). Option 1 OSPF+LDP restore. Index: `eda-dci-lab/docs/DCI-OPTIONS.md`. CLI/YANG: `docs/SRL-DCI-WAN-IGP-Tech-Note.md` §7 | Lab-specific; do not copy SRL ISIS CRs |
| L3 stitch | VPNv4 on WAN | Dual: local **EVPN-IFL**, remote **BGP VPN**. `allow-export-bgp-vpn` often needed for **EVPN** RIC; usually **not** for **IPVPN** RIC (auto EVPN↔IPVPN when both instances present) |


## Stitch RT map (SROS lab)

| VNet | Interconnect | Stitch RT |
|------|--------------|-----------|
| vnet-1 (L3 DC1) | RouterInterconnect | `target:100:100` |
| vnet-2 (L3 DC2 hub) | RouterInterconnect | `target:101:101` |
| vnet-5 (spoke DC1) | RouterInterconnect | `target:102:102` |
| vnet-3 (L2 DC1) | BridgeDomainInterconnect | export `300:300`, import remote `301:301` |
| vnet-4 (L2 DC2) | BridgeDomainInterconnect | export `301:301`, import remote `300:300` |

SOO: `soo-1122` (DC1), `soo-2211` (DC2). Tags: `tag-10`, `tag-20`.

## Anycast VTEP (MAC-VRF MH) vs BridgeDomainInterconnect — 26.8.1

**Anycast VTEP is not a BDI knob.** `BridgeDomainInterconnect` / `RouterInterconnect` stay v2 with no `vtep` / `anycast` fields. The 26.8.1 feature is EVPN Anycast Multi-homing on **access ESI LAGs**, L2 (mac-vrf) only; L3 is future.

| Item | 26.8.1 fact |
|------|-------------|
| CRD | `Interface.spec.lag.multihoming.vtep.mode` = `Unicast` (default) \| `Anycast`; `anycastIPv4Pool` required for Anycast |
| Consumers | `BridgeInterface` / `VLAN` (MAC-VRF). Not BDI, not RIC, not IRB |
| New CR | `DefaultLoopbackInterface` (`routing.eda.nokia.com/v1`) — derived `avtep-{local}-{others…}` on `loopback-255` (`lo255`) |
| OS | **SRL 26.7.1+ only**. SROS: no. 7220 H5/Dx; 7250 IXR ingress-only. **H5 L2 EVPN VXLAN validated 2026-09-03** on Kind #1 `h5-2x2` (TH-32D) — [h5-th-evpn.md](../eda/h5-th-evpn.md) |
| MH rules | `AllActive`; `dfElection` `HighestPreference` or unset. One anycast IPv4 per **node-set** (shared across ESes on that exact set). Changing ES members reallocates the IP (brief outage) |
| Prep | User must create Interface CRs named **`loopback-255`** on participating leaves first (CE loop-detection blocks auto-create from Interfaces/Fabrics/Services) |
| Underlay | Fabrics eBGP export of local `/32` loopbacks (OSPF/IS-IS passive later). DCGWs must reach the anycast IP |

**BDI interaction:** lab BDI is a **second EVPN instance on DCGWs** (still **MPLS/LDP**, different RT/EVI). It does not allocate anycast VTEPs. Fabric VTEPs stay per-leaf system IPs unless the **access LAG** is `vtep.mode: Anycast`. Same BridgeDomain can mix anycast MH leaves + unicast DCGW stitch **only if DCGWs are not in that ES** and the anycast `/32` is in the fabric underlay. Do not put DCGW nodes in an Anycast ES.

**Lab check 2026-09-01:**

| Lab | BDI | Anycast VTEP |
|-----|-----|----------------|
| #3 WSL SROS `clab-3-tier-leaf-spine-dcgw` | `bridge-domain-interconnect-vnet-3` + `bridge-domian-interconnect-vnet-4` (**typo in name**) **Up**, MPLS, RT `300:300`/`301:301`. `bd-3` = leaf-2 only; `bd-4` = leaf-6 only | **N/A** — 0 LAG MH, 0 `DefaultLoopbackInterface`, SROS unsupported |
| #2 SRL git `eda-dci-lab` | `bd-interconnect-vnet-3/4` MPLS LDP, RT `target:1:300`/`1:301` | Same model: BDI does not turn on anycast; enable on leaf ESI LAG if you want it |

Do not copy `vtep` onto BDI YAML. 3-site MH LAGs (`eda-3-site-bl-spine`) are the candidate to *use* the knob; those are stretched EVPN, not DCGW BDI.

## WAN peer → policy (SROS mode-specific)

| Mode | Peer example | Import | Export |
|------|--------------|--------|--------|
| EVPN | `dcgw-1-dcgw-3` | `import-dci-evpn-dc-1` | `export-dci-evpn-dc-1` |
| EVPN | `dcgw-3-dcgw-1` | `import-dci-evpn-dc-2` | `export-dci-evpn-dc-2` |
| IPVPN | `dcgw-2-dcgw-4` | `import-dci-ipvpn-dc-1` | `export-dci-ipvpn-dc-1` |
| IPVPN | `dcgw-4-dcgw-2` | `import-dci-ipvpn-dc-2` | `export-dci-ipvpn-dc-2` |

**Do not use `*-dual` (obsolete).** Peer fields: **`importPolicies` / `exportPolicies`** (session-wide). No Policy annotations. `allow-export-bgp-vpn` conditional on EVPN RIC.

## SROS Policy `configuredName` vs RouterInterconnect (26.4.x–26.8.1)

Customer report (EDA 26.4.x / SROS 25.10): `BGPGroup` pushes the referenced Policy **`configuredName`** into nodeconfig; `RouterInterconnect` `importPolicy`/`exportPolicy` pushes the Policy **CR `metadata.name`**. If those differ, SROS gets a `policy-statement` under `configuredName` and a VPRN/VPN import/export under the CR name → missing and/or duplicate entries.

| Our #3 WSL lab (checked 2026-09-07) | Value |
|-------------------------------------|--------|
| EDA | **26.8.1** (not 26.4.x) |
| DCGW | SROS **26.3.r1** SR-1 (not 25.10) |
| Hub RIC | `importPolicy: import-ric-vnet-2` (live, Up). Spokes: targets only |
| WAN | `DefaultBGPPeer` `importPolicies`/`exportPolicies` (CR names) |
| Any Policy `configuredName` | **unset** on all CRs in `clab-3-tier-leaf-spine-dcgw` |

**Live test 2026-09-07 (EDA 26.8.1 / SROS 26.3.r1):** set `configuredName: IMPORT_RIC_VNET_2` on hub Policy `import-ric-vnet-2` (RIC `importPolicy` left as CR name). ConfigEngine txn **5103 FAILED**:

`MGMT_CORE #240: policy-statement[name=import-ric-vnet-2] - Entry has references - vprn router-2 bgp-evpn mpls vrf-import/policy`

Policy app tried to rename/delete the CR-named statement; RIC still holds `vrf-import policy ["import-ric-vnet-2"]`. Same split as 26.4.x; here SROS **rejects the commit** instead of leaving duplicates. Alarm `ReconcileFailure-…Policy-import-ric-vnet-2`; node kept the last working config. **Reverted** `configuredName` after the test. Do not set `configuredName` ≠ CR name on RIC-attached Policies.

## 26.8.1 per-AFI/SAFI BGP policies (limited support — Protocols)

Same Policy CRs, attached **per address family** instead of (or as well as) session-wide. Inheritance, most-specific wins:

**neighbor → group → instance** (`DefaultBGPPeer` overrides `DefaultBGPGroup` overrides `DefaultRouter.spec.bgp`).

| Level | Session-wide | Per AFI (examples) |
|-------|----------------|-------------------|
| Neighbor | `DefaultBGPPeer.spec.importPolicies` | `spec.l2VPNEVPN.importPolicies`, `spec.vpnIPv4Unicast.importPolicies`, `spec.ipv4Unicast.importPolicies` |
| Group | `DefaultBGPGroup.spec.importPolicies` | same AFI objects on the group |
| Instance | `DefaultRouter.spec.importPolicies` (leaking / default VRF) | `spec.bgp.l2VPNEVPN.importPolicies`, `spec.bgp.vpnIPv4Unicast.importPolicies`, … |

AFIs on default-VRF BGP: `ipv4Unicast`, `ipv6Unicast`, `l2VPNEVPN`, `vpnIPv4Unicast`, `vpnIPv6Unicast`, plus `rtc` on peer/group. Overlay `BGPPeer` / `Router.spec.bgp` only have IPv4/IPv6 unicast (no EVPN/VPN AFI on the VNET BGP object).

**Lab today:** WAN peers still use **session-wide** `importPolicies: [import-dci-evpn-dc-1]` with `l2VPNEVPN.enabled: true` and **no** per-AFI policy lists. Group `default-bgp-group-dc-1` only enables EVPN. This is the knob that would let **one** WAN session run EVPN + vpnIPv4 with **two** Policy CRs instead of mixing statements (the old `*-dual` trap). Limited-support — do not attach on SROS 26.3.R1 without an explicit ask.

**Not a Fabric CR split.** Fabric only has session-wide `overlayProtocol.bgp.importPolicies` / `underlayProtocol.bgp.importPolicies` (empty → Fabric auto-generates **one** policy per protocol: underlay vs overlay). No `l2VPNEVPN` / `vpnIPv4Unicast` policy fields on `Fabric`. Per-AFI attach is Protocols: `DefaultBGPPeer` / `DefaultBGPGroup` / `DefaultRouter.spec.bgp.<afi>`. WAN DCI peers are extra DefaultBGPPeers, not Fabric overlay.

**Fabric override (supported):** set those lists on the Fabric CR to your own Policy names — Nokia: *“If routing policies are defined independently of the Fabric through the importPolicies or exportPolicies properties, they will be used instead.”* Live `pod-1`/`pod-2` leave them empty (auto). Do **not** patch Fabric-owned DefaultBGPPeer/ISL/Policy children; they are not user CRs in this NS (kube only shows the four WAN `dcgw-*-bgp-peer`s). Unused lab Policies `import-policy-pod-pod` / `expor-policy-pod-to-pod` are the attach-your-own pattern, not currently referenced. Route leaking is a separate singular `importPolicy`/`exportPolicy`, overridable per role.

**eBGP UL+OL (still UL policies only).** Fabrics `bgp.py` (26.8 app): overlay `EBGP` adds `l2VPNEVPN` to the **same** ISL session / `bgpgroup-ebgp-{fabric}`. Group `importPolicies`/`exportPolicies` are taken only from `underlayProtocol.bgp` (or auto `ebgp-isl-*-policy-{fabric}`). Overlay lists are wired only for **iBGP** RR groups. AFI objects on that group are `enabled` only — Fabric never writes `l2VPNEVPN.importPolicies`. Auto-gen eBGP Policy is **one** CR with mixed BGP + EVPN-type statements. Option 4 YAML (`overlayProtocol.protocol: EBGP`, no overlay `bgp` block) is this model.

## 26.8.1 Policy: BGP next-hop match + RTM preference (limited support)

Live CRD `Policy` v1 (WSL 2026-09-01):

| Need | Field | Notes |
|------|--------|--------|
| Match BGP NEXT_HOP | `match.bgp.nextHop.ipAddress` **or** `.prefixSet` | Mutually exclusive. Not the same as `action.bgp.nextHop` (rewrite). |
| Set RTM / admin distance | `action.setRoutePreference` (1–255) | **Not** `action.bgp.setLocalPreference`. Nokia: **lower is better**. BGP default ~170. |

Example (unused CRs, not on WAN peers): `eda-dci-sros-lab/services/dci-policies/examples/26.8.1-bgp-nh-rtm-pref/`. DC2 NHs: dc-gw-3 `11.0.0.14`, dc-gw-4 `11.0.0.8`. Chain with `NextPolicy` in front of `import-dci-evpn-dc-1`. Do not attach without an explicit ask — SROS 26.3.R1 may no-op or Deviation.


## DCI connectivity debugging

### Prove control-plane vs datapath

### SRL CLI quirks (26.7, verified)

| Want | Command |
|------|---------|
| NI list | `docker exec leaf-1 sr_cli "show network-instance summary"` |
| Route table | `sr_cli "info from state network-instance router-1 route-table ipv4-unicast"` — the `show ... route-table ipv4-unicast` form is **rejected** in 26.7; `route` node needs all 4 keys so dump the whole subtree and grep |
| Subif / loopback binding | `sr_cli "show network-instance router-1 interfaces"` (plural) |
| EVPN type-5 RIB | `sr_cli "show network-instance default protocols bgp routes evpn route-type 5 prefix <p> detail"` |

SROS DCGWs: no `docker exec` CLI — `sshpass -p 'NokiaSros1!' ssh -tt admin@172.55.10.20{0,1,2,3}` (dc-gw-1..4 mgmt `172.55.10.200-203`), feed commands on stdin after `environment more false`. Config dump: `admin show configuration /configure service vprn "router-1"`. Service IDs differ per node — check `show service service-using` first (on dc-gw-1/2 `router-1` is **10003**, `router-3` is 10002).

SROS 3-site spines (`clab-3-site-bl-spine`): same — `docker exec <cid> sh` is Linux, not MD-CLI. `ssh admin@172.55.10.201` (spine-1) … `.206`. k0r4 has no `sshpass`; use ASKPASS. `ssh host 'show …'` fails (`exec request failed`); pipe into `-tt`. EVPN: `auto-disc`=T1, `mac`=T2, `incl-mcast`=T3, `eth-seg`=T4.

### SRL gNMI `:57410` stuck Connecting (clab WSL, 2026-08-22)

| Want | Command |
|------|---------|
| Who listens | `docker exec leaf-1 ss -lntp` (srbase) vs `ip netns exec srbase-mgmt ss -lntp` |
| Dual IP | `ip -4 addr` vs `ip netns exec srbase-mgmt ip -4 addr` — both have `172.55.10.100` |
| Prove setns | `python3 -c "import os,socket; fd=os.open('/var/run/netns/srbase-mgmt',0); os.setns(fd,0x40000000); s=socket.socket(); s.settimeout(3); s.connect(('127.0.0.1',57410)); print('ok')"` |
| Dual SYN-ACK | `tcpdump -nn -i mgmt0 tcp port 57410` — second `[S.]` with a different ISN |

**Abandoned:** proxy that `setns` then splices the **accepted client fd** in the same process — TLS works on loopback, host/EDA get RST. **Working:** `socketpair` so client splice stays in srbase + iptables DROP non-`lo` dport 57410 in `srbase-mgmt`. Details in **eda-dci** `SKILL.md`.

### Host CLAB missing dataplane veths (WSL 2026-08-27)

TargetNodes **Ready** after gNMI/edaboot recovery, but fabrics `pod-1`/`pod-2`, interfaces, BDs/vnets **Degraded/Down**. Cause: CLAB dataplane veths (`e1-1`… `altname clab-o-*`) missing from SRL `srbase`. Host `clab-stitch-…` ifaces still point at dead netns IDs. On-box: `oper-down-reason lower-layer-down`. SROS ISLs can already be Up.

**Abandoned:** `ip link set e1-*-0 up` (internal subif, not the CLAB cable). **Do not** `clab restart` healthy SRL or re-run `--post-rebuild`.

**Fix:** `sudo clab deploy -t /home/clab/3-tier-leaf-spine-s_spine/clab-s-spine-spine-leaf-sr-sim-srl.yaml` — `--dry-run` first (`added links` / `without node lifecycle action`); **no `--reconfigure`**. See **eda-branch**.

**Windows/PowerShell → WSL quoting:** heredocs break. Write the script to a Windows path, then `wsl bash -c "tr -d '\r' </mnt/c/.../q.sh >/tmp/q.sh; bash /tmp/q.sh"`.

| Test | From | Proves |
|------|------|--------|
| `ping 2.2.2.2 -I 1.1.1.1` (loopbacks) | `leaf-1 router-1` | DCI + stitch + remote service router |
| `ping 2.2.2.2` from client-1 | client eth1 | End-to-end including IRB/egress |
| Traceroute to remote client GW | local client | Where path stops |

**Asymmetric / client dataplane pattern (SROS WSL, 2026-08 — authoritative):** loopback OK (`1.1.1.1`↔`2.2.2.2`), same NHG for remote `/32` and `/24`, but client↔client FAIL and **0 packets** on remote host / leaf edge — **not** WAN BGP. Root cause: **`MicroSegmentationPolicy/red-blue-green`** with `serviceTargets.virtualNetworks: [vnet-1]` (GBP default deny). Fix: remove `vnet-1` from targets or disable that MS policy. Older notes about DC2↔DC1 asymmetry + IRB host routes alone are incomplete for this lab.

### Hub RIC import (SROS) — validated

| Item | Detail |
|------|--------|
| CommunitySets | `vpn-import-rt-100` (`100:100`), `vpn-import-rt-102` (`102:102`), each `matchSetOptions: All` |
| Policy | `import-ric-vnet-2` — two Accept statements; `defaultAction: Reject`; field **`spec.statements`** |
| RIC | `importPolicy: import-ric-vnet-2` + `exportTarget: target:101:101` (no `importTarget`) |
| Broken pattern | Multi-member `vpn-import-rts` with All → RIB-IN may show routes but **not installed** in hub VPRN; client5 GW `172.16.102.254` ICMP net unreachable to `101.x`/`151.x` while spokes still reach hub |

### "Why is my local loopback learned via BGP?" — DCGW re-origination echo (SROS lab, 2026-08)

Symptom: on leaf-1, NI `router-1` shows **two** entries for its own loopback `1.1.1.1/32` — `route-type host` (owner `net_inst_mgr`, pref 0, **active true**) and `route-type bgp-evpn` (owner `bgp_evpn_mgr`, pref 170, **active false**). Same shadow pair appears for `172.16.101.0/24` and local host routes.

Cause: the DC1 DCGWs (`dc-gw-1` 11.0.0.20, `dc-gw-2` 11.0.0.23) hold VPRN `router-1` with **two** bgp-evpn instances — `mpls 1` (WAN, `domain-id 65000:100`, RD `1.2.3.4:123`, import `101:101` / export `100:100`) and `vxlan 1` (fabric, `domain-id 65000:200`, `auto-rd` → `<system-ip>:10002`, vrf-target `target:1:100`). Every route in the VPRN route-table is re-originated out of **both** instances, so fabric-learned prefixes are advertised straight **back into the fabric** with the DCGW as next-hop.

Diagnostic — read the **D-PATH**, it tells you where the route came from:

| Prefix on leaf-1 | RD | D-PATH | Meaning |
|---|---|---|---|
| `1.1.1.1/32` | `11.0.0.20:10002` | `65000:200` only | local fabric echo — never left DC1 |
| `2.2.2.2/32` | `11.0.0.20:10002` | `65000:100` + `65001:201`, community `origin:65501:2211` | genuine DC2 route over the WAN |
| `1.1.1.1/32` | `11.0.0.4:100` | — (Originator-ID = self) | RR reflection from the DCGW-as-RR; dropped, status `-` |

**Benign** — SRL prefers pref 0 (host/local) over pref 170 (bgp-evpn), so the local route always wins and the EVPN copy stays `active false`. Confirms it is *not* a WAN re-import loop when the D-PATH lacks the WAN domain-id / remote SOO. `dc-gw-2` proves it: its `router-1` VPRN has **zero** WAN routes yet still advertises `1.1.1.1/32` back to leaf-1.

Note the DC1 DCGWs are also the **EVPN RRs** for pod-1 (leaf EVPN peers are `11.0.0.20`/`11.0.0.23` + `121::4`/`121::7`, group `ibgp-rrclient-pod-1`); the spines carry only eBGP IPv4/IPv6 underlay.

### Abandoned approaches

- Type-2 WAN fabric RT export/import when loopback test already passes
- SROS multi-member CommunitySet All for “OR” hub import; EDA `matchSetOptions: Any` on SROS; Policy `spec.statement` (singular — invalid)
- Copying SRL `multi-rt-import` + multi-member `vpn-import-rts` onto SROS unchanged
- Enabling IRB host route populate on DCI vnets while using type-5 stitch **when** the design is single-leaf-per-subnet stitch (not when multi-leaf hosts share a subnet — see multi-leaf note below)
- **Wrong conclusion (do not repeat):** attributing SROS client↔client recovery to IRB `hostRoutePopulate`/`evpnRouteAdvertisementType` `add` patches after a delayed retest — coincidence while **MSG/GBP on vnet-1** was the real blocker; do not push IRB prereqs as the fix for that symptom
- **Multi-member Loopback Interface:** not supported — Interfaces app enforces one member per Loopback CR. Anycast on another leaf → separate Interface CR + VN `routedInterfaces` entry.

### Multi-leaf same subnet — IRB host routes required

When **hosts span multiple leaves on the same subnet**, enable IRB **`hostRoutePopulate`** (and related EVPN host-route / ARP-ND advertisement settings) so each leaf advertises host routes for local attached hosts. Without that, remote leaves in the same BD/subnet may lack host reachability even when the subnet type-5 / GW is present.

| Case | IRB host routes |
|------|-----------------|
| Multi-leaf hosts on **same** subnet | **Required** (`hostRoutePopulate` / related EVPN host-route params) |
| Single-leaf-per-subnet + type-5 stitch DCI (repo default patches) | Often **disabled** by design (stitch prefixes + optional loopback `/32`) |
| Loopback OK + client FAIL, 0 pkts on remote host | Still check **MSG/GBP** first (golden rule) — do **not** reintroduce “IRB alone fixed GBP” |

## Vnet / client matrix (SRL lab — operational Talos 2026-08-24)

| Client | VNet | Leaf port | Notes |
|--------|------|-----------|-------|
| client-1/2 | vnet-1 | leaf-1 e1-5, leaf-2 e1-6 | DC1 L3 `101.x` |
| client-5/6 | vnet-2 hub | leaf-5 e1-5, leaf-6 e1-6 | DC2 L3 `201.x` |
| (none 151.x) | vnet-5 | leaf-4 e1-5 | IRB `151.254`; export RT `1:105` |
| client-3 | vnet-3 L2 | leaf-3 e1-5 | docker IP still 201.1 — wrong for L2 |
| client-7 | vnet-4 L2 | leaf-7 e1-5 | `105.x` |

Client config: `default via <irb-gw>` on eth1; VLAN subifs elsewhere.

## Vnet / client matrix (SROS lab `clab-3-tier-leaf-spine-dcgw` — differs from SRL names)

| Client | IP | VNet / leaf | IRB GW | Notes |
|--------|-----|-------------|--------|-------|
| client1 | 172.16.101.1 | vnet-1 / leaf-1 | 172.16.101.254 | DC1 stitch RT `100:100` |
| client5 | 172.16.102.1 | **vnet-2** / leaf-5 | 172.16.102.254 | Hub (not vnet-5); RT `101:101` |
| client3 | 172.16.151.1 | **vnet-5** / leaf-3 | 172.16.151.254 | Spoke RT `102:102` |

Hub uses `import-ric-vnet-2` (Accept `100:100` and `102:102` via separate sets). If hub lacks spoke `/24`s despite RIB-IN, check CommunitySet All/AND mistake.

### MSG / GBP note (SROS WSL, 2026-08 — client↔client)

| Item | Detail |
|------|--------|
| Symptom | Loopback OK; client `/24` FAIL; tcpdump on remote client / leaf edge = 0 pkts |
| Cause | `MicroSegmentationPolicy/red-blue-green` → `serviceTargets.virtualNetworks` includes **`vnet-1`**; GBP default deny |
| Fix | Remove `vnet-1` from `red-blue-green.serviceTargets` (or disable MS policy) |
| Not the fix | IRB `hostRoutePopulate` / `evpnRouteAdvertisementType` patches |

### IRB patch technique (optional; not the MSG symptom fix)

Live VNs may omit `hostRoutePopulate` / `evpnRouteAdvertisementType`. JSON **`replace`** no-ops if absent — use **`add`** when intentionally applying repo L3 prereq scripts. That is a patch technique only; **do not** treat it as required for loopback-OK / client-FAIL when GBP targets `vnet-1`.

**When host routes *are* needed:** multi-leaf same-subnet host reachability (see table above). Repo `apply-vnet-l3-prereqs-sros.sh` disables them for type-5 stitch style — override that design if you place hosts on multiple leaves of one subnet.

## Vnet L3 prerequisites (SROS patches)

Per-vnet JSON in `services/vnets/patches/`:

- Enable BGP on service router for L3 DCI vnets (1, 2, 5)
- Optional design: disable `hostRoutePopulate` and `evpnRouteAdvertisementType` on IRB vnets 1–7 (type-5 stitch style) — **orthogonal** to MSG/GBP client blocks; **do not** use disable when multi-leaf hosts share a subnet

Apply: `scripts/apply-vnet-l3-prereqs-sros.sh`

## Init / NodeProfile (Talos)

- Split `init-base` per platform — never `nodeSelectors: [managedSrl, managedSros]` (AND logic, matches nothing)
- `NodeProfile.spec.license` → ConfigMap name in same namespace
- Align `images[].image` with Artifact server paths
- CX sim: manual mgmt gateway on `mgmt0-cx` if Init omits it

Branch vcluster / CX / SROS content moved to **[eda-branch](../eda-branch/SKILL.md)** skill and **[eda-branch-lab](~/Projects/eda-branch-lab)** repo.

## 3-site fabric ASN (clab-3-site-bl-spine)

EDA Fabric eBGP underlay: unique ASN per **leaf**, **one** ASN for all **spines** (allocation key `{fabric}-spine`, no node name). That is correct for a Clos where spines do **not** eBGP with each other.

This lab has spine–spine links (intra-site `c3`/`c4` after 2026-08-26 extra-uplink deploy, and inter-site ISLs).

**CLAB replace + ESI LAG (2026-08-26):** `clab-connector remove` deletes NS `clab-3-site-bl-spine` (Fabric/VNET/LAG CRs go with it). Then destroy → rm CLAB dir → deploy extra-uplink YAML → `integrate` → relabel `borderleaf`/`spine` → **Option 2:** three site Fabrics (`fabrics-option2-per-site.yaml`) → WAN ISLs `isl=wan-interSwitch` → RR–RR iBGP EVPN. Do **not** add a 4th Fabric. c1/c5 AllActive LACP; c3 SingleActive Static + host active-backup (do not LACP c3). `vnet-1` **Degraded** from A/S LAG is a known EDA issue (fix **26.8.1**); F0 still OK. **Fail catalog 2026-08-26:** F2 (`e1-1`+`e1-2`) all OK (not isolate). F2iso (all 4 uplinks, edge still up): host ECMP onto isolated leaf. **Shut edge `e1-5` until the D5 rejoins**, then restore the member (F2iso-edge all OK). Manual until a later isolate/rejoin workflow. F9/F10 access LAG OK.

**Option 1 (snapshot):** one Fabric, eBGP UL + iBGP OL. Fail matrix passed. **Option 2 (snapshot):** three Fabrics, local RR, WAN eBGP + RR–RR iBGP EVPN. Fail matrix passed. **Option 3 (snapshot):** one Fabric eBGP UL+OL, SROS as **spine**. Instance `inter-as-vpn true` from template; Configlets `rr-vpn-forwarding` + `def-recv-evpn-encap vxlan` + group `next-hop-unchanged evpn` applied; Type-5 NH still spine. Fail matrix **did not pass**. **SROS spine keep-NH in the App (shared ASN):** falsified — Configlet = what Fabrics would render; Type-5 NH stayed spine. RFC table (7348/7432/8365/9014/9469/7938) in `eda-3-site-bl-spine/docs/3-site-bl-spine-fabric-and-failure.md` § RFC alignment. **Option 4 live (2026-08-28):** one Fabric eBGP UL+OL, D5=`leaf`, SROS=`wan` **borderleafs**, unique ASN per SROS. Type-5 NH = D5 VTEP. **L3** fail matrix **passed** (2026-08-26). **L2 `vnet-l2`:** unicast A/A works (T1); local T4 empty because eBGP ASBR does not re-advertise ES-import RT (same boxes reflected T4 as Option 2 iBGP RRs). Relabeling EDA `spine` while overlay stays eBGP does not fix T4. No RIC. YAML under `eda-3-site-bl-spine/clab/`.

**Client routes:** Docker linux nodes already have `default via 172.55.10.1` (mgmt). `ip route add default via <IRB> || true` never installs. Use `ip route add 172.16.0.0/16 via <IRB>` instead.

**Type-5 host `/32`:** set `hostRoutePopulate.evpn.populate: false`. `true` makes the pair leaf re-originate the `/32` with NH=self.

Workarounds if iBGP is not wanted: unique or per-site spine ASN (custom alloc / BGP CRs), or **one fabric per site + DCI**.

## WSL Zscaler TLS (same cluster as these labs)

After laptop reboot, AppStore catalogs / Discord `x509` is **eda-mcp**, not a DCI policy issue. Run `~/Projects/eda-mcp-client/scripts/fix_eda_proxy_ca_trust.sh`. Do **not** patch `eda-notifier` (derived App). See **eda-mcp**.

## Platform restore

Script: `scripts/eda-platform-restore.sh` in **eda-dci-lab**. Copy to `~/backups`, `chmod +x`, run interactively — wizard prompts for kubectl context, backup dir, namespace, toolbox pod, `.tar.gz` file. Uses kubectl + `edactl` in `eda-toolbox` pod (not EDA UI). WSL `kind-*` contexts skip host safety checks. **Never** `source` the script. Full connection examples: `docs/eda-platform-restore-connection.md`.
