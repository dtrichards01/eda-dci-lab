# Default IS-IS — WAN underlay option 2 (`default` NI)
#
# Live on Talos 2026-09-04. Option 1 restore: `clab/eda-ospf/` + `isls.yaml` + LDP.
# Do not apply this folder on top of OSPF without `scripts/switch-wan-isis.sh`.

## Files

| File | Contents |
|------|----------|
| `defaultisisinstances.yaml` | `isis-instance-1` (DC1), `isis-instance-2` (DC2), `isis-instance-backbone` (X1b PEs), SR-MPLS enabled |
| `defaultisisinterfaces.yaml` | Passive IS-IS on `dcgw-1`–`4` **and** `sros-pe-1/2` **system0** |

## Manual vs auto-created IS-IS

| Link type | How IS-IS is defined |
|-----------|----------------------|
| DCGW / PE system `/32` | **This folder** — `DefaultISISInterface` |
| DCGW↔DCGW mesh, DCGW↔X1b PE | **`clab/eda-fabric/isls-isis.yaml`** — `ISL` CR `isis` block |
| PE backbone (`backbone-simulation`) | Fabric underlay **ISIS** on PE↔PE TopoLinks. No kube `DefaultISISInstance` from Fabric — PEs use **`isis-instance-backbone`** |

After `kubectl apply` of `isls-isis.yaml`, strip leftover `spec.ospf.ospfv2` (`scripts/strip-isl-ospfv2.py`). Do not add user PE↔PE ISLs.

## Apply

```bash
bash ~/eda-dci-lab/scripts/apply-isis.sh          # instances + system ifaces only
bash ~/eda-dci-lab/scripts/switch-wan-isis.sh     # full option-2 cutover (IGP + SR-MPLS)
```

Apply instances **before** Fabric `ISL` CRs so the instance names exist.

## Confirm SR-ISIS on the box

```bash
docker exec dcgw-1 sr_cli -e 'show network-instance default tunnel-table'
docker exec dcgw-1 sr_cli -e 'info from state network-instance default tunnel-table ipv4'
```

WAN `/32`s must be `type sr-isis` / `owner segrt_mgr`. Full CLI + YANG→EQL: `docs/SRL-DCI-WAN-IGP-Tech-Note.md` §7.
