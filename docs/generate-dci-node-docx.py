#!/usr/bin/env python3
"""Generate DCI Technical Node Documentation Word file."""
from pathlib import Path

try:
    from docx import Document
    from docx.shared import Inches, Pt
    from docx.enum.text import WD_ALIGN_PARAGRAPH
except ImportError:
    raise SystemExit("Install python-docx: pip install python-docx")

OUT = Path(__file__).resolve().parent / "DCI-Technical-Node-Documentation.docx"

ENV = [
    ("EDA UI", "https://100.124.186.55"),
    ("SSH / kubectl", "nokia@100.124.186.51"),
    ("Namespace", "clab-srl-leaf-spine-dcgw"),
    ("CLAB name", "srl-leaf-spine-dcgw"),
    ("Mgmt subnet", "172.65.10.0/24"),
]

FABRIC = [
    ["srl-leaf-1", "DC1", "leaf", "ixr-d2l", "172.65.10.100", "pod-1"],
    ["srl-leaf-2", "DC1", "leaf", "ixr-d2l", "172.65.10.101", "pod-1"],
    ["srl-leaf-3", "DC1", "leaf", "ixr-d3l", "172.65.10.102", "pod-1"],
    ["srl-leaf-4", "DC1", "leaf", "ixr-d3l", "172.65.10.103", "pod-1"],
    ["srl-spine-1", "DC1", "spine", "ixr-d4", "172.65.10.104", "pod-1"],
    ["srl-spine-2", "DC1", "spine", "ixr-d4", "172.65.10.105", "pod-1"],
    ["srl-leaf-5", "DC2", "leaf", "ixr-d2l", "172.65.10.106", "pod-2"],
    ["srl-leaf-6", "DC2", "leaf", "ixr-d2l", "172.65.10.107", "pod-2"],
    ["srl-leaf-7", "DC2", "leaf", "ixr-d3l", "172.65.10.108", "pod-2"],
    ["srl-leaf-8", "DC2", "leaf", "ixr-d3l", "172.65.10.109", "pod-2"],
    ["srl-spine-3", "DC2", "spine", "ixr-d4", "172.65.10.110", "pod-2"],
    ["srl-spine-4", "DC2", "spine", "ixr-d4", "172.65.10.111", "pod-2"],
    ["dcgw-1", "DC1", "dcgw", "ixr-x1b", "172.65.10.200", "pod-1"],
    ["dcgw-2", "DC1", "dcgw", "ixr-x1b", "172.65.10.201", "pod-1"],
    ["dcgw-3", "DC2", "dcgw", "ixr-x1b", "172.65.10.202", "pod-2"],
    ["dcgw-4", "DC2", "dcgw", "ixr-x1b", "172.65.10.203", "pod-2"],
    ["sros-pe-1", "WAN", "pe", "sr-1", "172.65.10.204", "backbone"],
    ["sros-pe-2", "WAN", "pe", "sr-1", "172.65.10.205", "backbone"],
]

SERVICES = [
    ["vnet-1", "L3 IRB", "bd-1", "172.16.101.0/24", "target:1:100", "65401:2", "RouterInterconnect", "IPVPN-MPLS", "DC1 native → DC2"],
    ["vnet-2", "L3 IRB", "bd-2", "172.16.201.0/24", "target:1:103", "65402:2", "RouterInterconnect", "IPVPN-MPLS", "DC2 native → DC1"],
    ["vnet-3", "L2 BD", "bd-3", "172.16.103.0/24", "target:1:104", "EVI 104 / 110", "BridgeDomainInterconnect", "EVPN-MPLS", "DC1 native → DC2"],
    ["vnet-4", "L2 BD", "bd-4", "172.16.105.0/24", "target:1:105", "EVI 105 / 111", "BridgeDomainInterconnect", "EVPN-MPLS", "DC2 native → DC1"],
]

CLIENTS = [
    ["client-vnet-1-dc1", "DC1", "172.16.101.1", "vnet-1", "L3 native", "leaf-1 e1-5", "client-vnet-1-dc2"],
    ["client-vnet-1-dc2", "DC2", "172.16.101.2", "vnet-1", "L3 stretched", "leaf-8 e1-6", "client-vnet-1-dc1"],
    ["client-vnet-2-dc2", "DC2", "172.16.201.1", "vnet-2", "L3 native", "leaf-5 e1-5", "client-vnet-2-dc1"],
    ["client-vnet-2-dc1", "DC1", "172.16.201.2", "vnet-2", "L3 stretched", "leaf-3 e1-5", "client-vnet-2-dc2"],
    ["client-vnet-3-dc1", "DC1", "172.16.103.1", "vnet-3", "L2 native", "leaf-2 e1-6", "client-vnet-3-dc2"],
    ["client-vnet-3-dc2", "DC2", "172.16.103.2", "vnet-3", "L2 stretched", "leaf-6 e1-6", "client-vnet-3-dc1"],
    ["client-vnet-4-dc2", "DC2", "172.16.105.1", "vnet-4", "L2 native", "leaf-5 e1-6", "client-vnet-4-dc1"],
    ["client-vnet-4-dc1", "DC1", "172.16.105.2", "vnet-4", "L2 stretched", "leaf-4 e1-6", "client-vnet-4-dc2"],
]

DCI_PEERS = [
    ["dcgw-1 ↔ dcgw-3", "Primary", "export-wan-routes-only-dc-1", "import-dci-services-dc-1"],
    ["dcgw-2 ↔ dcgw-4", "Secondary + SOO", "export-dc-1-routes-and-add-soo", "import-dci-services-dc-1"],
    ["dcgw-3 ↔ dcgw-1", "Primary", "export-wan-routes-only-dc-2", "import-dci-services-dc-2"],
    ["dcgw-4 ↔ dcgw-2", "Secondary + SOO", "export-dc-2-routes-and-add-soo", "import-dci-services-dc-2"],
]

PING = [
    ["L3 vnet-1", "client-vnet-1-dc1 → 172.16.101.2", "client-vnet-1-dc2 → 172.16.101.1"],
    ["L3 vnet-2", "client-vnet-2-dc2 → 172.16.201.2", "client-vnet-2-dc1 → 172.16.201.1"],
    ["L2 vnet-3", "client-vnet-3-dc1 → 172.16.103.2", "client-vnet-3-dc2 → 172.16.103.1"],
    ["L2 vnet-4", "client-vnet-4-dc2 → 172.16.105.2", "client-vnet-4-dc1 → 172.16.105.1"],
]


def add_table(doc, headers, rows):
    table = doc.add_table(rows=1, cols=len(headers))
    table.style = "Table Grid"
    hdr = table.rows[0].cells
    for i, h in enumerate(headers):
        hdr[i].text = h
    for row in rows:
        cells = table.add_row().cells
        for i, val in enumerate(row):
            cells[i].text = val
    doc.add_paragraph()


def main():
    doc = Document()
    title = doc.add_heading("EDA DCI Lab — Technical Node Documentation", 0)
    title.alignment = WD_ALIGN_PARAGRAPH.LEFT

    doc.add_paragraph(
        "Datacenter interconnect test lab on Talos EDA with Containerlab fabric "
        "srl-leaf-spine-dcgw. Documents fabric nodes, virtual networks, client "
        "attachments, DCI BGP policies, and cross-DC verification tests."
    )

    doc.add_heading("1. Environment", level=1)
    add_table(doc, ["Item", "Value"], ENV)

    doc.add_heading("2. Architecture summary", level=1)
    doc.add_paragraph(
        "Two site fabrics (DC1 pod-1 ASN 65401, DC2 pod-2 ASN 65402) connect via "
        "four DCGW nodes with MPLS-based DCI. L3 services use RouterInterconnect "
        "(EVPN-VXLAN on leaves, IPVPN-MPLS on DCGW). L2 services use "
        "BridgeDomainInterconnect (EVPN-MPLS on DCGW). WAN PE routers attach via "
        "backbone-simulation fabric."
    )

    doc.add_heading("3. Fabric and WAN nodes", level=1)
    add_table(
        doc,
        ["Node", "Site", "Role", "Platform", "Mgmt IPv4", "Fabric"],
        FABRIC,
    )

    doc.add_heading("4. Virtual networks and DCI", level=1)
    add_table(
        doc,
        ["VNet", "Tier", "BD", "Subnet", "RT", "RD/EVI", "Interconnect CR", "DCGW CP", "Stretch"],
        SERVICES,
    )

    doc.add_heading("5. Client attachment matrix", level=1)
    doc.add_paragraph(
        "Each vnet uses a dedicated test subnet. Cross-DC tests pair the same vnet "
        "on both sites (same broadcast domain / IRB prefix via stitch)."
    )
    add_table(
        doc,
        ["Client", "Site", "Service IP", "VNet", "Leg", "Leaf / port", "Cross-DC peer"],
        CLIENTS,
    )

    doc.add_heading("6. Port conventions", level=1)
    doc.add_paragraph("e1-5 — L3 IRB edges (vnet-1 on DC1 leaves, vnet-2 on DC2 leaves).")
    doc.add_paragraph("e1-6 — L2 bridge edges (vnet-3 DC1, vnet-4 DC2) plus stretched L3/L2 legs.")
    doc.add_paragraph("client-vnet-{N}-dc{X} — one single-homed client per vnet per DC (8 total).")

    doc.add_heading("7. DCI BGP peers and policies", level=1)
    add_table(doc, ["Peer pair", "Link role", "Export policy", "Import policy"], DCI_PEERS)
    doc.add_paragraph(
        "Loop avoidance: DC1 local routes use internal tag-10; DC2 local tag-20. "
        "Secondary links add SOO (soo-1122 / soo-2211). DCI peers enable EVPN and VPN-IPv4."
    )

    doc.add_heading("8. Verification tests", level=1)
    add_table(doc, ["Case", "Forward ping", "Reverse ping"], PING)
    doc.add_paragraph("Run on Talos host: bash eda-dci-lab/scripts/test-cross-dc-ping.sh")

    doc.add_heading("9. Deployment workflow", level=1)
    steps = [
        "Copy clab/clab-s-spine-spine-leaf-srl-only.yaml to ~/3-tier-dci and clab deploy.",
        "Register topology with EDA (fabric pod-1, pod-2, backbone-simulation).",
        "Apply services: bash eda-dci-lab/scripts/apply-all.sh",
        "Verify BGP on DCGW DCI peers (Established, EVPN + VPN-IPv4).",
        "Run cross-DC ping matrix.",
    ]
    for i, step in enumerate(steps, 1):
        doc.add_paragraph(f"{i}. {step}", style="List Number")

    doc.add_heading("10. Related paths", level=1)
    doc.add_paragraph("CLAB YAML: eda-dci-lab/clab/clab-s-spine-spine-leaf-srl-only.yaml")
    doc.add_paragraph("EDA bundle: eda-dci-lab/services/ (interconnect, policies, interface labels)")
    doc.add_paragraph("README: eda-dci-lab/README.md")

    doc.save(OUT)
    print(f"Written {OUT}")


if __name__ == "__main__":
    main()
