# Response to RFP: DCI Model and Implementation in Nokia EDA

**Document:** [RFP reference]  
**Respondent:** [Organisation name]  
**Date:** 10 August 2026  
**Classification:** [Commercial in confidence]

---

## 1. Executive summary

[Organisation] proposes a **declarative, policy-driven DCI architecture** implemented on **Nokia Event-Driven Automation (EDA)**. The solution interconnects two or more datacentre sites using **DC Gateway (DCGW)** nodes at each site edge, with **site-local fabric** (EVPN-VXLAN on leaf/spine) and **inter-site WAN** transport (MPLS/LDP with BGP VPN-IPv4 and, where required, selective EVPN).

EDA provides:

- **Intent-based configuration** via Kubernetes custom resources (CRs)
- **Separation of service design** (Virtual Networks, interconnects) from **routing policy** (BGP, community sets, SOO/tags)
- **Multi-platform support** — SR Linux and SR OS DCGWs under a single automation domain
- **Operational consistency** — GitOps-style manifests, repeatable apply workflows, and transaction-based change control

We recommend a **phased implementation**: L3 hub-spoke DCI first (production-aligned), with optional L2 extension and multi-homed access as later phases subject to platform validation and customer risk acceptance.

---

## 2. Understanding of requirements

We understand the requirement to:

| # | Requirement area | Our interpretation |
|---|------------------|-------------------|
| 1 | **Multi-site connectivity** | Extend L3 and/or L2 services across geographically separated DCs with controlled route exchange |
| 2 | **Service isolation** | Distinct virtual networks (tenants/services) with hub-spoke, any-to-any, or L2 extension models |
| 3 | **WAN transport** | MPLS-enabled DCGW interconnect with loop prevention and fabric/WAN control-plane separation |
| 4 | **Automation** | Centralised design, provisioning, and lifecycle via EDA — not per-device CLI |
| 5 | **Platform flexibility** | Support for Nokia SR Linux and/or SR OS at the DCGW edge |
| 6 | **Operations** | Validated designs, documented policies, test plans, and handover artefacts |

---

## 3. Proposed DCI reference model

### 3.1 Logical architecture

Each datacentre comprises:

```
┌─────────────────────────────────────────────────────────┐
│  DC1 / DC2                                              │
│  ┌──────────┐   EVPN-VXLAN    ┌──────────┐             │
│  │  Leaves  │◄───────────────►│  Spines  │             │
│  └────┬─────┘                 └────┬─────┘             │
│       │                            │                    │
│       └────────────┬───────────────┘                    │
│                    ▼                                    │
│              ┌──────────┐                               │
│              │   DCGW   │  service NI + WAN NI         │
│              └────┬─────┘                               │
└───────────────────┼─────────────────────────────────────┘
                    │  MPLS / LDP
                    │  BGP VPN-IPv4 (+ selective EVPN for L2)
                    ▼
              ┌──────────┐
              │ Peer DCGW│
              └──────────┘
```

**Two policy layers** (not interchangeable):

| Layer | EDA objects | Function |
|-------|-------------|----------|
| **Stitch selection** | `RouterInterconnect`, `BridgeDomainInterconnect` | Selects which VPN routes are exported/imported between the **service network instance** and the **WAN interconnect instance** on each DCGW |
| **WAN exchange** | `DefaultBGPPeer` + routing policies | Controls what crosses the **DCGW ↔ DCGW** BGP session; enforces RT allow-lists, SOO, and import/export tags for loop prevention |

### 3.2 Control-plane model by service tier

| Service tier | Fabric (intra-DC) | DCGW stitch | WAN (inter-DC) |
|--------------|-------------------|-------------|----------------|
| **L3 (IRB)** | EVPN-VXLAN on leaves | `RouterInterconnect` — IPVPN or EVPN per platform | VPN-IPv4 (stitch RTs) |
| **L2 (bridge domain)** | EVPN-VXLAN | `BridgeDomainInterconnect` | Selective EVPN type-2/3 (stitch RTs) |
| **L3 multi-homed access** | EVPN ES + LAG | Per-ES `RouterInterconnect` | VPN-IPv4 per stitch RT |

### 3.3 Supported DCI topologies

| Topology | Use case | EDA implementation |
|----------|----------|-------------------|
| **Any-to-any L3** | Equal DC extension | Paired RICs with reciprocal import/export targets |
| **Hub-and-spoke L3** | Centralised services in hub DC; spokes reach hub only | Hub RIC uses multi-RT import; spokes target hub RT only |
| **L2 extension** | Same subnet across DCs | BDI + WAN EVPN type-2/3 with dedicated stitch RTs |
| **Single-homed L3** | Simple cross-DC subnet pairs | Standard RIC per vnet |
| **Multi-homed L3** | All-active or single-active ES | One VirtualNetwork per Ethernet segment; dedicated stitch RTs |

---

## 4. EDA implementation approach

### 4.1 Design principles

1. **Namespace per fabric context** — each CLAB/production fabric runs in a dedicated EDA Kubernetes namespace.
2. **Declarative CRs** — topology, fabrics, virtual networks, interconnects, BGP peers, and policies are version-controlled YAML.
3. **Route-target discipline** — one distinct stitch RT per service/interconnect; documented community sets.
4. **Fabric/WAN isolation** — WAN BGP carries only stitch prefixes; fabric EVPN (system IPs, VTEPs, IMET) is blocked on WAN (SRL) or constrained by positive allow-lists (SROS).
5. **Loop prevention** — SOO and import/export tags (`tag-10`/`tag-20`) on redundant WAN paths.

### 4.2 EDA resource stack (apply order)

| Phase | EDA resources | Purpose |
|-------|---------------|---------|
| 1 | `NetworkTopology`, `TopoNode`, `TopoLink`, `Interface` | Physical/logical topology |
| 2 | `Fabric`, `DefaultOSPFInstance`, MPLS/LDP CRs | Underlay + label distribution |
| 3 | `VirtualNetwork`, IRB/routed interfaces, bridge domains | Service definition |
| 4 | `RouterInterconnect` / `BridgeDomainInterconnect` | DCI stitch at DCGW |
| 5 | `DefaultBGPGroup`, `DefaultBGPPeer` | WAN BGP sessions |
| 6 | Routing policies, community sets, tag sets | WAN import/export rules |
| 7 | Client edge labels / interfaces | Access attachment |

Changes are applied via **EDA transactions** for atomic, auditable updates.

### 4.3 Platform variants

| Platform | RIC control plane | RT format | WAN fabric isolation |
|----------|-------------------|-----------|----------------------|
| **SR Linux DCGW** | `controlPlane: IPVPN` | `target:1:NNN` | Explicit `reject-all-local/remote-evpn` on WAN policies |
| **SR OS DCGW** | `controlPlane: EVPN` | `target:100:100` | Positive stitch-RT matching; fabric EVPN does not leak to WAN by default |

**Important:** SRL and SROS policy syntax and RIC behaviour are **not interchangeable**. Designs are maintained per platform with conversion at the policy layer.

### 4.4 L3 DCI prerequisites (both platforms)

For L3 DCI virtual networks using stitch type-5 prefixes:

- Enable service-router BGP where required
- **Disable** IRB `hostRoutePopulate` and `evpnRouteAdvertisementType` on DCI vnets
- Use stitch RTs and optional loopback `/32` routes for reachability validation

### 4.5 RIC design rules (EDA constraints)

- On a single `RouterInterconnect`, use **either** `importTarget`/`exportTarget` **or** `importPolicy`/`exportPolicy` — **not both**
- Hub multi-RT import: community set aggregates spoke stitch RTs (e.g. RT 100 + 105)
- Spoke isolation: each spoke imports hub RT only — no spoke-to-spoke leakage

---

## 5. Example service catalogue (reference)

| Virtual network | Tier | Site | Stitch RT | Cross-DC reachability |
|-----------------|------|------|-----------|------------------------|
| vnet-1 | L3 IRB | DC1 | 100 | Hub DC2 (`vnet-2`) |
| vnet-2 | L3 hub | DC2 | 101 | All spokes |
| vnet-5 | L3 spoke | DC1 | 105 | Hub only |
| vnet-3 / vnet-4 | L2 BD | DC1 / DC2 | 300 / 301 | Same L2 subnet |
| vnet-6 / vnet-7 | L3 SH | DC1 / DC2 | 400 / 401 | Paired subnets |

*RT values are illustrative; final numbering follows customer IP/MPLS standards.*

---

## 6. Implementation methodology

### Phase 0 — Discovery and design (2–4 weeks)

- Current DC topology, WAN/MPLS capabilities, addressing, RT allocation
- Service catalogue (L2/L3, hub-spoke vs any-to-any)
- Platform selection (SRL vs SROS DCGW)
- EDA namespace model, RBAC, GitOps workflow

### Phase 1 — Foundation (2–3 weeks)

- EDA platform readiness (or integration with existing cluster)
- Underlay: OSPF, MPLS/LDP, DCGW system addressing
- WAN BGP peer mesh (full-mesh or redundant pairs)
- Baseline policies (deny-all WAN, then explicit stitch permits)

### Phase 2 — L3 DCI pilot (3–4 weeks)

- Deploy hub-spoke or any-to-any L3 vnets
- Configure RICs and WAN VPN-IPv4 policies
- Validate: DCGW loopback ping, client cross-DC ping, negative tests (spoke isolation)

### Phase 3 — L2 DCI / advanced (optional, 3–4 weeks)

- Bridge domain interconnect + selective WAN EVPN
- Multi-homed access (ES modes)
- Subject to **platform validation** and customer risk sign-off

### Phase 4 — Hardening and handover (2 weeks)

- Documentation, runbooks, monitoring hooks
- Operations training
- Production change window support

---

## 7. Test and acceptance criteria

| Test | Pass criteria |
|------|---------------|
| **Control-plane** | Remote DCGW loopback reachable from local service router |
| **L3 hub-spoke** | Spoke client → hub client bidirectional; spoke ↔ spoke blocked |
| **L3 any-to-any** | Reciprocal client ping across DCs |
| **L2 extension** | Same-subnet hosts ping across DCs; no unintended L3 routing |
| **WAN isolation** | Remote fabric system/VTEP routes **not** present in WAN RIB |
| **Redundancy** | Failover on secondary WAN link; no routing loops (SOO/tags) |
| **Automation** | Full service reprovisioned from Git manifests via EDA transaction |

---

## 8. Deliverables

| # | Deliverable |
|---|-------------|
| 1 | DCI High-Level Design (HLD) — topology, RT plan, policy matrix |
| 2 | Low-Level Design (LLD) — EDA CR catalogue per namespace |
| 3 | Git repository — manifests, policies, apply scripts |
| 4 | Test plan and results pack |
| 5 | Operations runbook — add/change/withdraw vnet, WAN maintenance |
| 6 | Knowledge transfer sessions (design, operations, troubleshooting) |

---

## 9. Assumptions and dependencies

- Customer provides MPLS-capable WAN between DCGW pairs (or equivalent LDP-enabled transport)
- Nokia EDA release aligned with target DCGW platform versions (SR Linux / SR OS)
- IP addressing, RT/SOO allocation, and security zoning agreed before build
- EDA cluster meets Nokia platform requirements for production — see [EDA Software Installation Guide](https://docs.eda.dev/latest/software-install/)
- Customer change-management and back-out procedures for WAN BGP policy updates

---

## 10. Risks and mitigations

| Risk | Mitigation |
|------|------------|
| **L2 DCI on shared WAN peers** increases EVPN exposure | Phase separately; restrict to type-2/3 + stitch RTs; full security review |
| **SRL vs SROS policy divergence** | Maintain platform-specific policy repos; no copy-paste between labs |
| **EVPN RIC on SROS** — EDA reconcile edge cases | Prefer validated IPVPN RIC path on SRL for production L3 until release-qualified |
| **IRB host-route leakage** | Standard prerequisite patch: disable hostRoutePopulate on DCI vnets |
| **Scale / HA** | Size DCGW count, WAN peer redundancy, and EDA namespace model in HLD |

---

## 11. Why EDA for DCI

| Capability | Benefit |
|------------|---------|
| **Declarative services** | Virtual networks and interconnects modelled as CRs — repeatable across DCs |
| **Policy abstraction** | Routing policies referenced by BGP peers and RICs — centralised WAN rules |
| **Multi-platform** | Same automation framework for SRL and SROS DCGWs |
| **GitOps-ready** | Version-controlled manifests, transaction-based apply, audit trail |
| **Integrated fabric** | Fabric, MPLS, BGP, and services in one platform — not siloed device config |

---

## 12. Team and experience

[Organisation] has hands-on experience implementing DCI on Nokia EDA in lab and pilot environments, including:

- **SRL IPVPN RIC** hub-spoke L3 DCI (validated cross-DC client connectivity)
- **SROS EVPN RIC** DCGW policies with hybrid WAN (VPN-IPv4 + EVPN)
- L2 bridge-domain interconnect and multi-homed access patterns
- EDA transaction workflows, platform restore, and Containerlab integration

References and case studies: [on request]

---

## Related lab documentation

| Document | Path |
|----------|------|
| Service model alignment | `docs/DCI-ALIGNMENT.md` |
| L3 IPVPN policy map | `docs/L3VPN-DCI-GUIDE.md` |
| L2 BDI / WAN EVPN | `docs/L2-DCI-GUIDE.md` |
| SROS EVPN variant | `~/Documents/eda-dci-sros-lab/docs/SROS-EVPN-DCI-GUIDE.md` |

---

## Production positioning notes

- Lead with **L3 IPVPN hub-spoke** as the production-aligned path.
- Position **L2 hybrid WAN EVPN** as optional/pilot unless Nokia release notes qualify it for the target version.
- Customise RT numbering, timelines, and team credentials before customer submission.

**Contact:** [Name, role, email, phone]
