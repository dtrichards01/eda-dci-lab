# MAC-VRF anycast VTEP test (Talos #2)

Proven 2026-09-10 on `clab-srl-leaf-spine-dcgw`. Does **not** replace native vnet-1…5.

| Need | Result |
|------|--------|
| Which app | **Interfaces** defines `vtep.mode: Anycast` on the LAG. **Services** realizes it when the MAC-VRF attaches that LAG via **VLAN** (this test: `interfaceSelectors`) or **BridgeInterface**. Routing emits derived `DefaultLoopbackInterface` / `lo255`. |
| MH **host** for anycast **config** | **No** — ES + MAC-VRF is enough |
| MH **host** for LAG Up / LACP | **Yes** — `client-10-avtep` LACP bond |
| SingleActive + anycast | **No** — SRL: only all-active |
| L3 IRB on same LAG | **2026-09-11** `05-vnet-l3-irb.yaml` — VN **Up**, IRB `172.16.210.254/24` + `interface-less-routing`. |
| ES IFL-AD | **Not needed for L2.** **Needed for L3 IRB** so remotes can IP-alias IFL host routes to this ESI. EDA 26.8.1 does **not** emit it. Configlet `06-configlet-ifl-host-ad.yaml` (`mh-l2-avtep-ifl-host-ad`) — live on leaf-3/4 2026-09-11. Do **not** set `internal-tags` (unresolved tag-set takes the ES down). |

See `eda-dci` skill `reference.md` § Anycast VTEP and **IFL host AD** (canonical). **SRL only** — SROS DCI does not program anycast VTEP and **must not** receive this Configlet (WSL 2026-09-11).
