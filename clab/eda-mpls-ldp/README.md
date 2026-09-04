# MPLS / LDP CRs — `clab-srl-leaf-spine-dcgw` (WAN option 1)

Option 1 transport. **Live WAN (2026-09-04) is option 2 SR-ISIS** (`clab/eda-sr-mpls/`). Restore LDP with `scripts/switch-wan-ospf.sh` (re-applies these CRs). Do not leave Down LDP ifaces in place during option 2 — they tank Fabric health.

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
