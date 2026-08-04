# Fabric and WAN ISL CRs — `clab-srl-leaf-spine-dcgw`

Exported from live EDA cluster. These define the **three fabrics** and **manual ISL** objects (DCGW↔DCGW mesh, DCGW↔PE WAN) — separate from TopoLink ISLs in `eda-topology/`.

## Files

| File | Contents |
|------|----------|
| `fabrics.yaml` | `backbone-simulation`, `pod-1`, `pod-2` |
| `isls.yaml` | 6 ISL CRs: dcgw mesh + dcgw↔pe WAN |

## Apply

After CLAB deploy and EDA integrate (nodes + pools exist):

```bash
bash ~/eda-dci-lab/scripts/apply-fabric-mpls.sh
bash ~/eda-dci-lab/scripts/apply-topology-cr.sh   # TopoLink / Interface ISLs
```

Or as part of `apply-all.sh`.

## Re-export from cluster

On Talos (after cluster changes):

```bash
bash ~/eda-dci-lab/scripts/export-cluster-cr.sh
# copies to /tmp/eda-cr-export — scp back to repo clab/eda-fabric/ and clab/eda-mpls-ldp/
```

See also `clab/eda-mpls-ldp/README.md` and `clab/eda-topology/README.md`.
