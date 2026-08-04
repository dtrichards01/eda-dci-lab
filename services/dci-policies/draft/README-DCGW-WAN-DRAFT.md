# Draft: DCGW-only WAN — vnet-1 / vnet-2 L3 only

Scope: **vnet-1 (spoke DC1, RT 100)** ↔ **vnet-2 (hub DC2, RT 101)**. No vnet-5, MH, L2, SH.

```bash
bash ~/eda-dci-lab/scripts/apply-dci-wan-dcgw-draft.sh
# revert
bash ~/eda-dci-lab/scripts/revert-dci-wan-dcgw-draft.sh
```

## Policy map

| Policy | Role |
|--------|------|
| `export-dc-1-routes-wan-dcgw` | WAN secondary DC1: export vnet-1 RT 100, type-5 + VPNv4 |
| `export-dc-2-routes-wan-dcgw` | WAN secondary DC2: export vnet-2 RT 101, type-5 + VPNv4 |
| `export-dci-stitch-dc1-vnet-1` | RIC spoke export (draft overwrites prod CR) |
| `export-dci-stitch-dc2-hub` | RIC hub export (draft overwrites prod CR) |
| `import-dci-hub-stitch-prefix` | Spoke vnet-1 import hub RT 101, type-5 + VPNv4 |
| `import-dci-hub-vnet-1-stitch` | Hub vnet-2 import vnet-1 RT 100 only |
| WAN peers | `nextHopSelf: true` if not already set on `DefaultBGPPeer` |

If `dcgw-1-dcgw-3-bgp-peer` already has `nextHopSelf: true` and
`export-dc-1-prefixes-and-add-soo`, only replace that Policy CR:

```bash
kubectl apply -f services/dci-policies/draft/policies/export-dc-1-prefixes-wan-dcgw.yaml
```

Do the equivalent on the DC2 secondary peer (hub RT 101 export policy).

## Quick validation

- dcgw WAN: `172.16.201.0/24` NH = **DCGW system IP**, not leaf `11.0.0.x`
- leaf-1 `router-1`: no `target:1:103` paths to DC2 leaves
- `client-1` → `172.16.201.1` stable; client-4 no ARP for `.1`
