# Default OSPF — WAN underlay (`default` NI)

Exported from live EDA cluster. OSPFv2 on DCGW **system** interfaces and on **ethernet WAN links** (via Fabric ISL CRs).

## Files

| File | Contents |
|------|----------|
| `defaultospfinstances.yaml` | `ospf-instance-1` (DC1), `ospf-instance-2` (DC2) |
| `defaultospfareas.yaml` | `backbone-0` (area `0.0.0.0`) |
| `defaultospfinterfaces.yaml` | Passive OSPF on `dcgw-1`–`4` **system0** |

## Manual vs auto-created OSPF

| Link type | How OSPF is defined |
|-----------|---------------------|
| DCGW system `/32` | **This folder** — `DefaultOSPFInterface` CRs (`system-dcgw-*-system0-ipv4`) |
| DCGW↔DCGW mesh, DCGW↔PE WAN | **`clab/eda-fabric/isls.yaml`** — `ISL` CR `ospf` block; EDA programs ethernet OSPF (no separate `DefaultOSPFInterface` CR on cluster) |
| PE backbone (`backbone-simulation`) | **`backbone-simulation` Fabric** underlay OSPFv2 — instance/area names referenced in ISL (`backbone-simulation-ospfv2-ipv4`) |

## Apply

```bash
bash ~/eda-dci-lab/scripts/apply-ospf.sh
# or as part of:
bash ~/eda-dci-lab/scripts/apply-fabric-mpls.sh   # OSPF then ISLs
```

Apply **before** Fabric `ISL` CRs so instances and areas exist.

## Re-export

```bash
bash ~/eda-dci-lab/scripts/export-cluster-cr.sh
```
