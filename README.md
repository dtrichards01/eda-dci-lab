# EDA DCI Lab — Talos `srl-leaf-spine-dcgw`

Datacenter interconnect (DCI) service definitions for the Talos EDA cluster and CLAB lab `srl-leaf-spine-dcgw`.

| Item | Value |
|------|-------|
| EDA UI | https://100.124.186.55 |
| SSH / kubectl | `nokia@100.124.186.51` |
| Namespace | `clab-srl-leaf-spine-dcgw` |

**Sibling repo (EVPN control plane):** `~/Documents/eda-dci-evpn-lab` — L3 stitch uses `controlPlane: EVPN` and WAN EVPN; see its `docs/RELATIONSHIP-TO-IPVPN.md`.

## Service model

See `docs/DCI-ALIGNMENT.md` for hub/spoke RTs and apply order.  
See `docs/L3VPN-DCI-GUIDE.md` for policies, AFIs, MPLS/LDP checks, and WAN fabric isolation.

| Tier | Virtual networks | Interconnect CR | Stitch RTs |
|------|------------------|-----------------|------------|
| L3 (IRB) | `vnet-1`, `vnet-2` (hub), `vnet-5` (spoke) | `RouterInterconnect` | `100`, `101`, `102` |
| L2 (bridge only) | `vnet-3`, `vnet-4` | `BridgeDomainInterconnect` | `300`, `301` |
| L3 SH | `vnet-6`, `vnet-7` | `RouterInterconnect` | `400`, `401` |
| L3 MH (per ES) | `vnet-mh-l3-dc1a/b`, `vnet-mh-l3-dc2a/b` | `RouterInterconnect` | `430`, `431` |

- **L3:** EVPN-VXLAN on leaves → IPVPN-MPLS on DCGW (`controlPlane: IPVPN`).
- **L2:** EVPN-VXLAN on leaves → EVPN-MPLS on DCGW (`controlPlane: EVPN`).

## CLAB topology

| Item | Path |
|------|------|
| Canonical YAML | `clab/clab-leaf-spine-dcgw-srl-only.yaml` |
| Talos (your copy) | `~/3-tier-dci/clab-leaf-spine-dcgw-srl-only.yaml` |
| Client scripts | `clab/configs/client-config.sh`, `clab/configs/base-configs/mh-*.sh` |
| Pre-deploy review | `docs/CLAB-VALIDATION.md`, `docs/EDGE-INTERFACES.md` |

### Native client matrix

| Client | Site | IP | Service | Leaf port |
|--------|------|-----|---------|-----------|
| `client-1-vnet-1-dc1` | DC1 | 172.16.101.1 | L3 `vnet-1` | leaf-1 e1-5 |
| `client-2-vnet-1-dc1` | DC1 | 172.16.101.2 | L3 `vnet-1` | leaf-4 e1-5 |
| `client-3-vnet-2-dc2` | DC2 | 172.16.201.1 | L3 `vnet-2` hub | leaf-5 e1-5 |
| `client-4-vnet-2-dc2` | DC2 | 172.16.201.2 | L3 `vnet-2` hub | leaf-8 e1-5 |
| `client-5-vnet-5-dc1` | DC1 | 172.16.151.1 | L3 `vnet-5` spoke | leaf-3 e1-5 |
| `client-6-vnet-3-dc1` | DC1 | 172.16.103.1 | L2 `vnet-3` | leaf-2 e1-6 |
| `client-7-vnet-4-dc2` | DC2 | 172.16.103.2 | L2 `vnet-4` | leaf-8 e1-6 |
| `client-8-dc1-sh` | DC1 | 172.16.155.1 | SH `vnet-6` | leaf-3 e1-6 |
| `client-9-dc2-sh` | DC2 | 172.16.156.1 | SH `vnet-7` | leaf-5 e1-6 |

Cross-DC L3: `101.x` ↔ hub `201.x` ↔ spoke `151.x`. L2: `103.1` ↔ `103.2` same subnet.

### Multi-homed clients (LACP on leaf `e1-10`)

| Client | ES mode | Leaves | Script |
|--------|---------|--------|--------|
| `client-10-dc1-mh` | all-active | leaf-3 + leaf-4 | `mh-dc1a.sh` → `vnet-mh-l3-dc1a` |
| `client-11-dc2-mh` | all-active | leaf-5 + leaf-6 | `mh-dc2a.sh` → `vnet-mh-l3-dc2a` |
| `client-12-dc1-mh` | single-active | leaf-1 + leaf-2 | `mh-dc1b.sh` → `vnet-mh-l3-dc1b` |
| `client-13-dc2-mh` | single-active | leaf-7 + leaf-8 | `mh-dc2b.sh` → `vnet-mh-l3-dc2b` |

MH uses **L3 only** — VLAN 200, subnets `10.200.1.0/24` (DC1) and `10.200.2.0/24` (DC2). One VirtualNetwork per Ethernet-segment (not per DC). See `docs/EDGE-INTERFACES.md`.

After CLAB deploy, if MH LAGs are Down run `bash scripts/mh-bond-setup-11-13.sh` on k0r4 (bond was not created by client exec).

### Redeploy CLAB (on Talos host)

Run from **`eda-dci-lab/clab`** so `configs/` binds resolve next to the YAML:

```bash
cd ~/eda-dci-lab/clab
# optional: cp -r ~/3-tier-dci/configs/telemetry configs/telemetry
bash ~/eda-dci-lab/scripts/clab-deploy.sh
# or: clab deploy -t clab-leaf-spine-dcgw-srl-only.yaml

# Re-register with EDA / re-apply fabric as per your usual workflow
bash ~/eda-dci-lab/scripts/apply-all.sh
```

See `clab/README.md` for path layout and migration from `~/3-tier-dci`.

## DCI routing policies

**Full policy map (what is applied where, why, WAN fabric isolation):** `docs/L3VPN-DCI-GUIDE.md`

| Policy (live on WAN peers) | Role |
|----------------------------|------|
| `export-dc-1-routes-and-add-soo` | DC1 WAN export — VPNv4 RT `100` + `102`, SOO, no EVPN |
| `export-dc-2-routes-and-add-soo` | DC2 WAN export — VPNv4 RT `101`, SOO, no EVPN |
| `import-dci-services-dc-1` | DC1 WAN import — hub VPNv4 RT `101` only |
| `import-dci-services-dc-2` | DC2 WAN import — spoke VPNv4 RT `100` + `102` |

| Policy (live on hub RIC) | Role |
|--------------------------|------|
| `multi-rt-import` | Hub import spoke stitch RTs `100` + `102` |

WAN peers: **VPNv4 only** (`l2VPNEVPN` / `ipv4Unicast` disabled). See guide §1–2 for fabric address isolation.

## Layout

```
clab/
  clab-leaf-spine-dcgw-srl-only.yaml
  eda-fabric/                  # 3 fabrics + WAN ISL CRs
  eda-mpls-ldp/                # LDP routers, interfaces, label block
  eda-topology/                # TopoLink + Interface ISLs
  configs/client-config.sh
  configs/base-configs/mh-dc1a.sh … mh-dc2b.sh
docs/
  L3VPN-DCI-GUIDE.md         # Policy map, AFIs, WAN fabric isolation, MPLS checks
  DCI-ALIGNMENT.md
  CLAB-VALIDATION.md
  EDGE-INTERFACES.md
services/
  l3/router-interconnect/
  l3/interface-labels/       # vnet-1/2/5/6/7 edges
  l3/vnet-6/ vnet-7/           # SH VirtualNetworks
  l2/bridge-domain-interconnect/
  l2/interface-labels/
  mh/                          # per-ES L3 vnets + RIC + LAG labels
  dci-policies/
scripts/
  sync-repo-to-talos.sh        # Windows → Talos file sync
  sync-and-apply-talos.sh      # sync + apply-all
  apply-all.sh
  cleanup-mh-stale.sh          # remove orphan MH YAML/CRs
  mh-bond-setup-11-13.sh         # fix MH client bonds on k0r4
```

## Sync repo to Talos (from WSL)

```bash
wsl bash ~/Documents/eda-dci-lab/scripts/sync-repo-to-talos.sh
# or sync + apply:
wsl bash ~/Documents/eda-dci-lab/scripts/sync-and-apply-talos.sh
```

On Talos directly:

```bash
bash ~/eda-dci-lab/scripts/apply-all.sh
```

## Test (on Talos host after CLAB + EDA apply)

```bash
bash ~/eda-dci-lab/scripts/test-l3-cross-dc-ping.sh
```

## Technical documentation

| Format | Path |
|--------|------|
| Canvas | Open dci-technical-nodes.canvas.tsx beside chat |
| Word | `docs/DCI-Technical-Node-Documentation.docx` |
| Regenerate Word | `wsl python3 docs/generate-dci-node-docx.py` |
