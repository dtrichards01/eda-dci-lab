# WAN BGP — DCGW inter-DC peering

Exported **DefaultBGPPeer** and **DefaultBGPGroup** CRs for the four DCGW WAN links.

## Files

| File | Contents |
|------|----------|
| `defaultbgpgroups.yaml` | `default-bgp-group-dc-1`, `default-bgp-group-dc-2` |
| `defaultbgppeers.yaml` | `dcgw-1-dcgw-3`, `dcgw-2-dcgw-4`, `dcgw-3-dcgw-1`, `dcgw-4-dcgw-2` |

Peers use VPNv4 (`vpnIPv4Unicast: true`), EVPN disabled, `nextHopSelf: true`, and reference WAN import/export policies.

**Note:** `scripts/apply-dci-policies.sh` also patches these peers with JSON patches. Apply this file first for full CR spec; policy script aligns policy names if needed.

## Apply

```bash
bash ~/eda-dci-lab/scripts/apply-wan-bgp.sh
```

Before DCI RIC stitch (`apply-l3-dci.sh`) and after fabric/MPLS underlay is up.
