---
name: eda-dci
description: >-
  Nokia EDA DCI lab work — SRL IPVPN and SROS EVPN routing policies, vnet stitch
  RTs, WAN BGP, IRB prerequisites, client connectivity debugging, and Talos/clab
  topology. Use for eda-dci-lab, eda-dci-sros-lab, eda-dci-evpn-lab, cross-DC
  ping failures, RouterInterconnect, community sets, SOO/tag policies, platform
  restore, eda-platform-restore.sh. Not for branch vcluster / CX / Talos rebuild
  work (use eda-branch).
---

# EDA DCI labs

For MCP client / chat / EQL tooling, use the **eda-mcp** skill. Live alarm OSS feed: **eda-alarm-watch**. Umbrella index: **eda** skill. Instance URLs (all **26.8.1**): [eda/26.8.1-changes.md](../eda/26.8.1-changes.md) — 3-site k0r4 is **#2**, not #1. Host-CLAB ping/traceroute: EDA **Ping** / **Trace Route** / **ISL Ping** — **not Edge Ping** (TestMan/CX only). Route Trace ≠ Trace Route: [eda/oam-workflows.md](../eda/oam-workflows.md).

## Which repo am I in?

| Repo | RIC | Namespace | RT format |
|------|-----|-----------|-----------|
| **eda-dci-lab** | IPVPN | `clab-srl-leaf-spine-dcgw` | `target:1:NNN` |
| **eda-dci-sros-lab** | EVPN | `clab-3-tier-leaf-spine-dcgw` | `target:100:100` |
| **eda-dci-evpn-lab** | EVPN trial | varies | experimental |

**Never copy policies between SRL and SROS without converting syntax** — see [reference.md](reference.md).

**DCI options + use-case catalog (git, share this):** `eda-dci-lab/docs/DCI-OPTIONS.md` — which lab, WAN IGP **option 1 OSPF+LDP** vs **option 2 ISIS+SR-ISIS** (live), SRL vs SROS GRT, and **every validated use case** (hub-spoke, L2 BDI, SH, MH, 3-site 1–4, H5 pointer). YAML for both WAN underlays is in that repo. 3-site fabric options 1–4 are `eda-3-site-bl-spine`, not the WAN IGP switch.

### Kind #1 IXR-H5 TH (`clab-h5-2x2`) — 2026-09-03

**First lab EVPN VXLAN service on 7220 IXR-H5 (Tomahawk / TH series).** Not D2L/D3L/D5. Not `ai-topo-multi-plane` (H5-64O AI fabric). Canonical: **[eda/h5-th-evpn.md](../eda/h5-th-evpn.md)**. Laptop YAML in `netbox-eda-lab/clab/`.

| Item | Value |
|------|--------|
| UI / NS | Kind **#1** `:9443` / `clab-h5-2x2` |
| SKU | CLAB `ixr-h5-32d` = **7220 IXR-H5-32D**, SRL **26.7.2** |
| Fabric | `h5-2x2` eBGP UL + iBGP OL; spine RR; leaf RR-clients; AS 65500 |
| Service | `l2-vnet` **Up** untagged; client-1 `172.16.101.1/24`, client-2 `.2`; ping 0% loss |
| QoS | Ingress/Egress `*-rocev2-h5-2x2` on Fabric ISLs **and** edge (`PolicyDeployment` `eda.nokia.com/role=edge`). Not AI `rocev2QoS`. Audit: EQL `.namespace.node.srl.qos.interfaces.interface.pfc`. [qos-rocev2.md](../eda/qos-rocev2.md) |

**CLAB vs EDA:** `clab deploy` only wires cables and Linux host bonds. ESI LAG / Fabric / VNET are **after** `clab-connector integrate`. LACP has no partner until LAG CRs exist. **`integrate -t` is `topology-data.json`**, not the source YAML. Kind **#1** (`h5-2x2`): `clab-connector integrate -t /home/ubuntu/clab-h5-2x2/clab-h5-2x2/topology-data.json --eda-url https://100.124.186.50:9443`. See **eda** golden rule 16.

### 3-site BL/spine (`k0r4`, NS `clab-3-site-bl-spine`) — 2026-08-26

**Operational (do not redeploy from Windows).** Laptop: **`Documents/eda-3-site-bl-spine`** (spine-layer inter-site; **not NetBox**). CLAB on `nokia@100.124.186.51` (`k0r4`). EDA **#2 Talos** `https://100.124.186.55/` (not Kind `.50` / WSL).

**Live topology:** extra leaf–spine uplinks (two per D5 to each local spine), intra-site `c3`+`c4`, WAN 2×2. Dual-home ESI LAG. Laptop YAML: `clab/clab-3-site-bl-spine-add-uplinks-add-dual-homes-hosts.yaml`. k0r4 deploy file: `/home/nokia/collapsed-bl-wan/clab-3-site-bl-spine-add-uplinks.yaml`. Previous single-home snapshot: `clab/clab-3-site-bl-spine.yaml`. **One topology** — do not call these Topology A/B. Briefing master (do not overwrite): `docs/EDA-3-site-overlay-options-RFC.pptx` (slide 3 diagram is hand-edited).

**CLAB vs EDA:** `clab deploy` only wires cables and Linux host bonds. ESI LAG / Fabric / VNET are **after** `clab-connector integrate`. LACP has no partner until LAG CRs exist. Kind **#1** H5 integrate command: see **IXR-H5 TH** section above (golden rule 16).

**Replace CLAB (proven 2026-08-26):** Connector verbs **`remove`** then **`integrate`**. `remove` **deletes the namespace** — Fabric, VNET, and LAG CRs go with it (not left in place).

1. `clab-connector remove`
2. `clab destroy`
3. Remove old CLAB directory (`clab-3-site-bl-spine`)
4. `clab deploy` (extra-uplink / dual-home YAML)
5. `clab-connector integrate`
6. Relabel TopoNodes: D5 `borderleaf`, SR-1 `spine` (connector sets `leaf` / `backbone`)
7. Apply Fabric `clab/fabric-3-site-bl-spine.yaml`
8. Delete standalone Interface CRs that become LAG members; apply `clab/edge-mh-lags.yaml`
9. Label remaining single-home `e1-5` + LAG CRs; apply `clab/vnet-1-3-site-bl-spine.yaml`
10. If needed: add `172.16.0.0/16 via <IRB>` on clients (`|| true` at deploy often no-ops)

Script (run on k0r4 after copying YAML to `/tmp`): `eda-3-site-bl-spine/scripts/eda-apply-after-integrate.sh`. F0 pings: `scripts/eda-f0-baseline.sh`.

| Item | Value |
|------|--------|
| Laptop dir | `Documents/eda-3-site-bl-spine` |
| Live CLAB YAML (k0r4) | `/home/nokia/collapsed-bl-wan/clab-3-site-bl-spine-add-uplinks.yaml` |
| Laptop live YAML | `eda-3-site-bl-spine/clab/clab-3-site-bl-spine-add-uplinks-add-dual-homes-hosts.yaml` |
| Previous snapshot | `eda-3-site-bl-spine/clab/clab-3-site-bl-spine.yaml` |
| ESI LAGs | `eda-3-site-bl-spine/clab/edge-mh-lags.yaml` — c1/c5 **AllActive LACP**; c3 **SingleActive Static** |
| Stale file | `/home/nokia/collapsed-bl-wan/clab-2-site-bl-wan.yaml` — ignore |
| Images | SRL `ghcr.io/nokia/srlinux:26.7.1` `ixr-d5`; SROS `nokia_srsim:26.3.R1` `sr-1` |
| License | `/home/nokia/darren/license/license.key` |
| Mgmt | `172.55.10.0/24` (leaves `.101`–`.106`, spines `.201`–`.206`, clients `.11`–`.16`) |
| Borderleafs (D5) | CLAB name `leaf-*`; **Option 4 live:** `eda.nokia.com/role=leaf`. Option 1–3 used `borderleaf` |
| Spines (SR-1) | CLAB name `spine-*`; **Option 4 live:** `eda.nokia.com/role=wan` as Fabric **borderleafs** (not spine) |
| Fabric | **Live = Option 4 (2026-08-28):** `fabric-option4-bl-wan` **eBGP UL+OL**, D5=`leaf`, SROS=`wan` borderleafs. Service this pass is **L2 `vnet-l2`** (`vnet-1` deleted). L2 ping 172.16.100.{1,3,5} 0% loss after apply. Option 2 snapshot: `clab/fabrics-option2-per-site.yaml`. |
| WAN underlay | In-fabric `wanCore` ISLs (SROS–SROS) while Option 4 is live |
| Overlay | EVPN on `bgpgroup-ebgp-fabric-option4-bl-wan`. **No Configlet.** |
| ASNs | Option 4: **unique ASN per SROS** (101/102/105/106/109/110) and per D5. BL–BL is true eBGP |
| Clients | c1 `172.16.11.1` AllActive LACP (`lag-client-1-site-1`: leaf-1 `e1-5` + leaf-2 `e1-6`); c2 `.2` single-home leaf-2 `e1-5`; c3 `172.16.12.1` SingleActive static LAG + host active-backup (`lag-client-3-site-2`); c4 `.2` leaf-4 `e1-5`; c5 `172.16.13.1` AllActive LACP (`lag-client-5-site-3`); c6 `.2` leaf-6 `e1-5`. GW `.254` anycast. |
| L3 VNET | `vnet-1` — attach to **LAG CRs** + even-leaf `e1-5`. Manifest: `clab/vnet-1-3-site-bl-spine.yaml` |

**Do not** put LACP on client-3: both members stay in one aggregator and traffic hashed to the non-DF leaf is black-holed. Single-active = Static LAG + host active-backup (primary eth1 / preferred DF). **Exception 2026-08-27 Type-1/4 pass:** c1/c3/c5 all **AllActive LACP**.

**Option 4 L2 T4 hole (2026-08-28):** D5s **originate** Type-4 (SROS BL RIB has both local PEs: spine-1 has ESI-02 from `11.0.0.1`+`11.0.0.6`; spine-3 has ESI-03 from `11.0.0.3`+`11.0.0.4`). D5 T4 table is **empty** — SROS eBGP ASBR does **not** re-advertise Type-4 to other EVPN neighbors (local pair or WAN). Type-1 **is** re-advertised (EVI RT + `inter-as-vpn`). Same SROS boxes **did** reflect T4 as Option 2 iBGP RRs. Cause is **role** (eBGP ASBR vs iBGP RR) + ES-import RT, not “SROS cannot do Type-4.”

**Option 2 WAN ISL ASNs:** `asn-pool` reallocates per-site spine underlay ASNs on **every** Fabric create. Do **not** reuse YAML from a previous rebuild. Source of truth is `Fabric.status.spineNodes[].underlayAutonomousSystem`. `scripts/eda-apply-option2.sh` waits for those fields, rewrites `wan-isls-option2.yaml`, then verifies live ISL specs (`scripts/eda-sync-wan-isl-asns.py`). DefaultRouter system IPs are **edactl** (not kube CRDs). Clab `exec` is not a shell — `ip route add … || true` fails with `|| is a garbage`.

**Option 2 L2 MH (2026-08-27):** Valid for **L2 and L3**. Overlay is iBGP RR so Type-1/4 traverse RR–RR. Live `vnet-l2` Up; c1/c3/c5 AllActive LACP; L2 ping 172.16.100.{1,3,5} **0% loss**. Type-1 EAD from **all three ESIs** is used on remote D5s (aliasing tag=0 + MAX-ET). Type-4 is **same-ESI only** (ES-import RT) — each PE uses the pair-leaf Type-4, not remote-site Type-4. Neighbors on D5s are **local RRs only**. L3 `vnet-1` fail matrix already passed on Option 2 (2026-08-26).

**SROS CLI on k0r4 3-site spines:** `docker exec -it <cid> sh` is the **Linux** srsim shell (`/nokia` = license only; `sros` = hardware helpers). Timos MD-CLI is **not** in that PATH. SSH `admin@172.55.10.201` (spine-1) … `.206`, password `NokiaSros1!`. No `sshpass` on k0r4 — use `SSH_ASKPASS` + `SSH_ASKPASS_REQUIRE=force`. Do **not** pass the CLI as `ssh host 'show …'` (SROS `exec request failed`). Pipe `environment more false` + commands + `logout` into `ssh -tt`. spine-1 cid (this rebuild): `f57099d1f1e0` = `spine-1-site-1`.

**Overlay fast detect (2026-08-28):** Fabric `overlayProtocol.bgp.timers` **keepalive 3 / hold 9** on all three site Fabrics (on-box `negotiated-hold-time 9`). RR–RR `bgpgroup-ibgp-evpn-rr-rr` **`bfd: true`** + same timers. Overlay iBGP has **no** Fabric BFD field (`enable-bfd false` on the D5). YAML: `clab/fabrics-option2-per-site.yaml`, `clab/wan-rr-rr-ibgp-option2.yaml`.

**F2iso CP (2026-08-28):** Isolate leaf-1 e1-1..4, edge e1-5 up. **After 20s with hold=9:** leaf-1 overlay to `11.0.0.1`/`.2` is **connect** (down). Remote D5 T3 drops `11.0.0.4` (leaf-2 `11.0.0.3` remains). **T1 ESI-02 aliasing is only `11.0.0.3`** (isolated VTEP withdrawn). Uplinks restored; c1→c3 ping 0% loss. Script: `eda-3-site-bl-spine/scripts/eda-f2iso-cp-capture.sh`.

**Stretched ESI experiment (2026-08-28, Option 2, then restored):** `lag-client-1` members leaf-1+leaf-3. EDA accepted it. T4 used on **leaf-3** from leaf-1 for ESI-02; **leaf-4 did not** import that T4. leaf-1 had no T4 from leaf-3 (LAG Down). T1 for ESI-02 **was** used on leaf-4. Restored via `edge-mh-lags.yaml`. Briefing: slide **27** Type-3 IMET; **34** stretched-ESI write-up; **35** Option 4 local A/A L2; **36** why local T4 is missing (ASBR vs RR). Native ungrouped option diagrams on **11/13/15/17** (real c1–c6 cabling). Do not overwrite other PPTX text. Master: `docs/EDA-3-site-overlay-options-RFC.pptx`.

**Option 3 (snapshot):** SROS as Fabric **spines**, eBGP UL+OL, shared ASN 101. EDA template already sets instance **`inter-as-vpn true`**. Configlets `rr-vpn-forwarding`, `def-recv-evpn-encap vxlan`, group `next-hop-unchanged evpn` + `third-party-nexthop` all on-box. Type-5 NH stays the **spine**. F0 cross-site FAIL. Do not retry those knobs. YAML: `clab/fabric-3-site-bl-spine-ebgp-ol.yaml`.

**SROS 26.3.R1 eBGP EVPN NH (Option 3):** `keep-next-hop` **does not exist**. Configlet JSON must use MD-CLI names (`rr-vpn-forwarding`, not classic `enable-rr-vpn-forwarding` — txn 980). Combined instance+group Configlets did **not** keep VTEP while SROS were **spines**. Borderleaf role (Option 4) is the working eBGP overlay.

**SROS spine + shared ASN + keep VTEP via the App:** **not possible on 26.3.R1.** Detecting OS in Fabrics is easy; emitting keep-NH is not a missing intent. Configlets already wrote `inter-as-vpn`, `rr-vpn-forwarding`, `def-recv-evpn-encap vxlan`, group `next-hop-unchanged evpn` + `third-party-nexthop`. NH stayed the spine. SROS has no working equivalent of SRL `afi-safi evpn next-hop-self false` (`keep-next-hop` does not exist; `nextHopSelf: false` is BGP #12). Unique-ASN Fabrics fork is a **different** experiment (Option 4’s allocation), not a substitute for that knob. See failure doc § **Option 3b**.

**vnet-1:** `hostRoutePopulate.evpn.populate: false`; clients need `ip route add 172.16.0.0/16 via <site IRB>`. CR **Degraded** is a **known EDA issue with A/S (SingleActive) LAG** — standby member subinterface oper-down; dataplane/F0 still OK. Fix in **EDA 26.8.1**. Do not chase this as a lab misconfig. Option 4 pass saw `vnet-1` **Up**.

**Failure catalog + Option 1 vs 2 vs 3 vs 4:** `eda-3-site-bl-spine/docs/3-site-bl-spine-fabric-and-failure.md` (includes **RFC alignment**: 7348 / 7432 / 8365 / 9014 / 9469 / 7938). **Option 1, 2, and 4 L3 fail matrix passed**. **Option 3 did not pass** (SROS spine NHS = RFC 8365 §10.2 anti-pattern). Option 4 **L2 unicast A/A works** (T1); **local T4 DF missing** because eBGP ASBR does not re-advertise ES-import RT (same SR-1s reflected T4 as Option 2 iBGP RRs). Cause is ASBR vs RR, not the EDA `spine` vs `borderleaf` name. Complete MH CP: Option 2 or 1. Briefing master: slides **11/13/15/17** native ungrouped diagrams; **35** L2 appendix; **36** T4/ASBR. Isolate a MH D5 with the LAG member still up → AllActive host **ECMP onto the isolated leaf**. **Shut the edge** (`e1-5`) until the leaf rejoins, then restore the member. Manual until a later workflow. SROS WAN/c3 still unverified.

## Golden rules

1. **RIC:** use `importTarget`/`exportTarget` **or** `importPolicy`/`exportPolicy` — **not both** on one RouterInterconnect.
2. **SROS hub (vnet-2) multi-RT import:** Policy field is **`statements`** (plural). CommunitySet `matchSetOptions` is **All only** (no `Any`). Multi-member All = **AND** → does **not** match single-RT spoke routes. Use **one CommunitySet per RT** + **one Accept per set** (`vpn-import-rt-100` / `vpn-import-rt-102` + `import-ric-vnet-2`). Attach as `importPolicy` with `exportTarget: target:101:101` only. Symptom if wrong: RIB-IN shows spokes but hub VPRN never installs them → GW ICMP net unreachable.
3. **Loopback Interface:** single-member only (`type: Loopback`).
4. **Multi-leaf same subnet (anycast IRB):** enable **`evpnRouteAdvertisementType.arpDynamic`/`ndDynamic` + `l3ProxyARPND.proxyARP`/`proxyND`** on the vnet's IRBInterface when hosts on the same subnet span multiple leaves. Without ARP advertisement every client is published **MAC-only (`ip=0.0.0.0`)** and a leaf that also hosts the subnet locally can never resolve a remote host — see **Anycast IRB loopback failure** below. Type-5 stitch labs may still disable host routes by design on single-leaf-per-subnet topologies.
5. **SROS:** no `reject-all-local-evpn` needed — fabric EVPN does not leak to WAN by default. SROS DCGW Base does **not** fill with remote leaf/spine `/32`s.
6. **SRL:** fabric EVPN **must** be blocked on WAN import/export (`reject-all-local-evpn` egress, `reject-all-remote-evpn` ingress). Unrestricted WAN EVPN puts remote **leaf VTEP** in the stitch NH → wrong resolution over WAN MPLS. **DCGW `default` ≠ ISIS table** (GRT = host + IGP + BGP). Remote leaf `/32`s are **BGP**, never ISIS/OSPF in this lab. OSPF→ISIS did not change that. Canonical: **`docs/SRL-vs-SROS-DCGW-RIB.md`**. SRL hub may still use multi-member `vpn-import-rts` + `multi-rt-import`; **do not copy that pattern to SROS**.
7. Do **not** add WAN fabric type-2 RT workarounds if loopback test already passes.
8. **No Policy `metadata.annotations`** on SRL or SROS DCI Policy YAMLs (no descriptive/loop-avoidance annotations).
9. **SROS `configuredName` vs CR name (tested 2026-09-07 on 26.8.1):** `RouterInterconnect.importPolicy` is still a Policy **CR name** on the node (`vrf-import policy ["import-ric-vnet-2"]`). Setting `configuredName: IMPORT_RIC_VNET_2` on that Policy made CE txn **5103 fail** (`MGMT_CORE #240` — cannot delete/rename `policy-statement import-ric-vnet-2` while VPRN still references it). Same 26.4.x split; SROS rejects instead of duplicating. Reverted. Do **not** set `configuredName` ≠ CR name on RIC-attached Policies.

**Branch vcluster / CX / SROS (Talos):** use the **[eda-branch](../eda-branch/SKILL.md)** skill and **[eda-branch-lab](~/Projects/eda-branch-lab)** repo — not this skill.

## Troubleshooting workflow

```
1. ping remote loopback -I local loopback (from leaf service router)
2. If OK but client /24 FAIL: GW traceroute / leaf egress / dataplane policy
3. If loopback FAIL: WAN AFIs, RIC controlPlane vs peer AFI, stitch RT community sets, SOO/tags; **VPNv4 NH must be remote DCGW not leaf VTEP** — `docs/SRL-vs-SROS-DCGW-RIB.md`
4. Read docs/L3VPN-DCI-GUIDE.md or docs/SROS-EVPN-DCI-GUIDE.md in this repo
```

**Tech note:** `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` in **eda-dci-lab** and **eda-dci-sros-lab** (EVPN vs IPVPN, DCGW checkpoints, MPLS/VXLAN, CLI). EQL/YANG paths: **§4 → EQL / YANG state paths**. **Live SRL WAN (2026-09-04) is SR-ISIS not LDP:** CLI `show network-instance default tunnel-table` + `info from state … tunnel-table ipv4` (`type sr-isis`, `owner segrt_mgr`); VPNv4 NH = remote DCGW `/32` then join TTM. YANG→EQL table in `eda-dci-lab/docs/SRL-DCI-WAN-IGP-Tech-Note.md` §7. Option 1 LDP validation remains: VPRN RT → resolving NH `nexthop-tunnel-type=ldp` → tunnel-table / LDP labels.

**WAN IGP options (SRL Talos, 2026-09-04):** index **`eda-dci-lab/docs/DCI-OPTIONS.md`**. Two recorded underlays for `clab-srl-leaf-spine-dcgw` + X1b PEs. **Live now = Option 2** IS-IS L2+SR-MPLS, RIC encap MPLS / `allowedTunnelTypes: SR-ISIS`. **Confirm:** `docker exec dcgw-1 sr_cli -e 'show network-instance default tunnel-table'` — WAN `/32`s are **sr-isis** / next-hop **mpls** (no LDP); YANG `info from state … tunnel-table ipv4` (`type sr-isis`, `owner segrt_mgr`). CLI + EQL hints: `docs/SRL-DCI-WAN-IGP-Tech-Note.md` §7. User CR `isis-instance-backbone` (Fabric does not emit a PE ISIS instance). **Option 1** OSPFv2+LDP restore: `scripts/switch-wan-ospf.sh`. Cutover: `scripts/switch-wan-isis.sh`. JSON-remove leftover `ISL.spec.ospf.ospfv2`; delete leftover OSPF system0 + Down LDP ifaces or Fabric health stays off 100. Do **not** create user PE↔PE ISLs. Do **not** apply whole `fabrics.yaml`. Tech note: `eda-dci-lab/docs/SRL-DCI-WAN-IGP-Tech-Note.md`.

### Talos SRL DCI (`k0r4`, NS `clab-srl-leaf-spine-dcgw`) — 2026-08-24

**Operational (do not change EDA).** Hub-spoke RIC is up. Live 8-client CLAB: `~/3-tier-dci/clab-s-spine-spine-leaf-srl-only.yaml`.

| Vnet | Export RT | Import | Ports | Working docker hosts | Subnet / GW |
|------|-----------|--------|-------|----------------------|-------------|
| vnet-1 | `target:1:100` | `target:1:101` | leaf-1 e1-5, leaf-2 e1-6 | client-1 `.1`, client-2 `.2` | `172.16.101.0/24` / `.254` |
| vnet-2 hub | `target:1:101` | `importPolicy: multi-rt-import` | leaf-5 e1-5, leaf-6 e1-6 | **client-5** `.1`, **client-6** `.2` | `172.16.201.0/24` / `.254` |
| vnet-5 spoke | `target:1:105` | `target:1:101` | leaf-4 e1-5 | no `151.x` container (IRB `.254` from hub) | `172.16.151.0/24` / `.254` |

Hub `vpn-import-rts`: `1:100` + `1:105`, `matchSetOptions: Any`. Ping: vnet-1 ↔ vnet-2 both ways; vnet-2 → `151.254`; vnet-1 → `151.254` fail (spoke isolation). Post-check: `eda-dci-lab/scripts/post-check-l3-hub-spoke.sh`. Do not “fix DCI policies” first — WAN VPNv4 is fine.

## SRL gNMI netns (clab WSL)

**Symptom:** TargetNode **TCPWait** / connection refused on `:57410`. `EDA.pem` can be valid.

**Cause:** `sr_grpc_server` listens only in **`srbase-mgmt`**. Docker mgmt IP is on **`mgmt0` in srbase**. Same IP on `mgmt0.0` in srbase-mgmt → naive proxy = two SYN-ACKs / RST. Installing the proxy **before** srbase has the IPv4 and grpc is on `:57410` leaves factory grpc on `:57400` (TCPWait even if a python proxy process exists).

**Automate (failed SRL in NS):** `~/Projects/eda-clab-sros-recovery/recover-clab-sros-pe.sh --eda-instance wsl -n clab-3-tier-leaf-spine-dcgw --os srl --failed-only --post-rebuild`

Do **not** `clab restart` healthy SRL or replace fabric `config.json`. If grpc stays on `:57400` with IPv4 only in srbase-mgmt: docker-restart **those nodes only**, then re-run the command above. Proxy is ephemeral. See **eda-branch**.

**After TargetNodes Ready:** check fabrics (`pod-1`/`pod-2`) and interfaces. Ready + Down ifaces (WSL 2026-08-27) = missing CLAB dataplane veths (`e1-*` / `clab-o-*` gone from SRL `srbase`; stale host `clab-stitch-…`). **`--post-rebuild` will not fix this.** Reconcile the live topo: `sudo clab deploy -t /home/clab/3-tier-leaf-spine-s_spine/clab-s-spine-spine-leaf-sr-sim-srl.yaml` (`--dry-run` first; **no `--reconfigure`**). Abandoned: `ip link set e1-*-0 up`. SROS ISLs can already be Up.

**Zscaler after laptop reboot (same WSL cluster):** catalogs / Discord x509 → `~/Projects/eda-mcp-client/scripts/fix_eda_proxy_ca_trust.sh`. Do **not** patch `eda-notifier` (derived App). Skill **eda-mcp**.

**MCP / EQL UI:** verified cheat-sheet paths and aliases live in **eda-mcp** (`eql_aliases`, IP-prefix catalog dropdown, multi-TopoNode compare). SRL uses `afi-safi.evpn` singular `-route`; SROS uses `.state.` paths; per-route EVPN RIB is CLI-only on SROS.

## Anycast IRB loopback failure (verified 2026-08-13, eda-dci-sros-lab)

**Symptom:** `ping <leaf loopback>` from a client on a *different* leaf fails 100%, while same-subnet bridging, cross-DC and WAN all pass. Example: client4 (leaf-4, `172.16.101.2`) → `1.1.1.1` (loopback01 on leaf-1), both in vnet-1.

**Cause — not routing.** Echo requests *do* reach leaf-1; the reply is never built. leaf-1 also hosts the anycast IRB for `172.16.101.0/24`, so that subnet is a **connected** route and always beats the EVPN path. leaf-1 therefore ARPs locally for the remote host instead of routing over the L3 VNI. The ARP request floods and reaches the client, but the client's reply is unicast to the **anycast gateway MAC**, which the *local* leaf also owns — so it terminates the reply and never forwards it over VXLAN. ARP never resolves; every reply is dropped.

**Rule of thumb:** it breaks exactly when the *replying* leaf also hosts the source subnet via anycast IRB. That's why loopbacks fail while cross-DC works.

**Fix** (EDA API `PUT …/virtualnetworks/<vnet>`, per IRB interface):

```json
{"evpnRouteAdvertisementType": {"arpDynamic": true, "ndDynamic": true},
 "l3ProxyARPND": {"proxyARP": true, "proxyND": true}}
```

- **Proxy-ARP alone is not enough.** It is the consumer; with clients advertised MAC-only there is nothing to answer from. `arpDynamic` populates the binding, `proxyARP` uses it.
- **`l2proxyARPND` is rejected** — EDA renders it onto every member subinterface including the IRB and SR Linux refuses proxy-ARP there (`IRB interfaces cannot be configured with proxy-arp`). L3-only is sufficient; the BD `bridge-table proxy-arp` table stays empty **by design**.
- **kubectl patches are inert.** EDA has its own datastore and does not read kubectl-edited CRs; the BD is `eda.nokia.com/source: derived`. Write through the **EDA API** or the change never reaches the devices.
- Also fixes the "client MAC missing from bd-1" red herring: the 300s bridge-domain MAC age vs 14400s ARP timeout made idle hosts vanish. Verified durable — 420s idle, MAC still learnt, cold ping 0% loss.

**Verify (SRL CLI)** — `docker exec leaf-1 sr_cli -e "<cmd>"`:

| Check | Command |
|---|---|
| EVPN-learned ARP binding (`origin: evpn`) | `show arpnd arp-entries interface irb0` |
| The type-2 MAC-IP route behind it | `show network-instance default protocols bgp routes evpn route-type 2 ip-address <ip> detail` |
| Host route in the IP-VRF | `show network-instance <vrf> ipv4 route` |

**CLI traps:** `route-table` is accepted under a network-instance but is a **dead-end token** that only prints usage — use `ipv4 route` / `ipv6 route`. There is no `bridge-table mac-ip-table`; it's `bridge-table proxy-arp all`.

**EQL equivalents** (aliases in eda-mcp-client, all live-validated): `srl evpn arp bindings`, `srl evpn nd bindings`, `srl evpn host routes`, `srl irb proxy-arp enabled`, `srl irb arp advertise`.

## Platform restore (EDA backup)

Interactive wizard: `scripts/eda-platform-restore.sh` — copy to `~/backups`, run `./eda-platform-restore.sh` (WSL/KIND or Talos via kubectl; **do not source**). Docs: `docs/eda-platform-restore-connection.md`.

## Apply scripts (SROS lab)

```bash
bash scripts/apply-dci-policies-sros.sh
bash scripts/apply-vnet-l3-prereqs-sros.sh   # BGP + IRB disable patches vnet-1..7
```

### Dual EVPN + IPVPN WAN policies — OBSOLETE

**Do not mix EVPN and IPVPN in one Policy.** Use mode-specific pairs in `eda-dci-sros-lab/services/dci-policies/wan/policies/`:

| Mode | Import / export |
|------|-----------------|
| EVPN (`l2VPNEVPN` + EVPN RIC) | `import-dci-evpn-dc-{1,2}` / `export-dci-evpn-dc-{1,2}` |
| IPVPN (`vpnIPv4` + IPVPN RIC) | `import-dci-ipvpn-dc-{1,2}` / `export-dci-ipvpn-dc-{1,2}` |

Peer CR fields: **`importPolicies` / `exportPolicies`**. No Policy annotations.

**Policy model notes:**
- EDA `families` enum has **no vpn-ipv4** — never `families:[IPv4]` for vpn-ipv4 peers.
- Never `BGP_IPVPN` on SROS. IPVPN match: `BGP_VPN` + **one CommunitySet per RT** (SROS `matchSetOptions` is **All-only** — never `Any`; multi-member All = AND → one Accept statement per single-member set).
- **`allow-export-bgp-vpn`:** conditional — often for EVPN RIC; usually unset under IPVPN RIC (auto EVPN-IFL↔IPVPN when both instances present). Flag changes may need VPRN bounce.
- Apply: communitysets → mode policies → point peers. See `wan/README.md`.
- **26.8.1 limited:** `match.bgp.nextHop` + `action.setRoutePreference` — example CRs in `eda-dci-sros-lab/.../examples/26.8.1-bgp-nh-rtm-pref/` (**not** on live WAN peers).


## Stitch RTs (SRL lab — operational 2026-08-24)

| VNet | RT |
|------|-----|
| vnet-1 | `target:1:100` |
| vnet-2 hub | `target:1:101` + `importPolicy: multi-rt-import` (`vpn-import-rts` = `1:100`+`1:105`, Any) |
| vnet-5 spoke | `target:1:105` |

## Stitch RTs (SROS)

| VNet | RT |
|------|-----|
| vnet-1 | `target:100:100` |
| vnet-2 hub | `target:101:101` |
| vnet-5 spoke | `target:102:102` |
| vnet-3 L2 | `300:300` / import `301:301` |
| vnet-4 L2 | `301:301` / import `300:300` |

**Anycast VTEP ≠ BDI and ≠ a dual-homed host.** Canonical write-up: [reference.md](reference.md)#anycast-vtep-mac-vrf-mh-vs-bridgedomaininterconnect--2681 (also `eda-dci-lab/docs/EDGE-INTERFACES.md` + `DCI-OPTIONS.md` §2). **Interfaces** defines `vtep` on the LAG; **Services** realizes it via **VLAN** or **BridgeInterface**. **SRL only** (Talos 2026-09-10). **Not the same on SROS** (WSL 2026-09-11: 0 LAG, no `anycast-multi` in SROS configure tree). Anycast IRB is unrelated. **L3 IRB on the MH ES:** `advertise-ifl-host-ad-routes` is needed; EDA does not set it — Configlet `06-configlet-ifl-host-ad.yaml` (not L2).

## Agent checklist

- [ ] Confirm SRL vs SROS before editing policies
- [ ] Match BGP peer CR names (`dcgw-*`) to node names (`dc-gw-*` on SROS)
- [ ] Update README policy map when adding statements
- [ ] Run loopback test before deep WAN debugging
- [ ] Read `docs/EDGE-INTERFACES.md` for client ↔ vnet mapping (SRL lab)
- [ ] Anycast VTEP = AllActive **LAG across switches** + MAC-VRF on **SRL**; not BDI, not a host, **not SROS DCGW**
- [ ] L3 IRB on that MH ES: SRL Configlet `advertise-ifl-host-ad-routes` (`06-configlet-ifl-host-ad.yaml`); **L2 does not need it**; **do not copy** that Configlet to SROS
- [ ] **Update skill files** when you learn something new (see eda skill: Skill maintenance)

## More detail

- [eda/26.8.1-changes.md](../eda/26.8.1-changes.md) — 26.4.3 → 26.8.1 instances/URLs (3-site CLAB is **#2**, not #1)
- [reference.md](reference.md) — full policy tables, client matrix, abandoned approaches
- Tech note (both labs): `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md`
- Repo docs: `docs/SROS-EVPN-DCI-GUIDE.md`, `docs/L3VPN-DCI-GUIDE.md`, `docs/RELATIONSHIP-TO-SRL-LAB.md`, `docs/eda-platform-restore-connection.md`
