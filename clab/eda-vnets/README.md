# Core VirtualNetworks — vnet-1 .. vnet-5

Exported from live EDA cluster.

| File | Tier | Subnet | Role |
|------|------|--------|------|
| `vnet-1.yaml` | L3 IRB | `172.16.101.0/24` | DC1 spoke |
| `vnet-2.yaml` | L3 IRB | `172.16.201.0/24` | DC2 hub |
| `vnet-3.yaml` | L2 bridge | `172.16.103.0/24` | DC1 BD |
| `vnet-4.yaml` | L2 bridge | `172.16.103.0/24` | DC2 BD |
| `vnet-5.yaml` | L3 IRB | `172.16.151.0/24` | DC1 spoke |

## Apply

```bash
bash ~/eda-dci-lab/scripts/apply-clab-vnets.sh
```

After fabric integrate (pools, nodes). L3 vnets get IRB host-route patch; L2 vnets are pure bridge.

Edge interface labels remain in `services/l3/interface-labels/` and `services/l2/interface-labels/`.
