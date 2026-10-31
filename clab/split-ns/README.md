# Split-namespace DCI (`clab-srl-leaf-spine-dcgw` + `clab-srl-dcgw-wan`)

Same running CLAB (`~/3-tier-dci/clab-s-spine-spine-leaf-srl-only.yaml` on k0r4), onboarded into two EDA
namespaces on Talos #2 to validate both DCGW attachment models from the PRD:

| PRD option | Where | Model |
|------------|-------|-------|
| **Integrated** (26.4: combined DCGW/borderleaf) | `pod-1` in `clab-srl-leaf-spine-dcgw` | dcgw-1/2 are `borderLeafs` of Fabric `pod-1` |
| **Standalone**, different namespace, attached to the spine layer | dcgw-3/4 in `clab-srl-dcgw-wan` | Not in any Fabric. User `DefaultRouter`, eBGP underlay + iBGP EVPN (RR client of pod-2 spines) |

| Namespace | Nodes |
|-----------|-------|
| `clab-srl-leaf-spine-dcgw` | srl-leaf-1..8, srl-spine-1..4, dcgw-1/2, clients |
| `clab-srl-dcgw-wan` | dcgw-3/4, sros-pe-1/2 |

Cross-namespace links are not TopoLinks. Each end is an `Interface` + `DefaultInterface` in its own namespace.

| Link | Pod NS end | WAN NS end | Protocol |
|------|------------|------------|----------|
| dcgw-1 e1-5 - sros-pe-1 1/1/c1/1 | `192.168.210.0/31` | `.1` | IS-IS L2 + SR-MPLS |
| dcgw-2 e1-5 - sros-pe-1 1/1/c2/1 | `192.168.210.2/31` | `.3` | IS-IS L2 + SR-MPLS |
| srl-spine-3 e1-9 - dcgw-3 e1-1 | `192.168.220.0/31` | `.1` | eBGP underlay + iBGP EVPN (system0) |
| srl-spine-3 e1-10 - dcgw-4 e1-1 | `192.168.220.2/31` | `.3` | same |
| srl-spine-4 e1-9 - dcgw-3 e1-2 | `192.168.220.4/31` | `.5` | same |
| srl-spine-4 e1-10 - dcgw-4 e1-2 | `192.168.220.6/31` | `.7` | same |

Shared IS-IS domain, so pools must not overlap across namespaces:

| Pool | Pod NS | WAN NS |
|------|--------|--------|
| `systemipv4-pool` | `11.0.0.0/24` | `11.0.2.16/28` (PEs). dcgw-3 `11.0.2.3`, dcgw-4 `11.0.2.4` are static |
| `ipv4-pool` (ISL /31) | `12.0.0.0/16` | `12.1.0.0/16` |
| `sr-node-sid-pool` | index 1-64 | index 101-164 |

Services exist **only in the pod namespace**. The pod-2 DCI interconnects live in the WAN namespace with dcgw-3/4
and reference the service across namespaces (`nodeSelectors` only match nodes in the interconnect's own namespace):

```yaml
# wan/05-services.yaml
RouterInterconnect router-interconnect-vnet-2:   routerRef:       {name: router-2, namespace: clab-srl-leaf-spine-dcgw}
BridgeDomainInterconnect bd-interconnect-vnet-4: bridgeDomainRef: {name: bd-4,     namespace: clab-srl-leaf-spine-dcgw}
```

The RIC/BDI build router-2 / bd-4 on dcgw-3/4 themselves. Do not add copies of vnet-2 / vnet-4 in the WAN namespace
(an earlier build did; they had no interfaces and showed Unknown). EVI/VNI/RT stay pinned to the single-namespace values.

Values only known after the Fabrics come up (`${POD2_SPINE_AS}`, `${SPINE3_SYS}`, `${SPINE4_SYS}`,
`${DCGW1_SYS}`, `${DCGW2_SYS}`, PE port names) are written by the `vars` phase to `~/eda-rebuild/split-ns.vars`
and rendered by `scripts/split-ns-render.py`.

dcgw-3/4 underlay AS is **64906**, outside `asn-pool` (pool 100+ hands 106 to srl-leaf-4).

## Procedure (k0r4)

`scripts/split-ns-rebuild.sh <phase>`, one at a time:

| Phase | Does | Watch for |
|-------|------|-----------|
| `tenants-save` | Saves `Tenant` CRs + tenant-a/b VNETs, deletes the VNETs | Without this `remove` fails: tenant BridgeInterfaces depend on Tenants in the pod NS |
| `remove` | `clab-connector remove` (deletes the pod NS) | |
| `integrate` | Onboards pods and WAN topology files | SRL nodes moved to a **new** namespace stay `NotOnBoarded` (old cert, no discovery server). Fix below |
| `base` | ConfigMaps, pools, policy sets, Secret, artifacts, Discord CRs | |
| `labels` | Node/link roles, edge vnet labels, anycast LAG, tenant ports | |
| `fabric` | pod-1, pod-2, backbone-simulation; waits for Up | |
| `vars` | Spine AS, system IPs, PE port names | |
| `rest` | WAN plumbing, standalone DCGW peering, WAN BGP, services | |
| `tenants-restore` | Re-applies Tenants and tenant VNETs | |

**NotOnBoarded after namespace move:** patching `spec.onBoarded` is reverted. Re-enable the gNMI discovery
server so bootstrap can push new certs (EDA removes it again after onboarding):

```
docker exec -i dcgw-3 sr_cli <<'EOF'
enter candidate private
set / system grpc-server discovery admin-state enable
set / system grpc-server discovery network-instance mgmt
set / system grpc-server discovery port 50052
set / system grpc-server discovery default-tls-profile true
set / system grpc-server discovery metadata-authentication true
set / system grpc-server discovery services [ gnmi gnsi ]
commit now
EOF
```

Nodes that stay in the same namespace name (the pod NS) re-onboard on their own.

SROS PE-1 ports are `ethernet-1-a-1-1` / `ethernet-1-a-2-1` (the old `ethernet-1-1-1` name was an outlier).

Validate: `scripts/validate-dci-split.sh` (exit code = failed checks). 2026-10-31: **9/9 pass**, WAN BGP + SR-ISIS up on both DCGW pairs.

**Transient cross-DC loss (2026-10-31 16:13–16:2x):** all DCI checks failed once while local checks passed. dcgw-3 IS-IS
adjacency to PE-2 re-formed at 16:13:53, then dcgw-1↔dcgw-3 WAN BGP hit HOLDTIME at 16:16:46. k0r4 load average was
25–41. Recovered without changes (60-ping runs 0% loss, then 9/9). If DCI fails with every session Established, check
`show network-instance default protocols isis adjacency` last-transition times and the host load before touching config.
