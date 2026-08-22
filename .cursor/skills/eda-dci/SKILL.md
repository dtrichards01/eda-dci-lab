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

For MCP client / chat / EQL tooling, use the **eda-mcp** skill. Live alarm OSS feed: **eda-alarm-watch**. Umbrella index: **eda** skill.

## Which repo am I in?

| Repo | RIC | Namespace | RT format |
|------|-----|-----------|-----------|
| **eda-dci-lab** | IPVPN | `clab-srl-leaf-spine-dcgw` | `target:1:NNN` |
| **eda-dci-sros-lab** | EVPN | `clab-3-tier-leaf-spine-dcgw` | `target:100:100` |
| **eda-dci-evpn-lab** | EVPN trial | varies | experimental |

**Never copy policies between SRL and SROS without converting syntax** — see [reference.md](reference.md).

## Golden rules

1. **RIC:** use `importTarget`/`exportTarget` **or** `importPolicy`/`exportPolicy` — **not both** on one RouterInterconnect.
2. **SROS hub (vnet-2) multi-RT import:** Policy field is **`statements`** (plural). CommunitySet `matchSetOptions` is **All only** (no `Any`). Multi-member All = **AND** → does **not** match single-RT spoke routes. Use **one CommunitySet per RT** + **one Accept per set** (`vpn-import-rt-100` / `vpn-import-rt-102` + `import-ric-vnet-2`). Attach as `importPolicy` with `exportTarget: target:101:101` only. Symptom if wrong: RIB-IN shows spokes but hub VPRN never installs them → GW ICMP net unreachable.
3. **Loopback Interface:** single-member only (`type: Loopback`).
4. **Multi-leaf same subnet (anycast IRB):** enable **`evpnRouteAdvertisementType.arpDynamic`/`ndDynamic` + `l3ProxyARPND.proxyARP`/`proxyND`** on the vnet's IRBInterface when hosts on the same subnet span multiple leaves. Without ARP advertisement every client is published **MAC-only (`ip=0.0.0.0`)** and a leaf that also hosts the subnet locally can never resolve a remote host — see **Anycast IRB loopback failure** below. Type-5 stitch labs may still disable host routes by design on single-leaf-per-subnet topologies.
5. **SROS:** no `reject-all-local-evpn` needed — fabric EVPN does not leak to WAN by default.
6. **SRL:** fabric EVPN **must** be blocked on WAN import/export policies. SRL hub may still use multi-member `vpn-import-rts` + `multi-rt-import`; **do not copy that pattern to SROS**.
7. Do **not** add WAN fabric type-2 RT workarounds if loopback test already passes.
8. **No Policy `metadata.annotations`** on SRL or SROS DCI Policy YAMLs (no descriptive/loop-avoidance annotations).

**Branch vcluster / CX / SROS (Talos):** use the **[eda-branch](../eda-branch/SKILL.md)** skill and **[eda-branch-lab](~/Projects/eda-branch-lab)** repo — not this skill.

## Troubleshooting workflow

```
1. ping remote loopback -I local loopback (from leaf service router)
2. If OK but client /24 FAIL: GW traceroute / leaf egress / dataplane policy
3. If loopback FAIL: WAN AFIs, RIC controlPlane vs peer AFI, stitch RT community sets, SOO/tags — see docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md
4. Read docs/L3VPN-DCI-GUIDE.md or docs/SROS-EVPN-DCI-GUIDE.md in this repo
```

**Tech note:** `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md` in **eda-dci-lab** and **eda-dci-sros-lab** (EVPN vs IPVPN, DCGW checkpoints, MPLS/VXLAN, CLI). EQL/YANG paths: **§4 → EQL / YANG state paths** + **WAN prefix over LDP validation** (VPRN RT → resolving NH `nexthop-tunnel-type=ldp` → tunnel-table / LDP `in-label`+`out-label` nested tables, leaf `label`).

## SRL gNMI netns (clab WSL)

**Symptom:** TargetNode **TCPWait** / connection refused on `:57410`. `EDA.pem` can be valid.

**Cause:** `sr_grpc_server` listens only in **`srbase-mgmt`**. Docker mgmt IP is on **`mgmt0` in srbase**. Same IP on `mgmt0.0` in srbase-mgmt → naive proxy = two SYN-ACKs / RST.

**Automate (all SRL in NS):** `~/Projects/eda-clab-sros-recovery/recover-clab-sros-pe.sh --eda-instance wsl -n clab-3-tier-leaf-spine-dcgw --os srl --failed-only --post-rebuild`

Do **not** `clab restart` SRL or replace fabric `config.json`. Proxy is ephemeral. See **eda-branch**.

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


## Stitch RTs (SROS)

| VNet | RT |
|------|-----|
| vnet-1 | `target:100:100` |
| vnet-2 hub | `target:101:101` |
| vnet-5 spoke | `target:102:102` |
| vnet-3 L2 | `300:300` / import `301:301` |
| vnet-4 L2 | `301:301` / import `300:300` |

## Agent checklist

- [ ] Confirm SRL vs SROS before editing policies
- [ ] Match BGP peer CR names (`dcgw-*`) to node names (`dc-gw-*` on SROS)
- [ ] Update README policy map when adding statements
- [ ] Run loopback test before deep WAN debugging
- [ ] Read `docs/EDGE-INTERFACES.md` for client ↔ vnet mapping (SRL lab)
- [ ] **Update skill files** when you learn something new (see eda skill: Skill maintenance)

## More detail

- [reference.md](reference.md) — full policy tables, client matrix, abandoned approaches
- Tech note (both labs): `docs/DCI-CONTROL-PLANE-TROUBLESHOOTING.md`
- Repo docs: `docs/SROS-EVPN-DCI-GUIDE.md`, `docs/L3VPN-DCI-GUIDE.md`, `docs/RELATIONSHIP-TO-SRL-LAB.md`, `docs/eda-platform-restore-connection.md`
