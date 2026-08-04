#!/usr/bin/env python3
"""Generate EDA Interface + TopoLink CRs from clab-leaf-spine-dcgw-srl-only.yaml.

Workaround when clab-connector integration misses or mis-names breakout / fabric links.
Namespace: clab-srl-leaf-spine-dcgw

Outputs (in this directory):
  interfaces-isl.yaml, topolinks-isl.yaml   — leaf/spine + dcgw/spine + dcgw mesh
  interfaces-wan.yaml, topolinks-wan.yaml   — dcgw ↔ sros-pe + sros mesh
  topolinks-edge.yaml                       — linux clients → leaf (no client Interface CRs)
"""
from __future__ import annotations

import re
from pathlib import Path

import yaml

NS = "clab-srl-leaf-spine-dcgw"
HERE = Path(__file__).resolve().parent
CLAB_YAML = HERE.parent / "clab-leaf-spine-dcgw-srl-only.yaml"

E1_RE = re.compile(r"^e1-(\d+)$")
ETH_RE = re.compile(r"^eth(\d+)$")


def norm_iface(iface: str) -> str:
    m = E1_RE.match(iface)
    if m:
        return f"ethernet-1-{m.group(1)}"
    if iface.startswith("ethernet-"):
        return iface.replace("/", "-")
    if "/" in iface:
        return iface.replace("/", "-")
    return iface


def slash_iface(iface: str) -> str:
    """Native SRL slash form for TopoLink.interface when needed."""
    m = E1_RE.match(iface)
    if m:
        return f"ethernet-1/{m.group(1)}"
    if iface.startswith("ethernet-") and "-" in iface[9:]:
        parts = iface.split("-")
        if len(parts) >= 3 and parts[0] == "ethernet" and parts[1] == "1":
            return "ethernet-1/" + "/".join(parts[2:])
    return iface


def iface_cr_name(node: str, iface: str) -> str:
    return f"{node}-{norm_iface(iface)}"


def topolink_name(a_node: str, a_if: str, b_node: str, b_if: str) -> str:
    return f"{iface_cr_name(a_node, a_if)}--{iface_cr_name(b_node, b_if)}"


def node_role(nodes: dict, name: str) -> str:
    node = nodes.get(name, {})
    labels = node.get("labels") or {}
    return labels.get("role", "")


def iface_doc(node: str, clab_iface: str, role: str | None = None) -> dict:
    norm = norm_iface(clab_iface)
    meta: dict = {"name": iface_cr_name(node, clab_iface), "namespace": NS}
    if role:
        meta["labels"] = {"eda.nokia.com/role": role}
    return {
        "apiVersion": "interfaces.eda.nokia.com/v1",
        "kind": "Interface",
        "metadata": meta,
        "spec": {
            "enabled": True,
            "encapType": "Null",
            "ethernet": {"stormControl": {}},
            "lldp": True,
            "members": [
                {
                    "enabled": True,
                    "interface": norm,
                    "lacpPortPriority": 32768,
                    "node": node,
                }
            ],
            "type": "Interface",
        },
    }


def topolink_doc(
    local_node: str,
    local_if: str,
    remote_node: str,
    remote_if: str,
    link_type: str,
    remote_interface_resource: str | None = None,
    speed: str | None = None,
) -> dict:
    local_norm = norm_iface(local_if)
    remote_norm = norm_iface(remote_if)
    local_res = iface_cr_name(local_node, local_if)
    remote_res = remote_interface_resource or iface_cr_name(remote_node, remote_if)
    link: dict = {
        "local": {
            "node": local_node,
            "interface": local_norm,
            "interfaceResource": local_res,
        },
        "remote": {
            "node": remote_node,
            "interface": remote_norm,
            "interfaceResource": remote_res,
        },
        "type": link_type,
    }
    if speed:
        link["speed"] = speed
    role_label = "edge" if link_type == "edge" else "interSwitch"
    return {
        "apiVersion": "core.eda.nokia.com/v1",
        "kind": "TopoLink",
        "metadata": {
            "name": topolink_name(local_node, local_if, remote_node, remote_if),
            "namespace": NS,
            "labels": {"eda.nokia.com/role": role_label},
        },
        "spec": {"links": [link]},
    }


def classify_link(
    nodes: dict, a_node: str, a_if: str, b_node: str, b_if: str
) -> tuple[str, str, str, str, str, str | None, str | None]:
    """Return local_node, local_if, remote_node, remote_if, link_type, remote_res, speed."""
    a_role = node_role(nodes, a_node)
    b_role = node_role(nodes, b_node)

    # Linux client edge: leaf/dcgw local, client remote (eth1/eth2 — no Interface CR)
    if a_role == "client":
        return b_node, b_if, a_node, a_if, "edge", norm_iface(a_if), None
    if b_role == "client":
        return a_node, a_if, b_node, b_if, "edge", norm_iface(b_if), None

    # WAN: dcgw ↔ sros
    if "sros" in a_node or "sros" in b_node:
        if "dcgw" in a_node:
            dcgw, d_if, sros, s_if = a_node, a_if, b_node, b_if
        else:
            dcgw, d_if, sros, s_if = b_node, b_if, a_node, a_if
        return dcgw, d_if, sros, s_if, "interSwitch", None, "100G"

    # Spine ISL: spine local, leaf/dcgw remote (matches ai-backend-fabric convention)
    if a_role == "spine":
        return a_node, a_if, b_node, b_if, "interSwitch", None, "400G"
    if b_role == "spine":
        return b_node, b_if, a_node, a_if, "interSwitch", None, "400G"

    # dcgw mesh / other fabric: stable ordering by node name
    if a_node < b_node:
        return a_node, a_if, b_node, b_if, "interSwitch", None, "100G"
    return b_node, b_if, a_node, a_if, "interSwitch", None, "100G"


def dump_docs(path: Path, docs: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as f:
        for doc in docs:
            f.write("---\n")
            text = yaml.dump(
                doc,
                default_flow_style=False,
                sort_keys=False,
                indent=2,
                allow_unicode=True,
            )
            if "members:" in text:
                text = text.replace("\n  members:\n  - ", "\n  members:\n    - ")
                text = text.replace("\n    interface:", "\n      interface:")
                text = text.replace("\n    lacpPortPriority:", "\n      lacpPortPriority:")
                text = text.replace("\n    node:", "\n      node:")
            f.write(text)


def main() -> None:
    with CLAB_YAML.open(encoding="utf-8") as f:
        topo = yaml.safe_load(f)

    nodes = topo.get("topology", {}).get("nodes", {})
    links = topo.get("topology", {}).get("links", [])

    isl_interfaces: dict[tuple[str, str], dict] = {}
    wan_interfaces: dict[tuple[str, str], dict] = {}
    isl_topolinks: list[dict] = []
    wan_topolinks: list[dict] = []
    edge_topolinks: list[dict] = []

    for raw in links:
        a_ep, b_ep = raw["endpoints"]
        a_node, a_if = a_ep.split(":", 1)
        b_node, b_if = b_ep.split(":", 1)

        local_n, local_if, remote_n, remote_if, ltype, remote_res, speed = classify_link(
            nodes, a_node, a_if, b_node, b_if
        )

        if ltype == "edge":
            edge_topolinks.append(
                topolink_doc(
                    local_n,
                    local_if,
                    remote_n,
                    remote_if,
                    "edge",
                    remote_interface_resource=remote_res,
                )
            )
            continue

        is_wan = "sros" in local_n or "sros" in remote_n
        iface_bucket = wan_interfaces if is_wan else isl_interfaces
        tl_bucket = wan_topolinks if is_wan else isl_topolinks

        for node, ifs in ((local_n, local_if), (remote_n, remote_if)):
            key = (node, ifs)
            if key not in iface_bucket:
                iface_bucket[key] = iface_doc(node, ifs, "interSwitch")

        tl_bucket.append(
            topolink_doc(local_n, local_if, remote_n, remote_if, ltype, speed=speed)
        )

    isl_iface_list = list(isl_interfaces.values())
    wan_iface_list = list(wan_interfaces.values())

    dump_docs(HERE / "interfaces-isl.yaml", isl_iface_list)
    dump_docs(HERE / "topolinks-isl.yaml", isl_topolinks)
    dump_docs(HERE / "interfaces-wan.yaml", wan_iface_list)
    dump_docs(HERE / "topolinks-wan.yaml", wan_topolinks)
    dump_docs(HERE / "topolinks-edge.yaml", edge_topolinks)

    print(f"namespace: {NS}")
    print(f"source: {CLAB_YAML}")
    print(f"isl: {len(isl_iface_list)} interfaces, {len(isl_topolinks)} topolinks")
    print(f"wan: {len(wan_iface_list)} interfaces, {len(wan_topolinks)} topolinks")
    print(f"edge: {len(edge_topolinks)} topolinks (leaf Interface CRs → services/interface-labels)")
    for name in (
        "interfaces-isl.yaml",
        "topolinks-isl.yaml",
        "interfaces-wan.yaml",
        "topolinks-wan.yaml",
        "topolinks-edge.yaml",
    ):
        print(f"written: {HERE / name}")


if __name__ == "__main__":
    main()
