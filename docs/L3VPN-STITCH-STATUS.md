# L3 VPN stitch — status pointer

**Full policy map + WAN fabric isolation:** `docs/L3VPN-DCI-GUIDE.md`

Validated on cluster (2026-08-04):

- vnet-1 ↔ vnet-2 hub (IPVPN RIC + WAN VPNv4)
- vnet-5 ↔ vnet-2 hub-spoke (RT 102 + `multi-rt-import`)
- WAN: VPNv4 only, MPLS/LDP between DCGW system IPs
- Fabric EVPN / VTEP / system routes: **not** advertised on WAN (see guide §2)

EVPN control-plane trial: sibling repo `eda-dci-evpn-lab`.
