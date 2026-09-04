# WAN underlay isolation (vnet-1 / vnet-2) — priority fix before RIC tuning.
#
# Canonical explanation (GRT vs ISIS vs SROS): docs/SRL-vs-SROS-DCGW-RIB.md
#
# Problem: SRL DCGW default NI (GRT) shows ALL remote leaf/spine system IPs (11.0.0.x) as BGP.
# SROS DCGW only shows local fabric + remote DCGW system IPs.
# This is WAN EVPN leak, not OSPF/ISIS. Wrong service NH = remote leaf VTEP.
#
# Cause (typical on SRL):
#   1. import-dci-services-dc-* default Accept → accepts full remote EVPN
#   2. export-dc-*-prefixes default Accept → sends local fabric EVPN (types 1–5)
#   3. nextHopSelf only changes BGP NH attribute; EVPN still carries VTEP/mac-nh
#
# Test order:
#   A) Phase 1 — VPNv4 only on WAN (disable EVPN AF on peers) + strict import/export
#   B) Phase 2 — re-enable EVPN on WAN with type-5 only if VPNv4 alone works
#
# Apply:
#   bash scripts/apply-dci-underlay-isolation-draft.sh
# Revert:
#   bash scripts/revert-dci-underlay-isolation-draft.sh

## Phase 1 validation on dcgw-1 (default NI)

After apply, remote side should be **only dcgw-3 / dcgw-4 system IPs**, not DC2 leaves.

```text
show network-instance default route-table summary
show network-instance default route-table 11.0.0.11
show network-instance default protocols bgp routes evpn neighbor <wan-peer-ip> summary
show network-instance default protocols bgp routes vpn-ipv4 summary
```

**Pass:** EVPN from WAN neighbor ≈ 0 (or no remote leaf RDs).  
**Pass:** VPNv4 routes NH = remote **DCGW** system IP.  
**Fail:** EVPN type-1/2/3/4/5 from WAN with RD 11.0.0.11:103 etc.

## BGP peers (all four WAN sessions must match)

| Peer | Role |
|------|------|
| dcgw-1-dcgw-3-bgp-peer | DC1 primary or secondary |
| dcgw-2-dcgw-4-bgp-peer | DC1 secondary |
| dcgw-3-dcgw-1-bgp-peer | DC2 |
| dcgw-4-dcgw-2-bgp-peer | DC2 |

Each needs: tight **import** + **export**, `nextHopSelf: true` (you already have this).

Phase 1 also sets `l2VPNEVPN.enabled: false` on WAN peers (VPNv4 only).

## Policy files (draft/underlay/)

| File | Replaces CR name |
|------|------------------|
| `import-dci-services-dc-1-underlay.yaml` | `import-dci-services-dc-1` |
| `import-dci-services-dc-2-underlay.yaml` | `import-dci-services-dc-2` |
| `export-dc-1-prefixes-underlay.yaml` | `export-dc-1-prefixes-and-add-soo` (your live name) |
| `export-dc-2-prefixes-underlay.yaml` | match your DC2 export policy name |

If DC2 export policy name differs, patch peer exportPolicies manually after applying DC2 yaml
(copy structure, keep your CR name).
