# Edge interface matrix — `clab-leaf-spine-dcgw-srl-only.yaml`

Maps each CLAB client to EDA `Interface` CR and VirtualNetwork selector labels.

## Native L3/L2 (encap Null)

**Operational Talos (2026-08-24)** — 8-client lab `~/3-tier-dci/clab-s-spine-spine-leaf-srl-only.yaml`. Short docker names `client-1`…`client-8`. L3 stitch RTs: vnet-1 `1:100`, hub vnet-2 `1:101` + `importPolicy: multi-rt-import`, vnet-5 `1:105`. Hub community set `vpn-import-rts` = `1:100` + `1:105` (`matchSetOptions: Any`).

| Live docker | VNet | IP (now) | Interface CR | Leaf port |
|-------------|------|----------|--------------|-----------|
| client-1 | vnet-1 | 172.16.101.1 | `srl-leaf-1-ethernet-1-5` | leaf-1 e1-5 |
| client-2 | vnet-1 | 172.16.101.2 | `srl-leaf-2-ethernet-1-6` | leaf-2 e1-6 |
| client-5 | vnet-2 hub | 172.16.201.1 | `srl-leaf-5-ethernet-1-5` | leaf-5 e1-5 |
| client-6 | vnet-2 hub | 172.16.201.2 | `srl-leaf-6-ethernet-1-6` | leaf-6 e1-6 |
| client-4 | vnet-5 spoke | 172.16.201.2 (should be 151.1) | `srl-leaf-4-ethernet-1-5` | leaf-4 e1-5 |
| client-3 | vnet-3 L2 | 172.16.201.1 (should be 103.x) | `srl-leaf-3-ethernet-1-5` | leaf-3 e1-5 |
| client-7 | vnet-4 L2 | 172.16.105.1 | `srl-leaf-7-ethernet-1-5` | leaf-7 e1-5 |
| client-8 | unlabeled | 172.16.105.2 | `srl-leaf-8-ethernet-1-5` | leaf-8 e1-5 |

Working ping matrix: vnet-1 (client-1/2) ↔ vnet-2 (client-5/6) both ways; vnet-2 → vnet-5 IRB `172.16.151.254`; no path vnet-1 ↔ vnet-5. No container currently holds `172.16.151.x`.

Expanded 13-client YAML uses long names; native ports match the live labels above.

| Expanded client | VNet | Label key | Interface CR | Leaf port |
|-----------------|------|-----------|--------------|-----------|
| client-1-vnet-1-dc1 | vnet-1 | `eda.nokia.com/vnet-1=vlan-bd-1` | `srl-leaf-1-ethernet-1-5` | leaf-1 e1-5 |
| client-2-vnet-1-dc1 | vnet-1 | same | `srl-leaf-2-ethernet-1-6` | leaf-2 e1-6 |
| client-3-vnet-2-dc2 | vnet-2 | `eda.nokia.com/vnet-2=vlan-bd-2` | `srl-leaf-5-ethernet-1-5` | leaf-5 e1-5 |
| client-4-vnet-2-dc2 | vnet-2 | same | `srl-leaf-6-ethernet-1-6` | leaf-6 e1-6 |
| client-5-vnet-5-dc1 | vnet-5 | `eda.nokia.com/vnet-5=vlan-bd-5` | `srl-leaf-4-ethernet-1-5` | leaf-4 e1-5 |
| client-6-vnet-3-dc1 | vnet-3 | `eda.nokia.com/vnet-3=vlan-bd-3` | `srl-leaf-3-ethernet-1-5` | leaf-3 e1-5 |
| client-7-vnet-4-dc2 | vnet-4 | `eda.nokia.com/vnet-4=vlan-bd-4` | `srl-leaf-7-ethernet-1-5` | leaf-7 e1-5 |

Files: `services/l3/interface-labels/edge-l3-vnet-*.yaml`, `services/l2/interface-labels/edge-l2-vnet-3-4.yaml`

## Stretched-homed L3 (encap Null)

| Client | VNet | Label | Interface CR | Leaf port |
|--------|------|-------|--------------|-----------|
| client-8-dc1-sh | vnet-6 | `eda.nokia.com/vnet-6=vlan-bd-6` | `srl-leaf-3-ethernet-1-6` | leaf-3 e1-6 |
| client-9-dc2-sh | vnet-7 | `eda.nokia.com/vnet-7=vlan-bd-7` | `srl-leaf-5-ethernet-1-6` | leaf-5 e1-6 |

Files: `services/l3/interface-labels/edge-sh-vnet-6-7.yaml`, `services/l3/vnet-6/`, `services/l3/vnet-7/`

Cross-DC stitch for `155.x` ↔ `156.x` is in repo (`router-interconnect-vnet-6/7`).

## Multi-homed ESI LAG (encap Dot1q, type lag)

| Client | ES | Mode | Interface CR | Leaves e1-10 | VLAN services |
|--------|-----|------|--------------|--------------|-----------------|
| client-10-dc1-mh | mh-dc1a | all-active | `mh-dc1a-lag-leaf-3-4` | leaf-3 + leaf-4 | `vnet-mh-l3-dc1a` |
| client-11-dc2-mh | mh-dc2a | all-active | `mh-dc2a-lag-leaf-5-6` | leaf-5 + leaf-6 | `vnet-mh-l3-dc2a` |
| client-12-dc1-mh | mh-dc1b | single-active | `mh-dc1b-lag-leaf-1-2` | leaf-1 + leaf-2 | `vnet-mh-l3-dc1b` |
| client-13-dc2-mh | mh-dc2b | single-active | `mh-dc2b-lag-leaf-7-8` | leaf-7 + leaf-8 | `vnet-mh-l3-dc2b` |

Files: `services/mh/interface-labels/edge-mh-lags.yaml`, `services/mh/virtualnetwork-vnet-mh-l3-*.yaml`

MH LAG labels (two per LAG): `eda.nokia.com/role=edge` + one per-ES vnet selector:

| VNet CR | Selector label | Leaves | VLAN | Subnet |
|---------|----------------|--------|------|--------|
| vnet-mh-l3-dc1a | `eda.nokia.com/vnet-mh-l3-dc1a=vlan-bd-mh-200-dc1a` | 3, 4 | 200 | 10.200.1.0/24 |
| vnet-mh-l3-dc1b | `eda.nokia.com/vnet-mh-l3-dc1b=vlan-bd-mh-200-dc1b` | 1, 2 | 200 | 10.200.1.0/24 |
| vnet-mh-l3-dc2a | `eda.nokia.com/vnet-mh-l3-dc2a=vlan-bd-mh-200-dc2a` | 5, 6 | 200 | 10.200.2.0/24 |
| vnet-mh-l3-dc2b | `eda.nokia.com/vnet-mh-l3-dc2b=vlan-bd-mh-200-dc2b` | 7, 8 | 200 | 10.200.2.0/24 |

Cross-DC MH L3 — `router-interconnect-mh-l3-*` (RT 430 ↔ 431). Those L3 MH LAGs do **not** enable anycast VTEP (L2 MAC-VRF only).

## Anycast VTEP + L3 IFL-AD (AllActive LAG across switches)

**Trigger:** an **AllActive LAG with members on different switches** + MAC-VRF `vtep.mode: Anycast`. Not a dual-homed host, not SingleActive, not BDI.

**Apps:** **Interfaces** owns the knob (`Interface.spec.lag.multihoming.vtep`). **Services / VirtualNetwork** programs it when the MAC-VRF attaches that LAG — **VLAN** (`interfaceSelectors`, as in `vnet-mh-l2-avtep`) or **BridgeInterface** (`spec.interface:` the LAG). Same anycast either way. A direct ethernet Interface on the VNET does not. **Routing** `DefaultLoopbackInterface` is derived (`lo255`).

**SRL vs SROS:** anycast VTEP is **SRL-only**. SROS DCI (#3 WSL, 2026-09-11) has no MH LAG and no `anycast-multi-homing` on the DCGW. **Do not copy** `06-configlet-ifl-host-ad.yaml` to SROS (SRL YANG path). Canonical: `~/.cursor/skills/eda-dci/reference.md`.

| Item | Live 2026-09-10 (#2) |
|------|--------|
| LAG | `mh-l2-avtep-lag-leaf-3-4` leaf-3 + leaf-4 `e1-10` |
| VNET | `vnet-mh-l2-avtep` (untagged MAC-VRF) |
| Anycast IP | `10.9.9.1/32` on `lo255` both leaves |
| Host | `client-10-avtep` LACP bond — needed for LAG **Up** only; anycast config existed while LAG was Down |
| YAML | `services/mh/anycast-macvrf-test/` |
| `advertise-ifl-host-ad-routes` | **L2: not needed.** **L3 IRB: needed**, EDA does not emit it. Configlet `06-configlet-ifl-host-ad.yaml` set it on leaf-3/4 (2026-09-11). IRB still has `interface-less-routing`. |

Do not set `vtep.mode: Anycast` on SingleActive (SRL: all-active only). SROS does not support this.

## Removed (obsolete stretched legs)

| Old CR | Was | Replaced by |
|--------|-----|-------------|
| `edge-l3-vnet-1-dc2.yaml` | vnet-1 on leaf-8 e1-6 | vnet-4 L2 on same port |
| `edge-l3-vnet-2-dc1.yaml` | vnet-2 on leaf-3 e1-5 | vnet-5 on same port |
| `srl-leaf-5-ethernet-1-6` | vnet-4 L2 wrong leaf | `srl-leaf-8-ethernet-1-6` (vnet-4) + `srl-leaf-5-ethernet-1-6` (vnet-7 SH) |
| `srl-leaf-{N}-ethernet-1-10` | standalone MH physical | MH LAG CRs (`mh-dc*a/b-lag-*`) own e1-10 members |
| `srl-leaf-{2,6,7}-ethernet-1-5` | no CLAB client | removed — only leaf-1/3/4/5/8 have e1-5 clients |

## Apply

```bash
bash ~/eda-dci-lab/scripts/sync-repo-to-talos.sh   # WSL — sync repo to Talos
bash ~/eda-dci-lab/scripts/cleanup-stale-edge-interfaces.sh
bash ~/eda-dci-lab/scripts/cleanup-mh-stale.sh     # removes orphan MH YAML at repo root
bash ~/eda-dci-lab/scripts/apply-edge-interfaces.sh
```

Or `bash ~/eda-dci-lab/scripts/apply-all.sh` on Talos.
