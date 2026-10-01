# EDA topology CRs — `clab-srl-leaf-spine-dcgw`

Manual **Interface + TopoLink** bundle for when **clab-connector** integration is wrong or stale (breakouts, re-import after `clab destroy` / redeploy).

**Edge service labels** (vnet selectors, MH LAGs) are **not** here — they live in `services/*/interface-labels/` and are applied by `scripts/apply-edge-interfaces.sh`.

## Files

| File | Contents |
|------|----------|
| `interfaces-isl.yaml` | Fabric ISL Interface CRs (`interSwitch`) |
| `topolinks-isl.yaml` | Leaf↔spine, dcgw↔spine, dcgw mesh |
| `interfaces-wan.yaml` | dcgw↔sros-pe ports |
| `topolinks-wan.yaml` | WAN TopoLinks |
| `topolinks-edge.yaml` | Linux clients → leaf (no client Interface CRs) |
| `gen_clab_eda_cr.py` | Regenerator (reads `clab-leaf-spine-dcgw-srl-only.yaml`) |

**Related (exported from cluster):**

| Path | Contents |
|------|----------|
| `../eda-fabric/` | 3 Fabric CRs + 6 ISL CRs (DCGW mesh / PE WAN) |
| `../eda-mpls-ldp/` | LabelBlock, DefaultLDPRouter, DefaultLDPInterface |
| `../eda-wan-bgp/` | DefaultBGPGroup + DefaultBGPPeer (dcgw 1–4 WAN) |
| `../eda-vnets/` | VirtualNetwork `vnet-1` .. `vnet-5` |

## Regenerate

```bash
cd ~/eda-dci-lab
python3 clab/eda-topology/gen_clab_eda_cr.py
```

## Apply order (after CLAB deploy + EDA integrate)

```bash
cd ~/eda-dci-lab
bash scripts/apply-fabric-mpls.sh      # fabrics + MPLS/LDP + ISL CRs
bash scripts/apply-topology-cr.sh
bash scripts/apply-edge-interfaces.sh   # vnet / MH labels on edge ports
bash scripts/apply-all.sh               # or apply-sh-dci / apply-mh-dci as needed
```

If old TopoLinks from a prior import conflict, delete stale CRs first:

```bash
kubectl get topolinks -n clab-srl-leaf-spine-dcgw
# kubectl delete topolink <name> -n clab-srl-leaf-spine-dcgw
```

## Naming

| CLAB endpoint | EDA interface (CR) |
|---------------|------------------|
| `srl-leaf-1:e1-5` | `ethernet-1-5` on node `srl-leaf-1` |
| `client-1-vnet-1-dc1:eth1` | `eth1` (TopoLink remote, no Interface CR) |
| `dcgw-1:e1-5` | `ethernet-1-5` |
| `sros-pe-1:1/1/c1/1` | `1-1-c1-1` |

ISL TopoLinks use **spine = local**, leaf/dcgw = remote.

## MH e1-10 ports

Do **not** create standalone `srl-leaf-N-ethernet-1-10` Interface CRs. MH **LAG** CRs own `e1-10` members; TopoLinks still use `interfaceResource: srl-leaf-N-ethernet-1-10`. After topology apply, run `scripts/cleanup-stale-edge-interfaces.sh` if standalone e1-10 CRs appear.

## Related (different lab)

The **ai-topo-multi-plane** breakout lab uses `C:\Users\darrenri\Documents\clab-ai-topo-multi-plane-eda\` (namespace `clab-ai-topo-multi-plane`). Do not mix bundles. Backend overlay RouteLeaking vs EVPN, with pros/cons: `docs/AI-Backend-Overlay-RouteLeak-vs-EVPN.md` in that repo.
