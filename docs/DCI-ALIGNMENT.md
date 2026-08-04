# DCI lab alignment — target vs cluster vs repo



Last checked against Talos `clab-srl-leaf-spine-dcgw` (native-per-DC + hub/spoke).

**Scope:** Lab and demo only. L3 IPVPN hub-spoke is validated in this environment; L2 hybrid WAN EVPN and combined L2+L3 on the same WAN peers are **not recommended for production** — see `docs/L3VPN-DCI-GUIDE.md` § Lab / demo vs production.

---



| Item | Value |

|------|-------|

| Repo YAML | `clab/clab-leaf-spine-dcgw-srl-only.yaml` |

| Talos path (planned) | `~/3-tier-dci/clab-leaf-spine-dcgw-srl-only.yaml` |

| Legacy (5 clients) | `clab/clab-s-spine-spine-leaf-srl-only.yaml` — deprecated |

| Validation notes | `docs/CLAB-VALIDATION.md`, `docs/EDGE-INTERFACES.md` |



**Clients:** 7 native (hub/spoke + L2) + 2 SH (`vnet-6`/`vnet-7`) + 4 MH ES (2 all-active, 2 single-active on `e1-10`). CLAB `service:` label matches VirtualNetwork CR name.



MH client scripts: `clab/configs/base-configs/mh-dc1a.sh` … `mh-dc2b.sh` — **L3 only**, VLAN `200`; subnets `10.200.1.0/24` (DC1) / `10.200.2.0/24` (DC2). Four per-ES VirtualNetworks (`vnet-mh-l3-dc1a/b`, `vnet-mh-l3-dc2a/b`).




## Two policy layers (not interchangeable)



| Layer | Where | Mechanism | Role |

|-------|-------|-----------|------|

| **Stitch select** | `RouterInterconnect` / `BridgeDomainInterconnect` | `exportTarget` + `importTarget` **or** `importPolicy` | Which VPN routes enter/leave each service MPLS leg |

| **WAN exchange** | DCI `DefaultBGPPeer` | `import-dci-services-dc-*`, `export-wan-*`, `export-dc-*-soo` | What crosses DCGW↔DCGW BGP; loop avoidance (`tag-10`/`tag-20`), SOO |



Spokes use **`importTarget` / `exportTarget`** on RIC CRs. Hub vnet-2 uses **`importPolicy: multi-rt-import`** with community set `vpn-import-rts` (RT `100` + `102`). EDA allows **either** `importTarget`/`exportTarget` **or** `importPolicy`/`exportPolicy` on a single RIC — not both.

**WAN policies:** Hybrid VPNv4 (L3) + selective EVPN type-2/3 (L2 RT 300/301). See `docs/L3VPN-DCI-GUIDE.md` and `docs/L2-DCI-GUIDE.md`.



## Target service model



| VNet | Tier | Native DC | Subnet | Stitch export RT | Cross-DC peer |

|------|------|-----------|--------|--------------------|---------------|

| vnet-1 | L3 IRB | DC1 | `172.16.101.0/24` | `target:1:100` | vnet-2 hub (`201.x`) |

| vnet-2 | L3 IRB | DC2 (hub) | `172.16.201.0/24` | `target:1:101` | vnet-1 + vnet-5 |

| vnet-5 | L3 IRB spoke | DC1 | `172.16.151.0/24` | `target:1:102` | vnet-2 hub only |

| vnet-3 | L2 BD | DC1 | `172.16.103.0/24` | `target:1:300` (BDI) | vnet-4 (`103.2`) |

| vnet-4 | L2 BD | DC2 | `172.16.103.0/24` | `target:1:301` (BDI) | vnet-3 (`103.1`) |

| vnet-6 | L3 SH | DC1 | `172.16.155.0/24` | `target:1:400` | vnet-7 (`156.x`) |

| vnet-7 | L3 SH | DC2 | `172.16.156.0/24` | `target:1:401` | vnet-6 (`155.x`) |

| vnet-mh-l3-dc1a | L3 MH | DC1 | `10.200.1.0/24` | `target:1:430` | vnet-mh-l3-dc2a/b |
| vnet-mh-l3-dc1b | L3 MH | DC1 | `10.200.1.0/24` | `target:1:430` | vnet-mh-l3-dc2a/b |
| vnet-mh-l3-dc2a | L3 MH | DC2 | `10.200.2.0/24` | `target:1:431` | vnet-mh-l3-dc1a/b |
| vnet-mh-l3-dc2b | L3 MH | DC2 | `10.200.2.0/24` | `target:1:431` | vnet-mh-l3-dc1a/b |



**Hub vnet-2:** `exportTarget target:1:101` + **`importPolicy multi-rt-import`** (spoke RTs `100` + `102` via `vpn-import-rts`).



**L3 cross-DC:** different subnets (`101.x` ↔ `201.x` ↔ `151.x`) — routing via DCI + hub.  

**L2 cross-DC:** same subnet `103.x` — pure L2, no IRB between vnet-3 and vnet-4.



## Hub/spoke import path (vnet-2 ← vnet-1 + vnet-5)



```

DC1 dcgw RIC vnet-1  export RT 100 ──WAN VPNv4──► DC2 dcgw RIC vnet-2  multi-rt-import (100+102) ─► router-2

DC1 dcgw RIC vnet-5  export RT 102 ──WAN VPNv4──► DC2 dcgw RIC vnet-2  multi-rt-import (100+102) ─► router-2

```



Spoke isolation: vnet-1 RIC `importTarget 101` only; vnet-5 RIC `importTarget 101` only — neither imports the other spoke RT.



## Repo apply order

```bash
bash ~/eda-dci-lab/scripts/sync-repo-to-talos.sh   # from WSL — sync files first
bash ~/eda-dci-lab/scripts/apply-all.sh            # on Talos
```

`apply-all.sh` runs cleanup (stale edges, MH orphans, obsolete policies) then L3/L2/SH/MH, edges, policies.

Manual steps:

```bash
bash ~/eda-dci-lab/scripts/cleanup-stale-edge-interfaces.sh
bash ~/eda-dci-lab/scripts/cleanup-mh-stale.sh
bash ~/eda-dci-lab/scripts/cleanup-obsolete-dci.sh
bash ~/eda-dci-lab/scripts/apply-dci-policies.sh
bash ~/eda-dci-lab/scripts/apply-l3-dci.sh
bash ~/eda-dci-lab/scripts/apply-l2-dci.sh
bash ~/eda-dci-lab/scripts/apply-sh-dci.sh
bash ~/eda-dci-lab/scripts/apply-mh-dci.sh
bash ~/eda-dci-lab/scripts/apply-vnet-5-hub-spoke.sh
bash ~/eda-dci-lab/scripts/apply-edge-interfaces.sh
bash ~/eda-dci-lab/scripts/test-l3-cross-dc-ping.sh
bash ~/eda-dci-lab/scripts/test-l2-cross-dc-ping.sh
```

Do **not** apply `services/l2/bridge-domain-deployments/` — use BDI reciprocal RT import only (`docs/L2-DCI-GUIDE.md`). `apply-dcgw-import-routers.sh` runs cleanup instead.

## Cluster alignment (2026-08-04)

| Resource | Expected |
|----------|----------|
| L3 hub-spoke | vnet-1 ↔ vnet-2 and vnet-5 ↔ vnet-2 **working** (IPVPN RIC + VPNv4 WAN) |
| L2 vnet-3 ↔ vnet-4 | BDI + hybrid WAN EVPN type-2/3 (RT 300/301) — see `L2-DCI-GUIDE.md` |
| VirtualNetworks | vnet-1…7 Up; `vnet-mh-l3-dc1a/dc2a` Up; `vnet-mh-l3-dc1b/dc2b` Degraded (single-active standby) |
| MH LAGs | All four `mh-dc*a/b-lag-*` Up |
| MH RICs | `router-interconnect-mh-l3-dc1a/b`, `dc2a/b` Up |
| Edge interfaces | 9 native/SH + 4 MH LAGs — see `docs/EDGE-INTERFACES.md` |
| Removed | `vnet-mh-l2-*`, aggregated `vnet-mh-l3-dc1/dc2`, orphan `srl-leaf-{2,6,7}-e1-5`, standalone `e1-10` physical CRs |



## Removed (obsolete)



- Interconnect policies: `import-dci-interconnect`, `export-dci-interconnect-native-*`, `dci-interconnect-import-only-export`
- Stretched RIC legs: `router-interconnect-vnet-*-dc*-import`
- Remote `RouterDeployment` for L3 (native model uses RIC only; hub import via `multi-rt-import`)
- MH L2: `vnet-mh-l2-100/110`, BDI `bd-interconnect-mh-l2-*`, BD deployments `dcgw-*-bd-mh-*`
- Aggregated MH L3: `vnet-mh-l3-dc1/dc2` (replaced by per-ES `vnet-mh-l3-dc1a/b`, `dc2a/b`)


