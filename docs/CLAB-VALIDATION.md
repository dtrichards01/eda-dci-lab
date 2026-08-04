# CLAB validation — `clab-leaf-spine-dcgw-srl-only.yaml`

Review vs `docs/DCI-ALIGNMENT.md` and aligned cluster state.

## Issues in early drafts (fixed in repo)

| Issue | Wrong | Correct |
|-------|-------|---------|
| Wrong client IPs | client-2 `201.1`, client-3 `151.1`, client-5 `201.1` | `101.2`, `201.1`, `151.1` |
| Wrong tier labels | client-4 `tier: l2`, client-6 `tier: l3` | L2 only for vnet-3/4 (`103.x`) |
| Duplicate mgmt IP | client-3 and client-7 both `172.65.10.123` | Unique `.116`–`.129` |
| Duplicate leaf port | client-6 and client-7 both `srl-leaf-2:e1-6` | vnet-4 → `srl-leaf-8:e1-6` |
| Invalid link node names | `leaf3`, `leaf4` | `srl-leaf-3`, `srl-leaf-4` |
| MH exec without bind | `mh-*.sh` not mounted | `binds` to `configs/base-configs/` |

## Native L3/L2 (clients 1–7)

| Client | VNet | IP | Leaf |
|--------|------|-----|------|
| client-1 | vnet-1 DC1 | 172.16.101.1 | leaf-1 e1-5 |
| client-2 | vnet-1 DC1 | 172.16.101.2 | leaf-4 e1-5 |
| client-3 | vnet-2 hub | 172.16.201.1 | leaf-5 e1-5 |
| client-4 | vnet-2 hub | 172.16.201.2 | leaf-8 e1-5 |
| client-5 | vnet-5 spoke | 172.16.151.1 | leaf-3 e1-5 |
| client-6 | vnet-3 L2 | 172.16.103.1 | leaf-2 e1-6 |
| client-7 | vnet-4 L2 | 172.16.103.2 | leaf-8 e1-6 |

## Stretched-homed (clients 8–9)

| Client | IP | Leaf | EDA |
|--------|-----|------|-----|
| client-8-dc1-sh | 172.16.155.1 | leaf-3 e1-6 | `vnet-6`, `router-interconnect-vnet-6` |
| client-9-dc2-sh | 172.16.156.1 | leaf-5 e1-6 | `vnet-7`, `router-interconnect-vnet-7` |

## Multi-homed L3 (clients 10–13)

One VirtualNetwork per Ethernet-segment (not per DC). LAG label = `role=edge` + one vnet selector.

| Client | ES mode | Leaves e1-10 | VNet | VLAN | Subnet |
|--------|---------|--------------|------|------|--------|
| client-10 | all-active | leaf-3 + leaf-4 | `vnet-mh-l3-dc1a` | 200 | 10.200.1.0/24 |
| client-11 | all-active | leaf-5 + leaf-6 | `vnet-mh-l3-dc2a` | 200 | 10.200.2.0/24 |
| client-12 | single-active | leaf-1 + leaf-2 | `vnet-mh-l3-dc1b` | 200 | 10.200.1.0/24 |
| client-13 | single-active | leaf-7 + leaf-8 | `vnet-mh-l3-dc2b` | 200 | 10.200.2.0/24 |

**Fabric:** `services/mh/interface-labels/edge-mh-lags.yaml` — four LAG CRs, no standalone `e1-10` physical Interface CRs.

**MH L3 test clients** (in `mh-dc*.sh`): `10.200.1.11–.12` (dc1a), `.31–.32` (dc1b), `10.200.2.21–.22` (dc2a), `.41–.42` (dc2b); GW `.254`.

**Bond on k0r4:** If MH LAGs Down after deploy, clients 11–13 often need manual bond — `bash ~/eda-dci-lab/scripts/mh-bond-setup-11-13.sh`.

## Deploy checklist (Talos)

```bash
cd ~/eda-dci-lab/clab
clab deploy -t clab-leaf-spine-dcgw-srl-only.yaml
bash ~/eda-dci-lab/scripts/mh-bond-setup-11-13.sh   # if MH LAGs Down
bash ~/eda-dci-lab/scripts/apply-topology-cr.sh     # after EDA re-import
bash ~/eda-dci-lab/scripts/apply-fabric-mpls.sh     # fabrics + MPLS/LDP + ISL CRs
bash ~/eda-dci-lab/scripts/apply-all.sh
```

## Repo copy

- `clab/clab-leaf-spine-dcgw-srl-only.yaml`
- `clab/configs/client-config.sh`
- `clab/configs/base-configs/mh-dc1a.sh` … `mh-dc2b.sh`

Legacy `clab/clab-s-spine-spine-leaf-srl-only.yaml` (5 clients) is superseded.
