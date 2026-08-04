# L2 DCI — BridgeDomainInterconnect and hybrid WAN EVPN

**Namespace:** `clab-srl-leaf-spine-dcgw`  
**Services:** `vnet-3` (DC1, `103.1`) ↔ `vnet-4` (DC2, `103.2`) — same subnet, pure L2  
**Last updated:** 2026-08-04

Companion: `L3VPN-DCI-GUIDE.md` (L3 WAN + fabric isolation), `DCI-ALIGNMENT.md` (service model).

**Production:** L2 DCI in this repo is **lab / demo only** — see `L3VPN-DCI-GUIDE.md` § Lab / demo vs production. Do not deploy hybrid WAN EVPN for L2 in production without vendor validation and a dedicated security review.

---

## 1. Architecture

| Leg | Network instance | Encapsulation | Control | Stitch RT |
|-----|------------------|---------------|---------|-----------|
| Fabric (leaf) | `bd-3` / `bd-4` mac-vrf | VXLAN | EVPN | fabric EVI RT (`104` / `105`) |
| BDI (native DCGW) | `default` interconnect | MPLS/LDP | EVPN | export **300** / **301** |
| WAN (DCGW ↔ DCGW) | `default` | MPLS/LDP | **EVPN** (type-2 + type-3) | **300** / **301** |
| Remote BDI | `default` on far DCGW | MPLS/LDP | EVPN | imports reciprocal RT |

**L3 on the same WAN peers** still uses **VPNv4** (RT `100` / `101` / `102`) — see hybrid policy section below.

### End-to-end path (client-6 → client-7)

```
client-6 (103.1) → leaf-2 bd-3 [EVPN/VXLAN]
  → dcgw-1 fabric EVPN (type-2 MAC, EVI 104)
  → BDI bd-interconnect-vnet-3 leaks to default with export RT 300
  → WAN EVPN type-2/3/MPLS ──► dcgw-3 default
  → BDI bd-interconnect-vnet-4 imports RT 300 into bd-4 stitch context
  → leaf-8 bd-4 [EVPN/VXLAN] → client-7 (103.2)
```

Reverse path uses RT **301** from DC2.

### Do **not** use BridgeDomainDeployment for this model

`services/l2/bridge-domain-deployments/` deploys `bd-3` onto DC2 DCGWs and `bd-4` onto DC1 DCGWs. That **breaks** native VirtualNetwork ownership (`vnet-3` shows nodes on remote DCGWs) and is **not required** when BDI reciprocal RT import is used.

- **Apply:** `bridge-domain-interconnect/` + `interface-labels/` only  
- **Do not apply:** `bridge-domain-deployments/`  
- **Cleanup:** `bash scripts/cleanup-l2-bd-deployments.sh`

---

## 2. BridgeDomainInterconnect CRs

| CR | Bridge domain | DCGW selector | Export RT | Import RT | EVI (interconnect) |
|----|---------------|---------------|-----------|-----------|-------------------|
| `bd-interconnect-vnet-3` | `bd-3` | `eda.nokia.com/dci=dc-1` | `target:1:300` | `target:1:301` | 110 |
| `bd-interconnect-vnet-4` | `bd-4` | `eda.nokia.com/dci=dc-2` | `target:1:301` | `target:1:300` | 111 |

Files: `services/l2/bridge-domain-interconnect/`

Native edges: `services/l2/interface-labels/edge-l2-vnet-3-4.yaml` (leaf-2 e1-6, leaf-8 e1-6).

---

## 3. Hybrid WAN — EVPN for L2 + VPNv4 for L3

WAN BGP peers carry **both** address families:

| AFI | Enabled | Carries |
|-----|---------|---------|
| `vpnIPv4Unicast` | **true** | L3 stitch prefixes (RT 100, 101, 102) |
| `l2VPNEVPN` | **true** | L2 stitch EVPN type-2 (MAC) and type-3 (IMET) only |
| `ipv4Unicast` | **false** | — |

Enable EVPN AFI: `services/dci-policies/bgp-peers/wan-enable-evpn-patch.json` (applied by `apply-l2-wan-evpn.sh`).

Fabric EVPN (all other types and RTs) remains **blocked** by policy default-reject + explicit accept lists.

---

## 4. WAN peer → policy attachment

| Peer | Import | Export |
|------|--------|--------|
| `dcgw-1-dcgw-3-bgp-peer` | `import-dci-services-dc-1` | `export-dc-1-prefixes-and-add-soo` |
| `dcgw-2-dcgw-4-bgp-peer` | `import-dci-services-dc-1` | `export-dc-1-routes-and-add-soo` |
| `dcgw-3-dcgw-1-bgp-peer` | `import-dci-services-dc-2` | `export-dc-2-routes-and-add-soo` |
| `dcgw-4-dcgw-2-bgp-peer` | `import-dci-services-dc-2` | `export-dc-2-routes-and-add-soo` |

**Do not** attach `import-dci-services-dc-*-evpn` or `export-dc-*-routes-evpn-wan` — those are for the `eda-dci-evpn-lab` L3 EVPN RIC trial and do not include L2 stitch rules.

---

## 5. Import policy logic

### `import-dci-services-dc-1` (DC1 WAN peers)

| Order | Statement | Action |
|-------|-----------|--------|
| 1 | `reject-dc1-soo-evpn` | Reject EVPN with SOO `soo-1122` |
| 2 | `accept-remote-l2-type-2-evpn` | Accept EVPN **type-2**, RT **301** (`dci-rt-l2-import-dc1`), tag `tag-20` |
| 3 | `accept-remote-l2-type-3-evpn` | Accept EVPN **type-3**, RT **301**, tag `tag-20` |
| 4 | `reject-all-remote-evpn` | Reject all other EVPN |
| 5 | `accept-remote-hub-ipvpn` | Accept VPNv4 RT **101** (`dci-rt-dc2-l3`), tag `tag-20` |

### `import-dci-services-dc-2` (DC2 WAN peers)

| Order | Statement | Action |
|-------|-----------|--------|
| 1 | `reject-dc2-soo-evpn` | Reject EVPN with SOO `soo-2211` |
| 2 | `accept-remote-l2-type-2-evpn` | Accept EVPN **type-2**, RT **300** (`dci-rt-l2-import-dc2`) |
| 3 | `accept-remote-l2-type-3-evpn` | Accept EVPN **type-3**, RT **300** |
| 4 | `reject-all-remote-evpn` | Reject all other EVPN |
| 5 | `accept-remote-spoke-ipvpn-vnet-1` | Accept VPNv4 RT **100** |
| 6 | `accept-remote-spoke-ipvpn-vnet-5` | Accept VPNv4 RT **102** |

---

## 6. Export policy logic

### `export-dc-1-prefixes-and-add-soo` / `export-dc-1-routes-and-add-soo` (DC1)

| Order | Statement | Action |
|-------|-----------|--------|
| 1–2 | reject imported EVPN/VPNv4 with `tag-20` | Loop protection |
| 3 | `export-local-l2-type-2-evpn` | Export EVPN type-2, RT **300**, add SOO `soo-1122` |
| 4 | `export-local-l2-type-3-evpn` | Export EVPN type-3, RT **300**, add SOO |
| 5 | `reject-all-local-evpn` | Block fabric EVPN leak |
| 6–7 | `export-local-ipvpn-vnet-1` / `vnet-5` | Export VPNv4 RT **100** + **102** + SOO |

### `export-dc-2-routes-and-add-soo` (DC2)

Same pattern with RT **301** for L2 EVPN, SOO `soo-2211`, VPNv4 RT **101** for hub.

---

## 7. L2 community sets

| Name | Members | Use |
|------|---------|-----|
| `dci-rt-l2-export-dc1` | `target:1:300` | DC1 WAN export (bd-3 stitch) |
| `dci-rt-l2-export-dc2` | `target:1:301` | DC2 WAN export (bd-4 stitch) |
| `dci-rt-l2-import-dc1` | `target:1:301` | DC1 WAN import (remote bd-4) |
| `dci-rt-l2-import-dc2` | `target:1:300` | DC2 WAN import (remote bd-3) |
| `dci-rt-l2-stitch` | `300`, `301` | Reference / documentation |

File: `services/dci-policies/communitysets/dci-service-rts.yaml`

---

## 8. Apply order

```bash
# On Talos (after sync or git clone)
bash ~/eda-dci-lab/scripts/apply-l2-dci.sh
# applies edge labels, BDI, and apply-l2-wan-evpn.sh (policies + EVPN AFI)

# Or policies only:
bash ~/eda-dci-lab/scripts/apply-l2-wan-evpn.sh

# Test
bash ~/eda-dci-lab/scripts/test-l2-cross-dc-ping.sh
```

Full lab (L3 + L2): `apply-dci-policies.sh` then `apply-l2-dci.sh` — **not** `apply-dcgw-import-routers.sh`.

---

## 9. Validation

```bash
NS=clab-srl-leaf-spine-dcgw

# Policies have L2 statements
kubectl get policy import-dci-services-dc-1 -n $NS -o yaml | grep "name:"

# Hybrid AFI
kubectl get defaultbgppeers -n $NS -o custom-columns=\
NAME:.metadata.name,EVPN:.spec.l2VPNEVPN.enabled,VPN:.spec.vpnIPv4Unicast.enabled

# Native ownership (no cross-DC BD deployment)
kubectl get virtualnetwork vnet-3 vnet-4 -n $NS -o custom-columns=NAME:.metadata.name,NODES:.status.nodes
# vnet-3 → srl-leaf-2 only; vnet-4 → srl-leaf-8 only

# BDI Up
kubectl get bridgedomaininterconnect -n $NS

# MAC on leaf
docker exec srl-leaf-2 sr_cli 'show network-instance bd-3 bridge-table mac-table all'
docker exec srl-leaf-8 sr_cli 'show network-instance bd-4 bridge-table mac-table all'

# WAN EVPN (dcgw-1 → dcgw-3)
docker exec dcgw-1 sr_cli 'show network-instance default protocols bgp neighbor 11.0.0.11 advertised-routes evpn summary'
docker exec dcgw-3 sr_cli 'show network-instance default protocols bgp neighbor 11.0.0.7 received-routes evpn summary'
```

---

## 10. Sync repo to Talos

From **WSL** (not on k0r4 unless repo is already there):

```bash
unset TALOS_PASS   # unless sshpass is installed
bash /mnt/c/Users/darrenri/Documents/eda-dci-lab/scripts/sync-repo-to-talos.sh
```

Or on Talos:

```bash
git clone https://github.com/dtrichards01/eda-dci-lab.git ~/eda-dci-lab
chmod +x ~/eda-dci-lab/scripts/*.sh
perl -pi -e 's/\r//g' ~/eda-dci-lab/scripts/*.sh   # if copied from Windows
```
