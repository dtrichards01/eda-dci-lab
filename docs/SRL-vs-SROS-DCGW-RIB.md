# SRL vs SROS: DCGW default NI, WAN IGP, and service next-hop

| | |
|---|---|
| **Status** | Canonical — read this when mixing “remote leaf /32s”, ISIS/OSPF, and wrong service NH |
| **Labs** | SRL `eda-dci-lab` NS `clab-srl-leaf-spine-dcgw` · SROS `eda-dci-sros-lab` NS `clab-3-tier-leaf-spine-dcgw` |
| **Last checked** | 2026-09-04 (SRL WAN = ISIS + SR-ISIS) |

Agent index: `~/.cursor/skills/eda-dci/SKILL.md` golden rules 5–6. Policy map: `docs/L3VPN-DCI-GUIDE.md` §2. Labs / WAN option 1 vs 2: `docs/DCI-OPTIONS.md`.

---

## The mix-up

`default` on a DCGW is **not** “the ISIS table” (or OSPF table). It is the **GRT**: host + connected + **WAN IGP** + **BGP**.

The SRL vs SROS difference we recorded was **BGP EVPN leak into that GRT**, not ISIS/OSPF learning leaf/spine `/32`s. Switching OSPF → ISIS did **not** change that.

---

## Three separate facts

### 1. WAN IGP table (OSPF then, ISIS now) — **same on SRL and SROS**

The IGP only has what is in the WAN domain: DCGW `system0`, PE `system0`, WAN ISL `/31`s.

| Prefix class | In ISIS / OSPF on local DCGW? |
|--------------|-------------------------------|
| Remote DCGW / PE `/32` | **Yes** (required — VPNv4 NH + SR-ISIS/LDP tunnel) |
| Remote **leaf / spine** `/32` | **No** (not in that IGP; no BGP→IGP redistribution) |

Live SRL `dcgw-1`: ISIS = `.8/.15–.18`. DC2 leaves `.9–.14` are **not** ISIS.

### 2. SRL vs SROS GRT (BGP) — **this is the original comparison**

| | SRL DCGW `default` | SROS DCGW Base |
|--|--------------------|----------------|
| Local leaf/spine `/32` | BGP (fabric eBGP) — expected | Local fabric — expected |
| Remote DCGW `/32` | ISIS/OSPF — expected | IGP — expected |
| Remote **leaf/spine** `/32` | Often present as **BGP** | **Not** present — SROS does not leak fabric EVPN onto WAN by default |

Unrestricted SRL WAN EVPN (import/export default Accept) installs **all** remote fabric EVPN. Those routes’ next-hop is a **remote leaf VTEP**, not the DCGW. Forwarding then tries to reach that VTEP **over the WAN MPLS/SR path** instead of VXLAN **inside** the remote DC → **wrong service next-hop**.

SROS did not need `reject-all-local-evpn` / `reject-all-remote-evpn` for that reason (skill golden rule 5). SRL **must** block fabric EVPN on WAN BGP (golden rule 6).

**Correct L3 stitch NH:** VPNv4 prefix → next-hop = **remote DCGW system IP** (`11.0.0.15` from dcgw-1) → tunnel **SR-ISIS** (live) or LDP (option 1) to that `/32`. `nextHopSelf: true` on WAN peers rewrites exported VPNv4 NH to the local DCGW, not a leaf VTEP.

**Do not** “accept all” on WAN import/export to inspect ISIS. That re-opens leak 2 and can break overlay NH. ISIS is already only the WAN `/32`s.

### 3. WAN IGP leaking **down** into local spines — **same OSPF and ISIS, SRL-only extra filter**

Remote DCGW/PE `/32`s **must** stay on the DCGW GRT (fact 1). Fabric eBGP on the DCGW (superSpine → spine) will **also** advertise protocol ISIS/OSPFv2 into `pod-1`/`pod-2` unless `reject-igp-to-fabric` is on **DCGW→spine export**.

That policy is **egress into the local DC**, not WAN ingress. It is **not attached** live (`pod-1`/`pod-2` `bgp.exportPolicies` empty as of 2026-09-04). It would **not** remove BGP-learned leaf `/32`s and would **not** change the ISIS LSDB.

SROS labs did not need this extra IGP export filter.

---

## How SRL WAN BGP blocks fabric EVPN (leak 2)

Both directions; default **Reject**; only stitch RTs accepted.

| Direction | Attachment | Statement | Effect |
|-----------|------------|-----------|--------|
| **Egress from each site** | WAN peer **export** (`export-dc-*-routes-and-add-soo`) | `reject-all-local-evpn` after L2 type-2/3 stitch Accept | Do not send local leaf/spine EVPN **out** |
| **Ingress into each site** | WAN peer **import** (`import-dci-services-dc-*`) | `reject-all-remote-evpn` after L2 type-2/3 + VPNv4 Accept | Do not install remote fabric EVPN **in** |

YAML: `services/dci-policies/policies/import-dci-services-dc-1.yaml`, `export-dc-1-routes-and-add-soo.yaml` (and DC2 twins).

2026-09-04: those CRs **are** attached, yet `dcgw-1` GRT still has DC2 `.9–.14` as **BGP** (fabric eBGP recirculation / residual). Treat **VPNv4 NH = remote DCGW** + TTM `sr-isis` as the service pass/fail, not “GRT has zero remote leaf `/32`s”.

---

## Pass / fail (L3)

This table is a **diagnostic lookup**. The **Fail** column is what a **broken** overlay looks like **if you see that symptom**. It is **not** a prediction that this lab will fail, and it is **not** “this prefix existing somewhere means L3 is down.”

Live SRL (2026-09-04) is a **pass**: VPNv4 NH = remote DCGW, tunnel SR-ISIS. Hub-spoke ping 0% loss.

**The original SRL bug** is only the VPNv4 row: stitch next-hop became a **remote leaf VTEP**, so the WAN tried SR/MPLS to a fabric VXLAN endpoint. That is a real overlay break **when that NH is in use**. Seeing remote leaf `/32`s in the SRL **GRT as BGP** is **not** that bug by itself — those prefixes can sit in `default` while overlay still passes.

| Check | What you are looking at | Pass (healthy lab) | Fail (broken overlay) | Is this the original SRL bug? |
|-------|-------------------------|--------------------|------------------------|-------------------------------|
| ISIS / OSPF | WAN IGP table on the local DCGW | Only remote DCGW and PE `/32`s (+ WAN ISLs) | Leaf or spine `/32` in the **IGP** | **No.** That would be BGP→IGP redistribution. Not this lab; not the original comparison. |
| VPNv4 stitch | Service route next-hop **and** tunnel to that NH | NH = remote **DCGW** `/32`; tunnel SR-ISIS (live) or LDP | NH = remote **leaf VTEP**; WAN tries MPLS/SR to that VTEP | **Yes.** This **is** the original SRL bug. If you see this NH, L3 **will** fail until NH is rewritten to the DCGW (`nextHopSelf` + WAN EVPN deny-lists). |
| SROS GRT | DCGW Base / `default` | No remote leaf/spine `/32` unless you added extra leak policy | Remote leaf `/32`s present (SROS started leaking fabric EVPN) | **No.** SROS did not show this; that was why SRL looked “full” and SROS did not. |
| SRL GRT | DCGW `default` | Remote leaf `/32` **may still appear as BGP**. That is **not** a fail on this row. | Do **not** score this row as fail just because those BGP prefixes exist. | **No** if they are only in GRT. **Yes** only if VPNv4 **uses** one as stitch NH (score the VPNv4 row). |

Score overlay from the **VPNv4** row, not from “is the GRT empty of remote leaf `/32`s.”

CLI: `docs/L3VPN-DCI-GUIDE.md` §5, `docs/SRL-DCI-WAN-IGP-Tech-Note.md` §7.
