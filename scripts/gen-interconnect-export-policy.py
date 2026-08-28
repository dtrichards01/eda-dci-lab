#!/usr/bin/env python3
"""Generate SRL-safe interconnect export policy (1 EVPN route-type per statement)."""
from pathlib import Path

TEMPLATE = """# {title}
apiVersion: routingpolicies.eda.nokia.com/v1
kind: Policy
metadata:
  name: {name}
  namespace: clab-srl-leaf-spine-dcgw
  labels:
    eda.nokia.com/dci: l3-stitch
spec:
  defaultAction:
    policyResult: Reject
  statements:
{evpn_stmts}
    - name: export-local-ipvpn-stitch
      action:
        policyResult: Accept
      match:
        protocol: BGP_IPVPN
        bgp:
          communitySet: {community}
"""

EVPN = """    - name: export-local-evpn-type-{n}
      action:
        policyResult: Accept
      match:
        families:
          - EVPN
        bgp:
          communitySet: {community}
          evpnRouteTypes:
            - {n}
"""

OUT = Path(__file__).resolve().parents[1] / "services/dci-policies/policies"
for name, title, community in [
    ("export-dci-stitch-dc1-vnet-1", "vnet-1 interconnect export RT 100", "dci-rt-dc1-l3"),
    ("export-dci-stitch-dc2-hub", "hub interconnect export RT 101", "dci-rt-dc2-l3"),
    ("export-dci-stitch-vnet-5", "vnet-5 interconnect export RT 105", "dci-rt-vnet-5-stitch"),
]:
    evpn = "".join(EVPN.format(n=i, community=community) for i in range(1, 6))
    (OUT / f"{name}.yaml").write_text(
        TEMPLATE.format(title=title, name=name, community=community, evpn_stmts=evpn),
        encoding="utf-8",
    )
