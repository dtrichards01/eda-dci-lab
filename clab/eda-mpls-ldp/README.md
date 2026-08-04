# MPLS / LDP CRs — `clab-srl-leaf-spine-dcgw`

Exported from live EDA cluster. Enables MPLS LDP on DCGW and PE nodes for DCI WAN transport.

## Files

| File | Contents |
|------|----------|
| `labelblocks.yaml` | `eda-default-ldp-label-block` (bootstrap label range) |
| `defaultldprouters.yaml` | LDP enabled on `dcgw-1`–`4`, `pe-1`, `pe-2` |
| `defaultldpinterfaces.yaml` | LDP on WAN/MPLS interfaces (dcgw mesh + pe ports) |

## Apply

```bash
bash ~/eda-dci-lab/scripts/apply-fabric-mpls.sh
```

Apply **before** DCI service RICs that use MPLS/LDP transport.

## Re-export

```bash
bash ~/eda-dci-lab/scripts/export-cluster-cr.sh
```
