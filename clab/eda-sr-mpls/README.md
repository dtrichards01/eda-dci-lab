# SR-MPLS label resources for WAN option 2 (IS-IS + SR-ISIS)

Used with `clab/eda-isis/`. Option 1 keeps `clab/eda-mpls-ldp/` (LDP).

| File | Contents |
|------|----------|
| `labelblocks.yaml` | Static SRGB `srgb-wan` (**18432–20431**; SROS X1b rejects start 16000) |
| `indexallocationpools.yaml` | `sr-node-sid-pool` (indexes 1–64) |

Node SID label = `18432 + index`. Apply via `scripts/apply-isis.sh` / `switch-wan-isis.sh`.

Live SIDs (Talos 2026-09-04): dcgw-1 `11.0.0.7`→18433, dcgw-2 `.8`→18434, dcgw-4 `.16`→18435, pe-1 `.18`→18436, dcgw-3 `.15`→18437, pe-2 `.17`→18438. Confirm: `info from state … isis instance … segment-routing mpls sid-database`.
