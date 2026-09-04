# Fabric and WAN ISL CRs — `clab-srl-leaf-spine-dcgw`

Exported from live EDA cluster. These define the **three fabrics** and **manual ISL** objects (DCGW↔DCGW mesh, DCGW↔PE WAN) — separate from TopoLink ISLs in `eda-topology/`.

## Files

| File | Contents |
|------|----------|
| `fabrics.yaml` | `backbone-simulation`, `pod-1`, `pod-2` (**do not apply whole file** — live backbone pool is `wan-interface-ipv4-pool`) |
| `isls.yaml` | Option 1 — 6 ISL CRs, **OSPF on / ISIS off** (dcgw mesh + dcgw↔X1b PE) |
| `isls-isis.yaml` | Option 2 (live) — same six ISLs, **ISIS on / OSPF off**; PE side `isis-instance-backbone` (Fabric does not emit a PE instance) |

WAN IGP cutover (does not wipe vnets/RIC): `scripts/switch-wan-ospf.sh` / `scripts/switch-wan-isis.sh`. Tech note: `docs/SRL-DCI-WAN-IGP-Tech-Note.md`.

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
